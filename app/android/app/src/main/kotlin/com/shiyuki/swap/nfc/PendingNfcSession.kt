package com.shiyuki.swap.nfc

data class PendingNfcSession(
    val sessionId: String,
    val sessionSecret: String,
    val url: String,
    val createdAtMillis: Long,
    val expiresAtMillis: Long,
)
