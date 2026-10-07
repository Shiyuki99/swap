package com.shiyuki.swap.nfc

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class ApduProcessorTest {
    private val url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876"
    private val ndefFile = NdefSnapshotBuilder.buildNdefFile(url, "com.shiyuki.swap")

    private fun processorWith(file: ByteArray?) = ApduProcessor(ndefFile = { file })

    @Test
    fun `full Type 4 sequence returns ndef file with NLEN`() {
        val processor = processorWith(ndefFile)
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_NDEF_APPLICATION))
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_CAPABILITY_CONTAINER))
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            processor.process(Apdu.READ_CAPABILITY_CONTAINER),
        )
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_NDEF_FILE))
        assertArrayEquals(
            byteArrayOf(ndefFile[0], ndefFile[1], Apdu.A_OKAY[0], Apdu.A_OKAY[1]),
            processor.process(Apdu.READ_BINARY_NLEN),
        )
    }

    @Test
    fun `read binary chunks honor offset and length`() {
        val processor = processorWith(ndefFile)
        processor.process(Apdu.SELECT_NDEF_APPLICATION)
        processor.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        processor.process(Apdu.READ_CAPABILITY_CONTAINER)
        processor.process(Apdu.SELECT_NDEF_FILE)
        processor.process(Apdu.READ_BINARY_NLEN)

        val first = processor.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x50))
        assertArrayEquals(ndefFile.copyOfRange(0, 80) + Apdu.A_OKAY, first)

        val rest = processor.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x50, 0x50))
        assertArrayEquals(ndefFile.copyOfRange(80, ndefFile.size) + Apdu.A_OKAY, rest)
    }

    @Test
    fun `no active session serves empty ndef file and refuses binary reads`() {
        val processor = processorWith(null)
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_NDEF_APPLICATION))
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_CAPABILITY_CONTAINER))
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            processor.process(Apdu.READ_CAPABILITY_CONTAINER),
        )
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_NDEF_FILE))
        assertArrayEquals(
            byteArrayOf(0x00, 0x00, Apdu.A_OKAY[0], Apdu.A_OKAY[1]),
            processor.process(Apdu.READ_BINARY_NLEN),
        )
        assertArrayEquals(
            Apdu.A_ERROR,
            processor.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x02, 0x0F)),
        )
    }

    @Test
    fun `unknown apdu returns error status`() {
        val processor = processorWith(ndefFile)
        assertArrayEquals(Apdu.A_ERROR, processor.process(byteArrayOf(0x01, 0x02, 0x03)))
    }

    @Test
    fun `short apdu returns error status`() {
        val processor = processorWith(ndefFile)
        assertArrayEquals(Apdu.A_ERROR, processor.process(byteArrayOf(0x00)))
    }

    @Test
    fun `read binary with offset beyond file returns error`() {
        val processor = processorWith(ndefFile)
        processor.process(Apdu.SELECT_NDEF_APPLICATION)
        processor.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        processor.process(Apdu.SELECT_NDEF_FILE)
        assertArrayEquals(
            Apdu.A_ERROR,
            processor.process(byteArrayOf(0x00, 0xB0.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0x0F)),
        )
    }

    @Test
    fun `reselect application after partial transaction serves capability container again`() {
        val processor = processorWith(ndefFile)
        processor.process(Apdu.SELECT_NDEF_APPLICATION)
        processor.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        processor.process(Apdu.READ_CAPABILITY_CONTAINER)
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_NDEF_APPLICATION))
        assertArrayEquals(Apdu.A_OKAY, processor.process(Apdu.SELECT_CAPABILITY_CONTAINER))
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            processor.process(Apdu.READ_CAPABILITY_CONTAINER),
        )
    }

    @Test
    fun `reset allows capability container read again`() {
        val processor = processorWith(ndefFile)
        processor.process(Apdu.SELECT_NDEF_APPLICATION)
        processor.process(Apdu.READ_CAPABILITY_CONTAINER)
        processor.reset()
        processor.process(Apdu.SELECT_CAPABILITY_CONTAINER)
        assertArrayEquals(
            Apdu.CAPABILITY_CONTAINER_RESPONSE,
            processor.process(Apdu.READ_CAPABILITY_CONTAINER),
        )
    }
}
