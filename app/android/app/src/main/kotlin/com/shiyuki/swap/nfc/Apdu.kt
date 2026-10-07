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

    /** CC response: mapping v2.0, NDEF file E1 04, read/write without security. */
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
        0xFF.toByte(),
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
}
