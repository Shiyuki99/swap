package com.shiyuki.swap.nfc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NfcSessionGeneratorTest {
    @Test
    fun `tokens are 22 characters of unpadded url-safe base64`() {
        val pair = NfcSessionGenerator.generate()
        assertEquals(22, pair.sessionId.length)
        assertEquals(22, pair.sessionSecret.length)
        val allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        assertTrue(pair.sessionId.all { it in allowed })
        assertTrue(pair.sessionSecret.all { it in allowed })
    }

    @Test
    fun `successive generations differ`() {
        val first = NfcSessionGenerator.generate()
        val second = NfcSessionGenerator.generate()
        assertNotEquals(first.sessionId, second.sessionId)
        assertNotEquals(first.sessionSecret, second.sessionSecret)
    }

    @Test
    fun `id and secret are independent`() {
        val pair = NfcSessionGenerator.generate()
        assertNotEquals(pair.sessionId, pair.sessionSecret)
    }
}
