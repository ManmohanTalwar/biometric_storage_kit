package dev.dnplugins.biometric_storage_kit
import org.junit.Assert.*
import org.junit.Test
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.AEADBadTagException

class RecordCodecTest {
    @Test fun malformedUnicodeCannotAliasAValidName() {
        for (text in listOf("\uD800", "\uDC00", "x\uD800y")) {
            assertThrows(java.nio.charset.CharacterCodingException::class.java) { RecordCodec.identity("demo",text) }
            assertThrows(java.nio.charset.CharacterCodingException::class.java) { RecordCodec.encodeText(text) }
        }
        assertEquals("📝",RecordCodec.decodeText(RecordCodec.encodeText("📝")))
    }
    @Test fun identityIsUnambiguous() {
        assertFalse(RecordCodec.identity("a","bc").contentEquals(RecordCodec.identity("ab","c")))
        assertEquals(64,RecordCodec.digest(RecordCodec.identity("नया","📝")).length)
    }
    @Test fun envelopeRejectsTruncationAndUnknownVersion() {
        for (size in 0..31) assertThrows(IllegalArgumentException::class.java) { RecordCodec.decode(ByteArray(size)) }
        assertThrows(IllegalArgumentException::class.java) { RecordCodec.decode(ByteArray(32)) }
    }
    @Test fun realGcmRoundtripAndWrongIdentityFails() {
        val key=SecretKeySpec(ByteArray(32){it.toByte()},"AES")
        val identity=RecordCodec.identity("demo","secret")
        val encrypt=Cipher.getInstance("AES/GCM/NoPadding");encrypt.init(Cipher.ENCRYPT_MODE,key)
        encrypt.updateAAD(RecordCodec.aad(identity))
        val envelope=RecordCodec.encode(encrypt.iv,encrypt.doFinal("नया 📝".toByteArray(Charsets.UTF_8)))
        val (iv,body)=RecordCodec.decode(envelope)
        fun decrypt(aad:ByteArray): ByteArray {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,iv));cipher.updateAAD(aad)
            return cipher.doFinal(body)
        }
        assertEquals("नया 📝",RecordCodec.decodeText(decrypt(RecordCodec.aad(identity))))
        assertThrows(AEADBadTagException::class.java) { decrypt(RecordCodec.aad(RecordCodec.identity("other","secret"))) }
        body[0]=(body[0].toInt() xor 1).toByte()
        assertThrows(AEADBadTagException::class.java) { decrypt(RecordCodec.aad(identity)) }
    }
    @Test fun legacyHasNoNewHeaderAndMalformedUtf8Fails() {
        val bytes=ByteArray(28){it.toByte()};val (iv,data)=RecordCodec.decode(bytes,true)
        assertArrayEquals(bytes.copyOfRange(0,12),iv);assertEquals(16,data.size)
        assertThrows(java.nio.charset.CharacterCodingException::class.java) { RecordCodec.decodeText(byteArrayOf(0xc3.toByte(),0x28)) }
    }
}
