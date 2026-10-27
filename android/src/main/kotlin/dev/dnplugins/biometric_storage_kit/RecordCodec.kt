// Copyright 2026 the biometric_storage_kit contributors.
// SPDX-License-Identifier: Apache-2.0
package dev.dnplugins.biometric_storage_kit
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

internal object RecordCodec {
    const val MAX_SECRET = 65536
    private val magic = byteArrayOf(0x42, 0x53, 0x4b, 1)
    fun identity(namespace: String, name: String): ByteArray {
        val a = encodeText(namespace); val b = encodeText(name)
        return ByteBuffer.allocate(8 + a.size + b.size).putInt(a.size).put(a).putInt(b.size).put(b).array()
    }
    fun digest(identity: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(identity).joinToString("") { "%02x".format(it.toInt() and 255) }
    fun aad(identity: ByteArray) = magic + identity
    fun encode(iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(iv.size == 12 && ciphertext.size in 16..(MAX_SECRET + 16))
        return magic + iv + ciphertext
    }
    fun decode(bytes: ByteArray, legacy: Boolean = false): Pair<ByteArray, ByteArray> {
        val prefix = if (legacy) 0 else magic.size
        require(bytes.size in (prefix + 12 + 16)..(prefix + 12 + MAX_SECRET + 16))
        if (!legacy) require(bytes.copyOfRange(0,4).contentEquals(magic))
        return Pair(bytes.copyOfRange(prefix,prefix+12),bytes.copyOfRange(prefix+12,bytes.size))
    }
    fun encodeText(value: String): ByteArray {
        val encoded = Charsets.UTF_8.newEncoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .encode(CharBuffer.wrap(value))
        return ByteArray(encoded.remaining()).also { encoded.get(it) }
    }
    fun decodeText(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes)).toString()
}
