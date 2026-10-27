// Copyright 2026 the biometric_storage_kit contributors.
// SPDX-License-Identifier: Apache-2.0
package dev.dnplugins.biometric_storage_kit

import android.app.Activity
import android.app.Application
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import androidx.annotation.Keep
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import java.io.File
import java.io.FileOutputStream
import java.lang.ref.WeakReference
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.NoSuchFileException
import java.nio.file.LinkOption
import java.nio.file.attribute.BasicFileAttributes
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKeyFactory
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

@Keep
object DNBiometricStorageKitBridge {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var app: Application? = null
    private var host = WeakReference<FragmentActivity>(null)
    @Volatile private var session = 0L
    @Volatile private var active: Operation? = null
    // AndroidX owns one prompt callback per Activity. Keep it reserved until a
    // cancelled prompt acknowledges its terminal result, even after Dart settles.
    private var draining: Operation? = null
    private class Operation(val id: Long, val generation: Long, val session: Long) {
        val cancelled = AtomicBoolean(false)
        val authenticationCompleted = AtomicBoolean(false)
        var prompt: BiometricPrompt? = null
        var promptHost = WeakReference<FragmentActivity>(null)
    }
    private class Failure(val code: String, val nativeCode: Int? = null): Exception()
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity is FragmentActivity) host = WeakReference(activity)
        }
        override fun onActivityStopped(activity: Activity) {
            if (host.get() === activity) { active?.let { cancel(it.id) }; host.clear() }
        }
        override fun onActivityDestroyed(activity: Activity) {
            if (host.get() === activity) { active?.let { cancel(it.id) }; host.clear() }
            if (draining?.promptHost?.get() === activity) draining = null
        }
        override fun onActivityPaused(activity: Activity) {}
        override fun onActivityCreated(activity: Activity, state: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    }
    private fun retireDestroyedPrompt() {
        val owner = draining?.promptHost?.get()
        if (owner == null || owner.isDestroyed) draining = null
    }
    fun attach(application: Application) {
        retireDestroyedPrompt()
        app?.unregisterActivityLifecycleCallbacks(lifecycle)
        app = application; application.registerActivityLifecycleCallbacks(lifecycle)
    }
    fun detach() {
        active?.let { cancel(it.id) }
        app?.unregisterActivityLifecycleCallbacks(lifecycle); app = null; host.clear()
        resetDispatcher()
    }
    @JvmStatic fun isMainThread(): Boolean = Looper.myLooper() == Looper.getMainLooper()
    @JvmStatic external fun generation(): Long
    @JvmStatic external fun deliver(token: Long, kind: Int, payload: ByteArray): Boolean
    @JvmStatic external fun resetDispatcher()
    @JvmStatic fun initialize(newSession: Boolean) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (newSession) {
            session++
            active?.let { stop(it) }
            active = null
        }
    }
    private fun live(op: Operation) = !op.cancelled.get() && active === op &&
        op.session == session && op.generation == generation()
    private fun reply(id: Long, value: Any? = null, failure: Failure? = null) {
        check(Looper.myLooper() == Looper.getMainLooper())
        val result = if (failure == null) JSONObject().put("value", value ?: JSONObject.NULL)
            else JSONObject().put("error", JSONObject().put("code", failure.code)
                .put("message", "Protected storage operation failed (${failure.code}).")
                .put("nativeCode", failure.nativeCode ?: JSONObject.NULL))
        deliver(id,0,result.toString().toByteArray(Charsets.UTF_8))
    }
    private fun finish(op: Operation, value: Any? = null, failure: Failure? = null) {
        main.post {
            if (!live(op)) return@post
            active = null; op.prompt = null
            reply(op.id,value,failure)
        }
    }
    private fun stop(op: Operation) {
        op.cancelled.set(true)
        if (op.prompt != null && !op.authenticationCompleted.get()) draining = op
        op.prompt?.cancelAuthentication()
    }
    private fun drain(op: Operation): Boolean {
        if (draining !== op) return false
        draining = null; op.prompt = null
        return true
    }
    @JvmStatic fun cancel(id: Long) {
        check(Looper.myLooper() == Looper.getMainLooper())
        val op = active ?: return
        if (op.id != id) return
        active = null; stop(op)
        if (op.generation == generation()) reply(id,failure=Failure("cancelled"))
    }
    private fun required(q: JSONObject, key: String, limit: Int): String {
        val v = q.opt(key) as? String ?: throw Failure("invalid_request")
        if (v.isEmpty() || v.contains('\u0000') || RecordCodec.encodeText(v).size > limit) throw Failure("invalid_request")
        return v
    }
    private fun availability(application: Application): String = when (
        BiometricManager.from(application).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
        BiometricManager.BIOMETRIC_SUCCESS -> "available"
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "notEnrolled"
        BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE, BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "unavailable"
        else -> "unknown"
    }
    private fun mapError(error: Exception): Failure = when(error) {
        is Failure -> error
        is KeyPermanentlyInvalidatedException -> Failure("key_invalidated")
        is UserNotAuthenticatedException -> Failure("authentication_failed")
        is AEADBadTagException -> Failure("corrupt_data")
        is IllegalArgumentException, is java.nio.charset.CharacterCodingException -> Failure("corrupt_data")
        else -> Failure("storage_error")
    }
    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun key(store: KeyStore, alias: String, mayCreate: Boolean): SecretKey {
        if (store.containsAlias(alias)) {
            val existing = store.getKey(alias,null) as? SecretKey ?: throw Failure("key_missing")
            val info = SecretKeyFactory.getInstance(existing.algorithm,"AndroidKeyStore").getKeySpec(existing,KeyInfo::class.java) as KeyInfo
            if (!info.isUserAuthenticationRequired || info.userAuthenticationValidityDurationSeconds > 0) throw Failure("unsupported_key_policy")
            if (Build.VERSION.SDK_INT >= 30 && info.userAuthenticationType != KeyProperties.AUTH_BIOMETRIC_STRONG) throw Failure("unsupported_key_policy")
            return existing
        }
        if (!mayCreate) throw Failure("key_missing")
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= 30) builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        else @Suppress("DEPRECATION") builder.setUserAuthenticationValidityDurationSeconds(-1)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply { init(builder.build()) }.generateKey()
    }
    private fun persist(file: File, bytes: ByteArray, op: Operation) {
        if (!file.parentFile!!.isDirectory && !file.parentFile!!.mkdirs()) throw Failure("storage_error")
        val tmp = File.createTempFile(".pending-", ".bin", file.parentFile)
        try {
            FileOutputStream(tmp).use { it.write(bytes); it.fd.sync() }
            if (!live(op)) return
            // No non-atomic fallback; an unsupported/failed rename is an error.
            Files.move(tmp.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
        } finally { if (tmp.exists()) tmp.delete() }
    }
    @JvmStatic fun request(id: Long, bytes: ByteArray) {
        check(Looper.myLooper() == Looper.getMainLooper())
        retireDestroyedPrompt()
        val gen = generation(); val currentSession = session
        val text = String(bytes,Charsets.UTF_8)
        if (active != null || draining != null) {
            main.post {
                if (gen == generation() && currentSession == session) reply(id,failure=Failure("busy"))
            }
            return
        }
        // Reserve synchronously: cancel/dispose can arrive before main.post runs.
        val op = Operation(id,gen,currentSession); active = op
        main.post {
            if (!live(op)) return@post
            try {
                val application = app ?: throw Failure("engine_detached")
                val q = JSONObject(text)
                val command = required(q,"operation",32)
                if (command == "availability") { finish(op,availability(application)); return@post }
                if (command !in listOf("read","readLegacy","write","delete")) throw Failure("invalid_request")
                val name = required(q,"name",512); val namespace = required(q,"namespace",128)
                val title = required(q,"title",1024); val reason = required(q,"reason",1024)
                val cancelLabel = required(q,"cancelLabel",1024)
                val legacy = command == "readLegacy"
                if (legacy && (name.contains('/') || name.contains('\\') || name == "." || name == "..")) throw Failure("invalid_request")
                val value = if (command == "write") q.opt("value") as? String ?: throw Failure("invalid_request") else null
                if (value != null && RecordCodec.encodeText(value).size > RecordCodec.MAX_SECRET) throw Failure("invalid_request")
                if (command == "write") {
                    val available = availability(application)
                    if (available != "available") throw Failure(if (available == "notEnrolled") "not_enrolled" else "unavailable")
                }
                val identity = RecordCodec.identity(namespace,name)
                val digest = RecordCodec.digest(identity)
                val file = if (legacy) File(File(application.filesDir,"biometric_storage"),"$name.v2.txt")
                    else File(File(application.noBackupFilesDir,"biometric_storage_kit"),"$digest.bin")
                val alias = if (legacy) "_CM_${name}_master_key" else "dev.dnplugins.biometric_storage_kit.$digest"
                worker.execute {
                    if (!live(op)) return@execute
                    try {
                        val store = keyStore()
                        if (command == "delete") {
                            if (!live(op)) return@execute
                            // Delete ciphertext first, then its key; never on an error path.
                            Files.deleteIfExists(file.toPath())
                            if (!live(op)) return@execute
                            store.deleteEntry(alias); finish(op); return@execute
                        }
                        val attributes = try { Files.readAttributes(file.toPath(),BasicFileAttributes::class.java,LinkOption.NOFOLLOW_LINKS) }
                            catch (_: NoSuchFileException) { null }
                        val exists = attributes != null
                        if (!exists && command != "write") { finish(op); return@execute }
                        if (attributes != null && (!attributes.isRegularFile || attributes.size() > 65568)) throw Failure("corrupt_data")
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        val protectedKey = key(store,alias,command == "write" && !exists)
                        var ciphertext: ByteArray? = null
                        if (command == "write") cipher.init(Cipher.ENCRYPT_MODE,protectedKey)
                        else {
                            val decoded = RecordCodec.decode(file.readBytes(),legacy)
                            ciphertext = decoded.second
                            cipher.init(Cipher.DECRYPT_MODE,protectedKey,GCMParameterSpec(128,decoded.first))
                        }
                        val encrypted = ciphertext
                        main.post prompt@{
                            if (!live(op)) return@prompt
                            val activity = host.get()
                            if (activity == null || activity.isFinishing || activity.isDestroyed ||
                                !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) ||
                                activity.supportFragmentManager.isStateSaved) {
                                finish(op,failure=Failure("no_foreground_host")); return@prompt
                            }
                            val available = availability(application)
                            if (available != "available") {
                                finish(op,failure=Failure(if (available == "notEnrolled") "not_enrolled" else "unavailable")); return@prompt
                            }
                            val prompt = BiometricPrompt(activity,Executor { main.post(it) },object: BiometricPrompt.AuthenticationCallback() {
                                override fun onAuthenticationError(code: Int, message: CharSequence) {
                                    if (drain(op)) return
                                    if (!live(op) || !op.authenticationCompleted.compareAndSet(false,true)) return
                                    val category = when(code) {
                                        BiometricPrompt.ERROR_CANCELED, BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON -> "cancelled"
                                        BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "locked_out"
                                        BiometricPrompt.ERROR_NO_BIOMETRICS -> "not_enrolled"
                                        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "passcode_not_set"
                                        else -> "authentication_failed"
                                    }
                                    finish(op,failure=Failure(category,code))
                                }
                                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                                    if (drain(op)) return
                                    if (!live(op) || !op.authenticationCompleted.compareAndSet(false,true)) return
                                    val authenticated = result.cryptoObject?.cipher
                                    if (authenticated == null || authenticated !== cipher) {
                                        finish(op,failure=Failure("authentication_failed")); return
                                    }
                                    worker.execute crypto@{
                                        if (!live(op)) return@crypto
                                        try {
                                            // Keystore requires biometric authorization before
                                            // updateAAD as well as doFinal on per-use keys.
                                            if (!legacy) authenticated.updateAAD(RecordCodec.aad(identity))
                                            if (command == "write") {
                                                val plain = RecordCodec.encodeText(value!!)
                                                val output = try { authenticated.doFinal(plain) } finally { plain.fill(0) }
                                                if (!live(op)) return@crypto
                                                persist(file,RecordCodec.encode(authenticated.iv,output),op)
                                                finish(op)
                                            } else {
                                                val plain = authenticated.doFinal(encrypted!!)
                                                val resultText = try { RecordCodec.decodeText(plain) } finally { plain.fill(0) }
                                                finish(op,resultText)
                                            }
                                        } catch (error: Exception) { finish(op,failure=mapError(error)) }
                                    }
                                }
                                // A mismatch is retryable. No secret is released here.
                                override fun onAuthenticationFailed() {}
                            })
                            op.promptHost = WeakReference(activity)
                            op.prompt = prompt
                            try {
                                val info = BiometricPrompt.PromptInfo.Builder().setTitle(title).setDescription(reason)
                                    .setNegativeButtonText(cancelLabel)
                                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).build()
                                prompt.authenticate(info,BiometricPrompt.CryptoObject(cipher))
                            } catch (error: Exception) {
                                op.prompt = null
                                finish(op,failure=mapError(error))
                            }
                        }
                    } catch (error: Exception) { finish(op,failure=mapError(error)) }
                }
            } catch (error: Exception) { finish(op,failure=mapError(error)) }
        }
    }
}
