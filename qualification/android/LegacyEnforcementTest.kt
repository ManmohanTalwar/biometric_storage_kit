package dev.dnplugins.biometric_upgrade_fixture

import android.os.Build
import android.security.KeyStoreException
import android.security.keystore.UserNotAuthenticatedException
import android.security.keystore.KeyPermanentlyInvalidatedException
import javax.crypto.AEADBadTagException
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Requires actual legacy producer records and externally captured pre-upgrade hashes. */
@RunWith(AndroidJUnit4::class)
class LegacyEnforcementTest {
    private fun authenticationRequired(error: Throwable): Boolean =
        generateSequence(error) { it.cause }.any {
            it is UserNotAuthenticatedException ||
                (Build.VERSION.SDK_INT >= 33 && it is KeyStoreException && it.requiresUserAuthentication())
        }
    @Test fun denialClassifierRejectsCorruptionAndInvalidation() {
        assertTrue(authenticationRequired(java.security.GeneralSecurityException("wrapper", UserNotAuthenticatedException())))
        assertFalse(authenticationRequired(AEADBadTagException("wrong tag")))
        assertFalse(authenticationRequired(KeyPermanentlyInvalidatedException()))
        assertFalse(authenticationRequired(java.security.InvalidAlgorithmParameterException("wrong IV")))
    }

    @Test fun legacyRecordsRetainBytesAndRejectUnauthenticatedDecryption() {
        assertTrue("Requires API 33+ authentication error classification", Build.VERSION.SDK_INT >= 33)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val args = InstrumentationRegistry.getArguments()
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        for (name in listOf("dn-upgrade.aGVsbG8_", "dn-upgrade-empty", "dn-upgrade-text")) {
            val expected = requireNotNull(args.getString(name)) { "Missing original-producer hash: $name" }
            val file = File(context.filesDir, "biometric_storage/$name.v2.txt")
            val before = file.readBytes()
            fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
                .digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals("Legacy bytes must match pre-upgrade baseline", expected, hash(before))
            val key = store.getKey("_CM_${name}_master_key", null) as SecretKey
            val info = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                .getKeySpec(key, KeyInfo::class.java) as KeyInfo
            assertTrue(info.isUserAuthenticationRequired)
            assertTrue(info.userAuthenticationValidityDurationSeconds <= 0)
            assertEquals(KeyProperties.AUTH_BIOMETRIC_STRONG, info.userAuthenticationType)
            var denied = false
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, before.copyOfRange(0, 12)))
                cipher.doFinal(before.copyOfRange(12, before.size))
            } catch (error: java.security.GeneralSecurityException) {
                assertTrue("Expected auth-required, not corruption/invalidation/storage failure: $error", authenticationRequired(error))
                denied = true
            }
            assertTrue("Fresh decrypt must require its own biometric approval", denied)
            assertArrayEquals("Failed access must leave ciphertext unchanged", before, file.readBytes())
        }
    }
}
