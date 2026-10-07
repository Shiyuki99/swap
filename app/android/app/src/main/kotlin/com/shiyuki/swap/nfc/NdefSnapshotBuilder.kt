package com.shiyuki.swap.nfc

/**
 * Builds NDEF message bytes (single URI record) in pure Kotlin so the exact
 * bytes stay unit-testable without Robolectric. This replaces the old
 * pub-cache sed patch that created URI records inside the flutter_nfc_hce
 * plugin, and is byte-equivalent to NdefRecord.createUri() for the same
 * prefix (NFC Forum URI prefix codes 0x00-0x04).
 *
 * Deliberately NO AAR: an AAR forces the tap intent to our package, but the
 * manifest has no NDEF_DISCOVERED filter (and the VIEW filter declares a
 * stale host), so taps died. URL-only lets the reader open the link.
 */
object NdefSnapshotBuilder {
    private const val TNF_WELL_KNOWN: Int = 0x01
    private const val FLAG_MB: Int = 0x80
    private const val FLAG_ME: Int = 0x40
    private const val FLAG_SR: Int = 0x10
    private val RTD_URI = byteArrayOf(0x55) // 'U'

    // NFC Forum URI prefix codes, most specific first.
    private val URI_PREFIXES = listOf(
        "https://www." to 0x02,
        "http://www." to 0x01,
        "https://" to 0x04,
        "http://" to 0x03,
    )

    /** Full NDEF file: 2-byte big-endian NLEN followed by the NDEF message. */
    fun buildNdefFile(url: String): ByteArray {
        val message = buildMessage(url)
        val nlen = byteArrayOf(
            ((message.size shr 8) and 0xFF).toByte(),
            (message.size and 0xFF).toByte(),
        )
        return nlen + message
    }

    /** Single URI record (MB and ME set): header 0xD1, the classic URI tag. */
    fun buildMessage(url: String): ByteArray =
        record(TNF_WELL_KNOWN, RTD_URI, uriPayload(url), mb = true, me = true)

    /** URI payload: 1-byte NFC Forum prefix code + UTF-8 remainder. */
    fun uriPayload(url: String): ByteArray {
        val match = URI_PREFIXES.firstOrNull { url.startsWith(it.first) }
        val prefixCode = match?.second ?: 0x00
        val body = if (match != null) url.removePrefix(match.first) else url
        return byteArrayOf(prefixCode.toByte()) + body.toByteArray(Charsets.UTF_8)
    }

    /**
     * NDEF short record: [MB|ME|SR|TNF, TYPE_LEN, PAYLOAD_LEN, TYPE...,
     * PAYLOAD...] with IL=0 and no ID field. Rejects payloads over 255 bytes
     * (SR limit).
     */
    fun record(tnf: Int, type: ByteArray, payload: ByteArray, mb: Boolean, me: Boolean): ByteArray {
        require(payload.size < 256) { "SR record payload must be < 256 bytes, was ${payload.size}" }
        var header = tnf and 0x07
        if (mb) header = header or FLAG_MB
        if (me) header = header or FLAG_ME
        header = header or FLAG_SR
        return byteArrayOf(header.toByte(), type.size.toByte(), payload.size.toByte()) + type + payload
    }
}
