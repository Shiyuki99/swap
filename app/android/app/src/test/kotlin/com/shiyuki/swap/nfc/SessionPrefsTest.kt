package com.shiyuki.swap.nfc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class SessionPrefsTest {
    private class InMemorySessionPrefs : SessionPrefs {
        private var stored: PendingNfcSession? = null
        override fun save(session: PendingNfcSession) {
            stored = session
        }
        override fun load(): PendingNfcSession? = stored
        override fun clear() {
            stored = null
        }
    }

    private val session = PendingNfcSession(
        sessionId = "abcd1234",
        sessionSecret = "wxyz9876",
        url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876",
        createdAtMillis = 1000L,
        expiresAtMillis = 1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS,
    )

    @Test
    fun `save then load returns identical session`() {
        val prefs: SessionPrefs = InMemorySessionPrefs()
        prefs.save(session)
        val loaded = prefs.load()
        assertNotNull(loaded)
        assertEquals(session, loaded)
    }

    @Test
    fun `load returns null when nothing saved`() {
        val prefs: SessionPrefs = InMemorySessionPrefs()
        assertNull(prefs.load())
    }

    @Test
    fun `clear removes saved session`() {
        val prefs: SessionPrefs = InMemorySessionPrefs()
        prefs.save(session)
        prefs.clear()
        assertNull(prefs.load())
    }

    @Test
    fun `save overwrites previous session`() {
        val prefs: SessionPrefs = InMemorySessionPrefs()
        prefs.save(session)
        val other = session.copy(sessionId = "second12")
        prefs.save(other)
        assertEquals(other, prefs.load())
    }
}
