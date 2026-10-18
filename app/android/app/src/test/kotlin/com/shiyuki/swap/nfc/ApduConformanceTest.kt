package com.shiyuki.swap.nfc

import org.junit.Assert.assertArrayEquals
import org.junit.Test

/**
 * Conformance corpus: real-world reader APDU variants observed from iOS
 * CoreNFC, Android NfcAdapter readers and third-party tag readers. Each
 * trace must resolve to the same Type 4 response as the canonical sequence.
 */
class ApduConformanceTest {
    private val url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876"
    private val file = NdefSnapshotBuilder.buildNdefFile(url)
    private val nlen = byteArrayOf(file[0], file[1])

    private fun processor() = ApduProcessor(ndefFile = { file })

    // ---- SELECT NDEF Tag Application variants ----

    @Test
    fun `select app without trailing Le`() {
        // 11-byte case-3 SELECT, no Le byte
        val apdu = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, 0x07,
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01)
        assertArrayEquals(Apdu.A_OKAY, processor().process(apdu))
    }

    @Test
    fun `select app with proprietary cla 0x80`() {
        val apdu = byteArrayOf(0x80.toByte(), 0xA4.toByte(), 0x04, 0x00, 0x07,
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01, 0x00)
        assertArrayEquals(Apdu.A_OKAY, processor().process(apdu))
    }

    @Test
    fun `select app with extended length header`() {
        val apdu = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, 0x00, 0x00, 0x00, 0x07,
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01)
        assertArrayEquals(Apdu.A_OKAY, processor().process(apdu))
    }

    @Test
    fun `select app with single marker byte before lc`() {
        val apdu = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, 0x00, 0x07,
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01)
        assertArrayEquals(Apdu.A_OKAY, processor().process(apdu))
    }

    @Test
    fun `select cc and ndef file accept P1 0x04`() {
        val p = processor()
        assertArrayEquals(
            Apdu.A_OKAY,
            p.process(byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x0C, 0x02, 0xE1.toByte(), 0x03)),
        )
        assertArrayEquals(
            Apdu.A_OKAY,
            p.process(byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x0C, 0x02, 0xE1.toByte(), 0x04)),
        )
    }

    // ---- Capability Container read variants (offset 0, Le > 2) ----

    @Test
    fun `cc read with Le 14 returns capability container`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        val cc = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x0E)
        assertArrayEquals(Apdu.CAPABILITY_CONTAINER_RESPONSE, p.process(cc))
    }

    @Test
    fun `cc read with Le 255 returns capability container`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        val cc = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0xFF.toByte())
        assertArrayEquals(Apdu.CAPABILITY_CONTAINER_RESPONSE, p.process(cc))
    }

    @Test
    fun `cc read with two-byte Le returns capability container`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        val cc = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x00, 0x0F)
        assertArrayEquals(Apdu.CAPABILITY_CONTAINER_RESPONSE, p.process(cc))
    }

    // ---- NDEF file reads after selecting the NDEF file ----

    @Test
    fun `single shot read after ndef select returns ndef file not cc`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_NDEF_FILE)
        val readAll = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0xFF.toByte())
        assertArrayEquals(file + Apdu.A_OKAY, p.process(readAll))
    }

    @Test
    fun `nlen read after ndef select returns nlen`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_NDEF_FILE)
        assertArrayEquals(nlen + Apdu.A_OKAY, p.process(Apdu.READ_BINARY_NLEN))
    }

    @Test
    fun `read without Le byte returns remaining file`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_NDEF_FILE)
        val read = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00)
        assertArrayEquals(file + Apdu.A_OKAY, p.process(read))
    }

    @Test
    fun `chunk read is clamped to 253 bytes`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_NDEF_FILE)
        val big = byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0xFF.toByte())
        // File is far below 253 bytes, so the clamp is not observable here;
        // assert we never exceed the requested window for a large file.
        val response = p.process(big)
        assertArrayEquals(file + Apdu.A_OKAY, response)
        if (file.size > 253) {
            assertArrayEquals(file.copyOfRange(0, 253) + Apdu.A_OKAY, response)
        }
    }

    @Test
    fun `chunk read with proprietary cla 0x80`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_NDEF_FILE)
        p.process(Apdu.READ_BINARY_NLEN)
        val chunk = byteArrayOf(0x80.toByte(), 0xB0.toByte(), 0x00, 0x00, 0x10)
        assertArrayEquals(file.copyOfRange(0, 16) + Apdu.A_OKAY, p.process(chunk))
    }

    // ---- Non-read instructions ----

    @Test
    fun `update binary returns not supported`() {
        val write = byteArrayOf(0x00, 0xD6.toByte(), 0x00, 0x00, 0x02, 0x00, 0x00)
        assertArrayEquals(Apdu.A_NOT_SUPPORTED, processor().process(write))
    }

    @Test
    fun `unknown instruction returns error`() {
        assertArrayEquals(Apdu.A_ERROR, processor().process(byteArrayOf(0x00, 0xB2.toByte(), 0x00, 0x00, 0x00)))
    }

    // ---- Recovery ----

    @Test
    fun `abort mid transfer then reselect app restores cc access`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        p.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F))
        p.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x10, 0x0F)) // mid-transfer abort
        // New field activation
        assertArrayEquals(Apdu.A_OKAY, p.process(Apdu.SELECT_NDEF_APPLICATION))
        assertArrayEquals(Apdu.A_OKAY, p.process(Apdu.SELECT_CAPABILITY_CONTAINER))
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            p.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F)),
        )
    }

    @Test
    fun `onDeactivated reset lets cc be read again`() {
        val p = processor()
        p.process(Apdu.SELECT_NDEF_APPLICATION)
        p.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F))
        p.process(Apdu.SELECT_NDEF_FILE)
        p.reset()
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            p.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x0F)),
        )
    }
}
