package com.shiyuki.swap.nfc

object Apdu {
    /** SELECT NDEF Tag Application (NFC Forum Type 4, section 5.5.2). */
    val SELECT_NDEF_APPLICATION = byteArrayOf(
        0x00, 0xA4.toByte(), 0x04, 0x00, 0x07,
        0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01,
        0x00,
    )

    /** SELECT Capability Container (E1 03). */
    val SELECT_CAPABILITY_CONTAINER = byteArrayOf(
        0x00, 0xA4.toByte(), 0x00, 0x0C.toByte(), 0x02, 0xE1.toByte(), 0x03,
    )

    /** READ BINARY of the CC file (15 bytes). */
    val READ_CAPABILITY_CONTAINER = byteArrayOf(
        0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F,
    )

    /**
     * CC response: mapping v2.0, NDEF file E1 04.
     * Write access is advertised as 0x00 (denied) because this tag is
     * read-only: UPDATE BINARY is answered with 6985. Advertising 0xFF made
     * readers probe writes and then fail.
     */
    val CAPABILITY_CONTAINER_RESPONSE = byteArrayOf(
        0x00, 0x0F,
        0x20,
        0x00, 0x3B.toByte(),
        0x00, 0x34.toByte(),
        0x04,
        0x06,
        0xE1.toByte(), 0x04,
        0x00, 0xFF.toByte(),
        0x00,
        0x00,
        0x90.toByte(), 0x00,
    )

    /** SELECT NDEF file (E1 04). */
    val SELECT_NDEF_FILE = byteArrayOf(
        0x00, 0xA4.toByte(), 0x00, 0x0C.toByte(), 0x02, 0xE1.toByte(), 0x04,
    )

    val READ_BINARY = byteArrayOf(0x00, 0xB0.toByte())

    val READ_BINARY_NLEN = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x02)

    val A_OKAY = byteArrayOf(0x90.toByte(), 0x00)
    val A_ERROR = byteArrayOf(0x6A.toByte(), 0x82.toByte())

    /** 6985: instruction not supported (e.g. UPDATE BINARY on a read-only tag). */
    val A_NOT_SUPPORTED = byteArrayOf(0x69.toByte(), 0x85.toByte())

    /** Instruction bytes the Type 4 processor understands. */
    const val INS_SELECT = 0xA4
    const val INS_READ_BINARY = 0xB0
    const val INS_UPDATE_BINARY = 0xD6

    /** Capability container file id (E1 03) and NDEF file id (E1 04). */
    val CC_FILE_ID = byteArrayOf(0xE1.toByte(), 0x03)
    val NDEF_FILE_ID = byteArrayOf(0xE1.toByte(), 0x04)

    /** NFC Forum Type 4 NDEF application AID. */
    val AID_NDEF_APPLICATION = byteArrayOf(
        0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01,
    )

    /** Max response data we return for a single READ BINARY (transceive-safe). */
    const val MAX_CHUNK = 253
}
