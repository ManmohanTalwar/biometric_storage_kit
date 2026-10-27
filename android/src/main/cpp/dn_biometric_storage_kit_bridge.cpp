// Copyright 2026 the biometric_storage_kit contributors.
// SPDX-License-Identifier: Apache-2.0
#include <jni.h>
#include <atomic>
#include <dlfcn.h>
#include <cstdint>
#include <cstring>
#include <string>

static JavaVM* vm = nullptr;
static jclass bridge = nullptr;
static jmethodID initialize_method = nullptr;
static jmethodID main_thread_method = nullptr;
static jmethodID request_method = nullptr;
static jmethodID cancel_method = nullptr;
using Generation = uint64_t (*)();
using Dispatcher = void (*)(int64_t, int32_t, const char*);
static std::atomic<Generation> generation_fn{nullptr};
static uint64_t current_generation() {
  const auto fn = generation_fn.load(std::memory_order_acquire);
  return fn ? fn() : static_cast<uint64_t>(-1);
}
static void* core_handle = nullptr; // Kept alive for the cached symbol lifetime.
// Main-thread-only slot. Never copy it into queued native work.
static int64_t dispatcher_slot = 0;
static uint64_t dispatcher_generation = 0;

class Env {
 public:
  JNIEnv* value = nullptr;
  bool attached = false;
  Env() {
    if (!vm) return;
    jint status = vm->GetEnv(reinterpret_cast<void**>(&value), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
      attached = vm->AttachCurrentThread(&value, nullptr) == JNI_OK;
      if (!attached) value = nullptr;
    } else if (status != JNI_OK) value = nullptr;
  }
  ~Env() { if (attached) vm->DetachCurrentThread(); }
};

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* java_vm, void*) {
  vm = java_vm;
  Env env;
  if (!env.value) return JNI_ERR;
  jclass local = env.value->FindClass("dev/dnplugins/biometric_storage_kit/DNBiometricStorageKitBridge");
  if (!local) return JNI_ERR;
  bridge = static_cast<jclass>(env.value->NewGlobalRef(local));
  env.value->DeleteLocalRef(local);
  main_thread_method = env.value->GetStaticMethodID(bridge, "isMainThread", "()Z");
  initialize_method = env.value->GetStaticMethodID(bridge, "initialize", "(Z)V");
  request_method = env.value->GetStaticMethodID(bridge, "request", "(J[B)V");
  cancel_method = env.value->GetStaticMethodID(bridge, "cancel", "(J)V");
  if (!main_thread_method || !initialize_method || !request_method || !cancel_method || env.value->ExceptionCheck()) return JNI_ERR;
  return JNI_VERSION_1_6;
}

static bool on_main(JNIEnv* env) {
  if (!env || !bridge || !main_thread_method) return false;
  const bool result = env->CallStaticBooleanMethod(bridge, main_thread_method) == JNI_TRUE;
  if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
  return result;
}

extern "C" JNIEXPORT int32_t DNBiometricStorageKitInitialize(int64_t pointer, int32_t new_session) {
  Env env;
  if (!on_main(env.value)) return 1;
  if (!generation_fn.load(std::memory_order_acquire)) {
    auto resolved = reinterpret_cast<Generation>(dlsym(RTLD_DEFAULT, "DN_IsolateGen"));
    if (!resolved) {
      // JVM-loaded libraries may be RTLD_LOCAL. Resolve once from the existing
      // runtime, then publish atomically; worker liveness reads never see a gap.
      if (!core_handle) core_handle = dlopen("libdartnative_android.so", RTLD_NOW | RTLD_NOLOAD);
      if (core_handle) resolved = reinterpret_cast<Generation>(dlsym(core_handle, "DN_IsolateGen"));
    }
    if (!resolved) return 2;
    generation_fn.store(resolved, std::memory_order_release);
  }
  const bool reset = !dispatcher_slot || dispatcher_generation != current_generation();
  dispatcher_generation = current_generation();
  dispatcher_slot = pointer;
  env.value->CallStaticVoidMethod(bridge, initialize_method, static_cast<jboolean>(new_session != 0 || reset));
  if (env.value->ExceptionCheck()) { env.value->ExceptionClear(); dispatcher_slot = 0; return 3; }
  return reset && new_session == 0 ? 4 : 0;
}

extern "C" JNIEXPORT int32_t DNBiometricStorageKitRequest(int64_t token, const char* payload) {
  Env env;
  if (!on_main(env.value) || !payload || !dispatcher_slot || !generation_fn.load(std::memory_order_acquire) || dispatcher_generation != current_generation()) return 1;
  const size_t length = std::strlen(payload);
  if (length > 1024 * 1024) return 1;
  jbyteArray bytes = env.value->NewByteArray(static_cast<jsize>(length));
  if (!bytes) { env.value->ExceptionClear(); return 1; }
  env.value->SetByteArrayRegion(bytes, 0, static_cast<jsize>(length), reinterpret_cast<const jbyte*>(payload));
  if (!env.value->ExceptionCheck()) env.value->CallStaticVoidMethod(bridge, request_method, static_cast<jlong>(token), bytes);
  env.value->DeleteLocalRef(bytes);
  if (env.value->ExceptionCheck()) { env.value->ExceptionClear(); return 1; }
  return 0;
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_dnplugins_biometric_1storage_1kit_DNBiometricStorageKitBridge_generation(JNIEnv*, jclass) {
  return static_cast<jlong>(current_generation());
}
extern "C" JNIEXPORT void JNICALL
Java_dev_dnplugins_biometric_1storage_1kit_DNBiometricStorageKitBridge_resetDispatcher(JNIEnv*, jclass) {
  dispatcher_slot = 0;
}
extern "C" JNIEXPORT jboolean JNICALL
Java_dev_dnplugins_biometric_1storage_1kit_DNBiometricStorageKitBridge_deliver(
    JNIEnv* env, jclass, jlong token, jint kind, jbyteArray payload) {
  if (!generation_fn.load(std::memory_order_acquire) || dispatcher_generation != current_generation() || !dispatcher_slot || !payload) return JNI_FALSE;
  const jsize length = env->GetArrayLength(payload);
  std::string text(static_cast<size_t>(length), '\0');
  env->GetByteArrayRegion(payload, 0, length, reinterpret_cast<jbyte*>(text.data()));
  if (env->ExceptionCheck()) { env->ExceptionClear(); return JNI_FALSE; }
  // Kotlin calls only on the main Looper; generation is rechecked at every fire.
  reinterpret_cast<Dispatcher>(dispatcher_slot)(token, kind, text.c_str());
  return JNI_TRUE;
}

extern "C" JNIEXPORT void DNBiometricStorageKitCancel(int64_t token) {
  Env env;
  if (!on_main(env.value) || !generation_fn.load(std::memory_order_acquire) || dispatcher_generation != current_generation()) return;
  env.value->CallStaticVoidMethod(bridge, cancel_method, static_cast<jlong>(token));
  if (env.value->ExceptionCheck()) env.value->ExceptionClear();
}
