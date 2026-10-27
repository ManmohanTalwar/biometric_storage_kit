// The native side of biometric_storage_kit on Android: the C functions Dart calls.
//
// Dart opens libbiometric_storage_kit.so (lib/src/biometric_storage_kit_bindings.dart) and
// looks these functions up by name, the same names as the iOS bridge. Each one
// crosses into Kotlin over JNI, where the Android APIs are
// (dev.dnplugins.biometric_storage_kit.DNBiometricStorageKitBridge).
//
// To add a function: an `extern "C"` function here, a @Keep @JvmStatic
// method in the Kotlin bridge with its method id resolved in JNI_OnLoad
// below, a lookup in the Dart bindings, and the same function in the iOS
// bridge. The plugin's README walks through one that takes a string, with
// its JNI signature.

#include <jni.h>
#include <android/log.h>
#include <cstdlib>
#include <cstring>

#define LOG_TAG "BiometricStorageKit"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static JavaVM*   g_vm = nullptr;
static jclass    g_bridge = nullptr;
static jmethodID g_platformVersion = nullptr;

// Runs when BiometricStorageKitPlugin.kt loads this library, on the Android main
// thread. The bridge class is resolved here and not later on purpose:
// FindClass from a Dart thread sees only the system class loader and would
// not find the app's classes.
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        LOGE("JNI_OnLoad: GetEnv failed");
        return JNI_ERR;
    }
    jclass local = env->FindClass("dev/dnplugins/biometric_storage_kit/DNBiometricStorageKitBridge");
    if (local == nullptr) {
        env->ExceptionClear();
        LOGE("JNI_OnLoad: DNBiometricStorageKitBridge not found");
        return JNI_VERSION_1_6;
    }
    g_bridge = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    g_platformVersion = env->GetStaticMethodID(g_bridge, "platformVersion", "()Ljava/lang/String;");
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        g_platformVersion = nullptr;
        LOGE("JNI_OnLoad: DNBiometricStorageKitBridge.platformVersion not found");
    }
    return JNI_VERSION_1_6;
}

// A JNIEnv for the calling thread, attaching it first when it is a Dart
// thread the VM has never seen.
static JNIEnv* envForThisThread(bool* attached) {
    *attached = false;
    if (g_vm == nullptr) return nullptr;
    JNIEnv* env = nullptr;
    const jint state = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (state == JNI_OK) return env;
    if (state == JNI_EDETACHED && g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
        *attached = true;
        return env;
    }
    return nullptr;
}

// The operating system and its version, "Android 15", as a pointer to a C
// string this file keeps for the life of the app, so Dart never frees it.
extern "C" JNIEXPORT const char* DNBiometricStorageKitPlatformVersion() {
    static const char* cached = nullptr;
    if (cached != nullptr) return cached;

    bool attached = false;
    JNIEnv* env = envForThisThread(&attached);
    const char* result = "";
    if (env != nullptr && g_bridge != nullptr && g_platformVersion != nullptr) {
        auto text = static_cast<jstring>(env->CallStaticObjectMethod(g_bridge, g_platformVersion));
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            text = nullptr;
        }
        if (text != nullptr) {
            const char* chars = env->GetStringUTFChars(text, nullptr);
            if (chars != nullptr) {
                result = strdup(chars);
                env->ReleaseStringUTFChars(text, chars);
            }
            env->DeleteLocalRef(text);
        }
    }
    if (attached) g_vm->DetachCurrentThread();
    if (result[0] != '\0') cached = result;
    return result;
}
