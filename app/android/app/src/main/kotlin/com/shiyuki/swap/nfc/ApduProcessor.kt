package com.shiyuki.swap.nfc

/**
 * Pure-Kotlin NFC Forum Type 4 command processor. Serves the NDEF file
 * produced by [ndefFile]; when it returns null the service answers with a
 * valid capability container and an empty NDEF file (NLEN = 0) so readers
 * see a clean empty tag instead of a protocol error.
 *
 * Commands are dispatched by parsed fields (INS + data field + offset/Le),
 * not by whole-APDU equality: real readers vary CLA (0x00/0x80), P1
 * (0x00/0x04), short vs extended length headers, and the presence of the
 * trailing Le byte. Byte-exact matching silently dropped those readers.
 */
class ApduProcessor(private val ndefFile: () -> ByteArray?) {
    private var ndefFileSelected = false

    fun process(commandApdu: ByteArray): ByteArray {
        return try {
            handle(commandApdu)
        } catch (_: Exception) {
            reset()
            Apdu.A_ERROR
        }
    }

    fun reset() {
        ndefFileSelected = false
    }

    private fun handle(commandApdu: ByteArray): ByteArray {
        // Shortest useful APDU is CLA INS P1 P2.
        if (commandApdu.size < 4) return Apdu.A_ERROR
        val ins = commandApdu[1].toInt() and 0xFF
        val p1 = commandApdu[2].toInt() and 0xFF
        val p2 = commandApdu[3].toInt() and 0xFF
        return when (ins) {
            Apdu.INS_SELECT -> handleSelect(commandApdu)
            Apdu.INS_READ_BINARY -> handleReadBinary(p1, p2, leOf(commandApdu))
            Apdu.INS_UPDATE_BINARY -> Apdu.A_NOT_SUPPORTED
            else -> Apdu.A_ERROR
        }
    }

    private fun handleSelect(commandApdu: ByteArray): ByteArray {
        val data = selectData(commandApdu)
        return when {
            data.contentEquals(Apdu.AID_NDEF_APPLICATION) -> {
                // A new application select starts a fresh transaction.
                ndefFileSelected = false
                Apdu.A_OKAY
            }
            data.contentEquals(Apdu.CC_FILE_ID) -> Apdu.A_OKAY
            data.contentEquals(Apdu.NDEF_FILE_ID) -> {
                ndefFileSelected = true
                Apdu.A_OKAY
            }
            else -> Apdu.A_ERROR
        }
    }

    /**
     * Data field of a SELECT. Short form carries Lc in byte 4. Readers also
     * emit a single marker byte before Lc (`00 Lc`) and the fully extended
     * form (`00 00 Lc_hi Lc_lo`).
     */
    private fun selectData(commandApdu: ByteArray): ByteArray {
        if (commandApdu.size <= 4) return ByteArray(0)
        val first = commandApdu[4].toInt() and 0xFF
        if (first != 0) return commandApdu.copyOfRange(5, minOf(5 + first, commandApdu.size))
        if (commandApdu.size > 5) {
            val second = commandApdu[5].toInt() and 0xFF
            if (second != 0) return commandApdu.copyOfRange(6, minOf(6 + second, commandApdu.size))
        }
        if (commandApdu.size > 7) {
            val extended = ((commandApdu[6].toInt() and 0xFF) shl 8) or
                (commandApdu[7].toInt() and 0xFF)
            return commandApdu.copyOfRange(8, minOf(8 + extended, commandApdu.size))
        }
        return ByteArray(0)
    }

    /**
     * Le of a READ BINARY. Returns the effective expected byte count, or
     * null when the APDU carries no Le (read to end of file).
     */
    private fun leOf(commandApdu: ByteArray): Int? {
        val raw = when {
            commandApdu.size <= 4 -> return null
            commandApdu.size == 5 -> (commandApdu[4].toInt() and 0xFF)
            commandApdu.size >= 6 ->
                ((commandApdu[4].toInt() and 0xFF) shl 8) or (commandApdu[5].toInt() and 0xFF)
            else -> return null
        }
        // Le = 0 means "as much as you can" per ISO 7816-4.
        return if (raw == 0) Apdu.MAX_CHUNK else raw
    }

    private fun handleReadBinary(p1: Int, p2: Int, le: Int?): ByteArray {
        val offset = (p1 shl 8) or p2
        val requested = le ?: Apdu.MAX_CHUNK
        // Before the NDEF file is selected, an offset-0 read is a capability
        // container read — never NDEF bytes, which would desync the reader.
        if (offset == 0 && !ndefFileSelected && requested > 2) {
            return Apdu.CAPABILITY_CONTAINER_RESPONSE
        }
        // An explicit short Le is the NDEF length query. A missing Le means
        // "read to end of file", so it must not be answered with NLEN.
        if (le != null && le <= 2) return nlenResponse()

        val file = ndefFile() ?: return Apdu.A_ERROR
        if (offset > file.size) return Apdu.A_ERROR
        val end = minOf(offset + minOf(requested, Apdu.MAX_CHUNK), file.size)
        return file.copyOfRange(offset, end) + Apdu.A_OKAY
    }

    private fun nlenResponse(): ByteArray {
        val nlen = ndefFile()?.copyOfRange(0, 2) ?: byteArrayOf(0x00, 0x00)
        return nlen + Apdu.A_OKAY
    }
}
