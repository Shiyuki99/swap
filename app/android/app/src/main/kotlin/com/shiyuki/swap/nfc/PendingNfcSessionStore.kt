package com.shiyuki.swap.nfc

import java.net.URI
import java.net.URISyntaxException
import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide store for the pending native NFC session. AtomicReference
 * swaps make set/clear/active race-safe between the HCE service thread and
 * the Dart method channel thread calling into the main thread.
 */
class PendingNfcSessionStore(
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val current = AtomicReference<PendingNfcSession?>()

    /** Stores the session pair parsed from [url]; null when the URL is not a swap URL. */
    fun set(url: String): PendingNfcSession? {
        val parsed = parseSwapUrl(url) ?: return null
        val now = nowMillis()
        val session = PendingNfcSession(
            sessionId = parsed.first,
            sessionSecret = parsed.second,
            url = url,
            createdAtMillis = now,
            expiresAtMillis = now + ttlMillis,
        )
        current.set(session)
        return session
    }

    /** Returns the session only while it is inside its TTL window. */
    fun active(): PendingNfcSession? {
        val session = current.get() ?: return null
        if (nowMillis() >= session.expiresAtMillis) return null
        return session
    }

    fun clear() {
        current.set(null)
    }

    companion object {
        /** Matches the existing five-minute server session TTL (audit baseline). */
        const val DEFAULT_TTL_MILLIS: Long = 5L * 60L * 1000L

        /** Shared instance used by the HCE service and the method channel. */
        val shared = PendingNfcSessionStore()

        /** Parses https://host/view/:id?sig=:secret into (id, secret); null otherwise. */
        fun parseSwapUrl(url: String): Pair<String, String>? {
            val uri = try {
                URI(url)
            } catch (_: URISyntaxException) {
                return null
            }
            val segments = uri.path?.split('/')?.filter { it.isNotBlank() } ?: return null
            val viewIndex = segments.indexOf("view")
            if (viewIndex == -1 || viewIndex + 1 >= segments.size) return null
            val id = segments[viewIndex + 1]
            val secret = uri.rawQuery
                ?.split('&')
                ?.firstOrNull { it.startsWith("sig=") }
                ?.removePrefix("sig=")
            if (id.isBlank() || secret.isNullOrBlank()) return null
            return id to secret
        }
    }
}
