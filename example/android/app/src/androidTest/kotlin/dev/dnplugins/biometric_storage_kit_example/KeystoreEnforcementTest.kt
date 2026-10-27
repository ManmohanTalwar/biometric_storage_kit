package dev.dnplugins.biometric_storage_kit_example

import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Run after the demo has stored its synthetic secret through the real plugin. */
@RunWith(AndroidJUnit4::class)
class KeystoreEnforcementTest {
    @Test fun productionKeysDenyUnauthenticatedCryptoAndPreserveCiphertext() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = java.io.File(context.noBackupFilesDir,"biometric_storage_kit")
        val before = directory.listFiles()?.filter { it.extension == "bin" }?.associate { it.name to it.readBytes() }.orEmpty()
        assertTrue("Store the demo secret through the plugin first", before.isNotEmpty())
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val aliases = store.aliases().toList().filter { it.startsWith("dev.dnplugins.biometric_storage_kit.") }
        assertTrue("Production plugin key must exist", aliases.isNotEmpty())
        for (alias in aliases) {
            val key = store.getKey(alias,null) as SecretKey
            val info = SecretKeyFactory.getInstance(key.algorithm,"AndroidKeyStore").getKeySpec(key,KeyInfo::class.java) as KeyInfo
            assertTrue(info.isUserAuthenticationRequired)
            assertTrue(info.userAuthenticationValidityDurationSeconds <= 0)
            assertEquals(KeyProperties.AUTH_BIOMETRIC_STRONG,info.userAuthenticationType)
            var denied = false
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE,key)
                cipher.doFinal("unauthenticated synthetic probe".toByteArray())
            } catch (_: java.security.GeneralSecurityException) { denied = true }
            assertTrue("A fresh cipher must not release output without its own biometric authorization", denied)
        }
        assertEquals(before.keys, directory.listFiles()?.filter { it.extension == "bin" }?.map { it.name }?.toSet())
        for ((name, bytes) in before) assertArrayEquals(bytes,java.io.File(directory,name).readBytes())
    }
}
