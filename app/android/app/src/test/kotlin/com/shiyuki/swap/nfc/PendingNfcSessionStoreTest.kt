package com.shiyuki.swap.nfc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PendingNfcSessionStoreTest {
    private val url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876"

    private class FakeClock(var now: Long = 1000L) {
        operator fun invoke(): Long = now
    }

    @Test
    fun `set parses session id and secret from swap url`() {
        val clock = FakeClock()
        val store = PendingNfcSessionStore(nowMillis = { clock.now })
        val session = store.set(url)
        assertNotNull(session)
        assertEquals("abcd1234", session!!.sessionId)
        assertEquals("wxyz9876", session.sessionSecret)
        assertEquals(url, session.url)
        assertEquals(1000L, session.createdAtMillis)
        assertEquals(1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS, session.expiresAtMillis)
    }

    @Test
    fun `active returns the session before expiry`() {
        val clock = FakeClock()
        val store = PendingNfcSessionStore(nowMillis = { clock.now })
        store.set(url)
        clock.now = 1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS - 1
        assertNotNull(store.active())
    }

    @Test
    fun `active returns null after ttl expiry`() {
        val clock = FakeClock()
        val store = PendingNfcSessionStore(nowMillis = { clock.now })
        store.set(url)
        clock.now = 1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS
        assertNull(store.active())
    }

    @Test
    fun `set rejects url without secret`() {
        val store = PendingNfcSessionStore(nowMillis = { 1000L })
        assertNull(store.set("https://swapapp-web.onrender.com/view/abcd1234"))
        assertNull(store.active())
    }

    @Test
    fun `set rejects url without view segment`() {
        val store = PendingNfcSessionStore(nowMillis = { 1000L })
        assertNull(store.set("https://swapapp-web.onrender.com/?sig=wxyz9876"))
        assertNull(store.active())
    }

    @Test
    fun `set rejects malformed url`() {
        val store = PendingNfcSessionStore(nowMillis = { 1000L })
        assertNull(store.set("not a url"))
        assertNull(store.active())
    }

    @Test
    fun `clear removes the session`() {
        val store = PendingNfcSessionStore(nowMillis = { 1000L })
        store.set(url)
        store.clear()
        assertNull(store.active())
    }

    @Test
    fun `replacement atomically swaps the session`() {
        val store = PendingNfcSessionStore(nowMillis = { 1000L })
        store.set(url)
        val other = "https://swapapp-web.onrender.com/view/second12?sig=secret34"
        store.set(other)
        assertEquals(other, store.active()!!.url)
    }

    @Test
    fun `parseSwapUrl handles a different host`() {
        val parsed = PendingNfcSessionStore.parseSwapUrl("https://example.com/view/zz99?sig=qq77&foo=bar")
        assertNotNull(parsed)
        assertEquals("zz99", parsed!!.first)
        assertEquals("qq77", parsed.second)
    }

    @Test
    fun `shared instance exists for service and channel`() {
        assertNotNull(PendingNfcSessionStore.shared)
    }

    @Test
    fun `restore keeps original ttl window and stays active`() {
        val clock = FakeClock()
        val store = PendingNfcSessionStore(nowMillis = { clock.now })
        val session = PendingNfcSession(
            sessionId = "abcd1234",
            sessionSecret = "wxyz9876",
            url = url,
            createdAtMillis = 1000L,
            expiresAtMillis = 1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS,
        )
        clock.now = 2000L
        store.restore(session)
        val active = store.active()
        assertNotNull(active)
        assertEquals(1000L + PendingNfcSessionStore.DEFAULT_TTL_MILLIS, active!!.expiresAtMillis)
    }

    @Test
    fun `restored expired session is inactive`() {
        val clock = FakeClock()
        val store = PendingNfcSessionStore(nowMillis = { clock.now })
        store.restore(
            PendingNfcSession(
                sessionId = "abcd1234",
                sessionSecret = "wxyz9876",
                url = url,
                createdAtMillis = 1000L,
                expiresAtMillis = 2000L,
            ),
        )
        clock.now = 2000L
        assertNull(store.active())
    }
}
