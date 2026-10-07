package com.shiyuki.swap.nfc

/**
 * Pure-Kotlin NFC Forum Type 4 command processor. Serves the NDEF file
 * produced by [ndefFile]; when it returns null the service answers with a
 * valid capability container and an empty NDEF file (NLEN = 0) so readers
 * see a clean empty tag instead of a protocol error.
 */
class ApduProcessor(private val ndefFile: () -> ByteArray?) {
    private var capabilityContainerRead = false

    fun process(commandApdu: ByteArray): ByteArray {
        return try {
            handle(commandApdu)
        } catch (_: Exception) {
            reset()
            Apdu.A_ERROR
        }
    }

    fun reset() {
        capabilityContainerRead = false
    }

    private fun handle(commandApdu: ByteArray): ByteArray {
        if (commandApdu.size < 2) return Apdu.A_ERROR

        if (commandApdu.contentEquals(Apdu.SELECT_NDEF_APPLICATION)) {
            capabilityContainerRead = false
            return Apdu.A_OKAY
        }
        if (commandApdu.contentEquals(Apdu.SELECT_CAPABILITY_CONTAINER)) return Apdu.A_OKAY
        if (commandApdu.contentEquals(Apdu.READ_CAPABILITY_CONTAINER) && !capabilityContainerRead) {
            capabilityContainerRead = true
            return Apdu.CAPABILITY_CONTAINER_RESPONSE
        }
        if (commandApdu.contentEquals(Apdu.SELECT_NDEF_FILE)) return Apdu.A_OKAY
        if (commandApdu.contentEquals(Apdu.READ_BINARY_NLEN)) {
            capabilityContainerRead = false
            return nlenResponse()
        }
        if (isReadBinary(commandApdu)) {
            capabilityContainerRead = false
            return readBinaryResponse(commandApdu)
        }
        return Apdu.A_ERROR
    }

    private fun isReadBinary(commandApdu: ByteArray): Boolean =
        commandApdu.size >= 5 &&
            commandApdu[0] == Apdu.READ_BINARY[0] &&
            commandApdu[1] == Apdu.READ_BINARY[1]

    private fun nlenResponse(): ByteArray {
        val nlen = ndefFile()?.copyOfRange(0, 2) ?: byteArrayOf(0x00, 0x00)
        return nlen + Apdu.A_OKAY
    }

    private fun readBinaryResponse(commandApdu: ByteArray): ByteArray {
        val file = ndefFile() ?: return Apdu.A_ERROR
        val offset = ((commandApdu[2].toInt() and 0xFF) shl 8) or (commandApdu[3].toInt() and 0xFF)
        val length = commandApdu[4].toInt() and 0xFF
        if (offset > file.size) return Apdu.A_ERROR
        val end = minOf(offset + length, file.size)
        return file.copyOfRange(offset, end) + Apdu.A_OKAY
    }
}
