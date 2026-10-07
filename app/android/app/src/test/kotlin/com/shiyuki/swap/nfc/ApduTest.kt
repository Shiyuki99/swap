package com.shiyuki.swap.nfc

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ApduTest {
    @Test
    fun `select ndef application matches NFC Forum Type 4 AID D2760000850101`() {
        val expected = byteArrayOf(
            0x00, 0xA4.toByte(), 0x04, 0x00, 0x07,
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01, 0x00,
        )
        assertArrayEquals(expected, Apdu.SELECT_NDEF_APPLICATION)
    }

    @Test
    fun `capability container select targets E1 03`() {
        assertArrayEquals(
            byteArrayOf(0x00, 0xA4.toByte(), 0x00, 0x0C.toByte(), 0x02, 0xE1.toByte(), 0x03),
            Apdu.SELECT_CAPABILITY_CONTAINER,
        )
    }

    @Test
    fun `ndef file select targets E1 04`() {
        assertArrayEquals(
            byteArrayOf(0x00, 0xA4.toByte(), 0x00, 0x0C.toByte(), 0x02, 0xE1.toByte(), 0x04),
            Apdu.SELECT_NDEF_FILE,
        )
    }

    @Test
    fun `status words are 9000 OK and 6A82 error`() {
        assertArrayEquals(byteArrayOf(0x90.toByte(), 0x00), Apdu.A_OKAY)
        assertArrayEquals(byteArrayOf(0x6A.toByte(), 0x82.toByte()), Apdu.A_ERROR)
    }

    @Test
    fun `capability container response is 17 bytes with mapping version 2_0`() {
        assertEquals(17, Apdu.CAPABILITY_CONTAINER_RESPONSE.size)
        assertEquals(0x20, Apdu.CAPABILITY_CONTAINER_RESPONSE[2].toInt())
    }
}
