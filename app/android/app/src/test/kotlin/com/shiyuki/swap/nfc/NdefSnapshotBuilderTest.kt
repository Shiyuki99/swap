package com.shiyuki.swap.nfc

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class NdefSnapshotBuilderTest {
    private val url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876"
    private val pkg = "com.shiyuki.swap"

    @Test
    fun `uri payload compresses https prefix to code 0x04`() {
        val payload = NdefSnapshotBuilder.uriPayload(url)
        assertEquals(0x04, payload[0].toInt())
        assertEquals(
            "swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876",
            String(payload.copyOfRange(1, payload.size), Charsets.UTF_8),
        )
    }

    @Test
    fun `uri payload without known prefix uses code 0x00 and full body`() {
        val payload = NdefSnapshotBuilder.uriPayload("example.com/tag")
        assertEquals(0x00, payload[0].toInt())
        assertEquals("example.com/tag", String(payload.copyOfRange(1, payload.size), Charsets.UTF_8))
    }

    @Test
    fun `message is uri record followed by aar record`() {
        val message = NdefSnapshotBuilder.buildMessage(url, pkg)
        // URI record: MB|SR|TNF1 header 0x91, typeLen 1, payloadLen, type 0x55 ('U'), prefix
        assertEquals(0x91, message[0].toInt() and 0xFF)
        assertEquals(1, message[1].toInt())
        val uriPayloadLen = message[2].toInt() and 0xFF
        assertEquals(0x55, message[3].toInt())
        assertEquals(0x04, message[4].toInt())
        // AAR starts after the URI record: 3 header bytes + 1 type byte + payload
        val aarStart = 4 + uriPayloadLen
        assertEquals(0x54, message[aarStart].toInt()) // ME|SR|TNF4
        assertEquals(15, message[aarStart + 1].toInt()) // typeLen of android.com:pkg
        assertEquals(
            "android.com:pkg",
            String(message.copyOfRange(aarStart + 3, aarStart + 3 + 15), Charsets.US_ASCII),
        )
        assertEquals(
            pkg,
            String(message.copyOfRange(aarStart + 3 + 15, message.size), Charsets.US_ASCII),
        )
    }

    @Test
    fun `ndef file prepends big endian NLEN equal to message size`() {
        val message = NdefSnapshotBuilder.buildMessage(url, pkg)
        val file = NdefSnapshotBuilder.buildNdefFile(url, pkg)
        assertEquals(message.size + 2, file.size)
        assertEquals((message.size shr 8) and 0xFF, file[0].toInt() and 0xFF)
        assertEquals(message.size and 0xFF, file[1].toInt() and 0xFF)
        assertArrayEquals(message, file.copyOfRange(2, file.size))
    }

    @Test
    fun `payload larger than 255 bytes is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            NdefSnapshotBuilder.record(0x01, byteArrayOf(0x55), ByteArray(256), mb = true, me = true)
        }
    }
}
