package com.shiyuki.swap.nfc

import java.security.SecureRandom
import java.util.Base64

/** Generates URL-safe 128-bit tokens for the native pending session pair. */
object NfcSessionGenerator {
    private const val TOKEN_BYTES = 16 // 128 bits

    data class SessionPair(val sessionId: String, val sessionSecret: String)

    fun generate(): SessionPair {
        val random = SecureRandom()
        val id = ByteArray(TOKEN_BYTES)
        random.nextBytes(id)
        val secret = ByteArray(TOKEN_BYTES)
        random.nextBytes(secret)
        return SessionPair(encode(id), encode(secret))
    }

    fun encode(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}
