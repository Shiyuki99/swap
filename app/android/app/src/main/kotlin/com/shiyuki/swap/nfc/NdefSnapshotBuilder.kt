package com.shiyuki.swap.nfc

/**
 * Builds NDEF message bytes (URI + AAR) in pure Kotlin so the exact bytes
 * stay unit-testable without Robolectric. This replaces the old pub-cache
 * sed patch that created URI records inside the flutter_nfc_hce plugin.
 */
object NdefSnapshotBuilder {
    private const val TNF_WELL_KNOWN: Int = 0x01
    private const val TNF_EXTERNAL_TYPE: Int = 0x04
    private const val FLAG_MB: Int = 0x80
    private const val FLAG_ME: Int = 0x40
    private const val FLAG_SR: Int = 0x10
    private val RTD_URI = byteArrayOf(0x55) // 'U'
    private val RTD_ANDROID_PKG = "android.com:pkg".toByteArray(Charsets.US_ASCII)

    // NFC Forum URI prefix codes, most specific first.
    private val URI_PREFIXES = listOf(
        "https://www." to 0x02,
        "http://www." to 0x01,
        "https://" to 0x04,
        "http://" to 0x03,
    )

    /** Full NDEF file: 2-byte big-endian NLEN followed by the NDEF message. */
    fun buildNdefFile(url: String, packageName: String): ByteArray {
        val message = buildMessage(url, packageName)
        val nlen = byteArrayOf(
            ((message.size shr 8) and 0xFF).toByte(),
            (message.size and 0xFF).toByte(),
        )
        return nlen + message
    }

    /** URI record first (MB set) + AAR record last (ME set). */
    fun buildMessage(url: String, packageName: String): ByteArray {
        val uriRecord = record(TNF_WELL_KNOWN, RTD_URI, uriPayload(url), mb = true, me = false)
        val aarRecord = record(
            TNF_EXTERNAL_TYPE,
            RTD_ANDROID_PKG,
            packageName.toByteArray(Charsets.US_ASCII),
            mb = false,
            me = true,
        )
        return uriRecord + aarRecord
    }

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
