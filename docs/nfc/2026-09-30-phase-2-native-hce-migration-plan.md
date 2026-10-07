# Phase 2: Native HCE Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `flutter_nfc_hce: ^0.1.8` dependency with an app-owned Kotlin HCE implementation that serves an immutable NDEF URI + AAR snapshot from a TTL-bound in-memory pending session, while preserving the existing generic Type 4 NDEF APDU sequence.

**Architecture:** Two layers. (1) Pure-Kotlin core with no Android framework dependency — `Apdu` constants, `NfcSessionGenerator`, `PendingNfcSessionStore`, `NdefSnapshotBuilder`, `ApduProcessor` — all covered by JUnit tests run via `./gradlew :app:testDebugUnitTest`. (2) Android glue — `SwapHostApduService` (wires store + processor, resets state on field deactivation, `BuildConfig.DEBUG`-gated redacted logs that never print the secret), `NfcMethodChannel` on channel `swap/nfc`, registration in `MainActivity.configureFlutterEngine`. Dart `NFCService` keeps its public API (`writeUUID`, `stopSession`, `isHceActive`, `isNFCAvailable`, `isNFCEnabled`) but talks to the channel, so `SwapSessionManager`, `share_screen.dart`, and `join_screen.dart` change not at all.

**Tech Stack:** Kotlin (JVM 17), Android `HostApduService`, JUnit 4, Dart MethodChannel, `flutter_test` with mock method handlers.

---

## Decisions (locked)

1. The HCE service is manifest-static: "starting HCE" means populating the process-wide store. No `startService` call (vendor approach dropped).
2. Store is **memory-only** — it survives app-closed-after-prior-launch while the process is alive; force-stopped / never-launched stays officially unsupported (audit).
3. Expired/absent session → valid capability container + `NLEN = 0` (clean empty tag), not `A_ERROR`.
4. AAR (`android.com:pkg`) rides in the NDEF message for reader-phone app opening; it cannot influence AID selection (audit line 60).
5. `NfcSessionGenerator` is built and tested now but stays unused until the Phase 4 native-first sender entry point (audit lists it in the Phase 2 boundary).
6. `flutter_nfc_kit` + `ndef` are unused (zero imports under `app/lib`) and are removed together with `flutter_nfc_hce`.
7. The shared native TTL is `PendingNfcSessionStore.DEFAULT_TTL_MILLIS` = 5 minutes, matching the existing server TTL (audit line 17).

## File Structure

Create (Kotlin main, package `com.shiyuki.swap.nfc`):

- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/Apdu.kt` — Type 4 APDU vectors + status words.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcSessionGenerator.kt` — SecureRandom 128-bit URL-safe pair.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSession.kt` — data class.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStore.kt` — atomic store, TTL, `/view/:id?sig=:secret` parser, `shared` instance.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilder.kt` — NDEF URI + AAR bytes, no framework use.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/ApduProcessor.kt` — Type 4 state machine.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/SwapHostApduService.kt` — Android glue.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcMethodChannel.kt` — `swap/nfc` channel.

Create (JUnit):

- `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduTest.kt`
- `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NfcSessionGeneratorTest.kt`
- `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStoreTest.kt`
- `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilderTest.kt`
- `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduProcessorTest.kt`

Create (Dart):

- `app/test/nfc_service_test.dart` — mocked channel tests for `NFCService`.

Modify:

- `app/android/app/build.gradle.kts` — add `testImplementation("junit:junit:4.13.2")`.
- `app/android/app/src/main/AndroidManifest.xml:76-89` — service name becomes `com.shiyuki.swap.nfc.SwapHostApduService`.
- `app/android/app/src/main/kotlin/com/shiyuki/swap/MainActivity.kt` — register the channel.
- `app/lib/services/nfc_service.dart` — MethodChannel rewrite, same public API.
- `app/pubspec.yaml:66-69` — remove `flutter_nfc_hce`, `flutter_nfc_kit`, `ndef`.

Delete:

- `app/.agent/workflows/patch-nfc-uri.md` — obsolete once URI records ship in owned Kotlin.

### Task 1: JUnit harness + Apdu constants

**Files:**
- Modify: `app/android/app/build.gradle.kts` (append dependencies block)
- Create: `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduTest.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/Apdu.kt`

- [ ] **Step 1: Add the JUnit dependency**

```kotlin
// Append at end of app/android/app/build.gradle.kts:
dependencies {
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2: Write the failing test**

```kotlin
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.ApduTest"` (workdir `app/android`)
Expected: FAIL — compilation error, unresolved reference `Apdu`

- [ ] **Step 4: Write the minimal implementation**

```kotlin
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.ApduTest"` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, 5 tests passed

- [ ] **Step 6: Commit**

```bash
git add app/android/app/build.gradle.kts app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/Apdu.kt app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduTest.kt
git commit -m "feat(nfc): add Type 4 APDU vectors with JUnit harness"
```

### Task 2: NfcSessionGenerator (secure 128-bit URL-safe pair)

**Files:**
- Create: `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NfcSessionGeneratorTest.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcSessionGenerator.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
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
        assertNotEquals(first.sessionSecret, second.secret)
    }

    @Test
    fun `id and secret are independent`() {
        val pair = NfcSessionGenerator.generate()
        assertNotEquals(pair.sessionId, pair.sessionSecret)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.NfcSessionGeneratorTest"` (workdir `app/android`)
Expected: FAIL — unresolved reference `NfcSessionGenerator`

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.shiyuki.swap.nfc

import java.security.SecureRandom
import java.util.Base64

/** Generates URL-safe 128-bit tokens for the native pending session pair. */
object NfcSessionGenerator {
    private const val TOKEN_BYTES = 16 // 128 bits

    data class SessionPair(val sessionId: String, val sessionSecret: String)

    fun generate(): SessionPair {
        val random = SecureRandom()
        val id = ByteArray(TOKEN_BYTES)
        random.nextBytes(id)
        val secret = ByteArray(TOKEN_BYTES)
        random.nextBytes(secret)
        return SessionPair(encode(id), encode(secret))
    }

    fun encode(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}
```

Note: `java.util.Base64` needs API 26+; minSdk is 26 (`app/android/app/build.gradle.kts:35`), so this is safe.

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.NfcSessionGeneratorTest"` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcSessionGenerator.kt app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NfcSessionGeneratorTest.kt
git commit -m "feat(nfc): add secure 128-bit session pair generator"
```

### Task 3: PendingNfcSession + PendingNfcSessionStore (atomic, TTL)

**Files:**
- Create: `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStoreTest.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSession.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStore.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package com.shiyuki.swap.nfc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PendingNfcSessionStoreTest {
    private val url = "https://swapapp-web.onrender.com/view/abcd1234?sig=wxyz9876"

    private class FakeClock(var now: Long = 1000L)

    // NOTE: FakeClock cannot be passed directly (Kotlin does not coerce to
    // function types), so each construction uses a lambda: `nowMillis = { clock.now }`
    // for mutable clocks and `nowMillis = { 1000L }` for fixed clocks.

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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.PendingNfcSessionStoreTest"` (workdir `app/android`)
Expected: FAIL — unresolved reference `PendingNfcSessionStore`

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.shiyuki.swap.nfc

data class PendingNfcSession(
    val sessionId: String,
    val sessionSecret: String,
    val url: String,
    val createdAtMillis: Long,
    val expiresAtMillis: Long,
)
```

```kotlin
package com.shiyuki.swap.nfc

import java.net.URI
import java.net.URISyntaxException
import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide store for the pending native NFC session. AtomicReference
 * swaps make set/clear/active race-safe between the HCE service thread and
 * the Dart method channel thread calling into the main thread.
 */
class PendingNfcSessionStore(
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val current = AtomicReference<PendingNfcSession?>()

    /** Stores the session pair parsed from [url]; null when the URL is not a swap URL. */
    fun set(url: String): PendingNfcSession? {
        val parsed = parseSwapUrl(url) ?: return null
        val now = nowMillis()
        val session = PendingNfcSession(
            sessionId = parsed.first,
            sessionSecret = parsed.second,
            url = url,
            createdAtMillis = now,
            expiresAtMillis = now + ttlMillis,
        )
        current.set(session)
        return session
    }

    /** Returns the session only while it is inside its TTL window. */
    fun active(): PendingNfcSession? {
        val session = current.get() ?: return null
        if (nowMillis() >= session.expiresAtMillis) return null
        return session
    }

    fun clear() {
        current.set(null)
    }

    companion object {
        /** Matches the existing five-minute server session TTL (audit baseline). */
        const val DEFAULT_TTL_MILLIS: Long = 5L * 60L * 1000L

        /** Shared instance used by the HCE service and the method channel. */
        val shared = PendingNfcSessionStore()

        /** Parses https://host/view/:id?sig=:secret into (id, secret); null otherwise. */
        fun parseSwapUrl(url: String): Pair<String, String>? {
            val uri = try {
                URI(url)
            } catch (_: URISyntaxException) {
                return null
            }
            val segments = uri.path?.split('/')?.filter { it.isNotBlank() } ?: return null
            val viewIndex = segments.indexOf("view")
            if (viewIndex == -1 || viewIndex + 1 >= segments.size) return null
            val id = segments[viewIndex + 1]
            val secret = uri.rawQuery
                ?.split('&')
                ?.firstOrNull { it.startsWith("sig=") }
                ?.removePrefix("sig=")
            if (id.isBlank() || secret.isNullOrBlank()) return null
            return id to secret
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.PendingNfcSessionStoreTest"` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, 10 tests passed

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSession.kt app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStore.kt app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/PendingNfcSessionStoreTest.kt
git commit -m "feat(nfc): add TTL-bound atomic pending session store"
```

### Task 4: NdefSnapshotBuilder (URI + AAR bytes, no framework)

**Files:**
- Create: `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilderTest.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilder.kt`

This replaces the non-reproducible `patch-nfc-uri.md` sed patch: URI records are built natively here instead of inside `~/.pub-cache`.

- [ ] **Step 1: Write the failing test**

```kotlin
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
        // URI record: MB|SR|TNF1 header 0x91, typeLen 1, type 0x55 ('U'), payloadLen
        assertEquals(0x91, message[0].toInt())
        assertEquals(1, message[1].toInt())
        assertEquals(0x55, message[2].toInt())
        val uriPayloadLen = message[3].toInt() and 0xFF
        assertEquals(0x04, message[4].toInt())
        // AAR starts after the URI record: 2 header bytes + 1 type byte + payload
        val aarStart = 4 + uriPayloadLen
        assertEquals(0x54, message[aarStart].toInt()) // ME|SR|TNF4
        assertEquals(15, message[aarStart + 1].toInt()) // typeLen of android.com:pkg
        assertEquals(
            "android.com:pkg",
            String(message.copyOfRange(aarStart + 2, aarStart + 2 + 15), Charsets.US_ASCII),
        )
        assertEquals(
            pkg,
            String(message.copyOfRange(aarStart + 2 + 15, message.size), Charsets.US_ASCII),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.NdefSnapshotBuilderTest"` (workdir `app/android`)
Expected: FAIL — unresolved reference `NdefSnapshotBuilder`

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.shiyuki.swap.nfc

/**
 * Builds NDEF message bytes (URI + AAR) in pure Kotlin so the exact bytes
 * stay unit-testable without Robolectric. This replaces the old pub-cache
 * sed patch that created URI records inside the flutter_nfc_hce plugin.
 */
object NdefSnapshotBuilder {
    private const val TNF_WELL_KNOWN: Int = 0x01
    private const val TNF_EXTERNAL_TYPE: Int = 0x04
    private const val FLAG_MB: Int = 0x80
    private const val FLAG_ME: Int = 0x40
    private const val FLAG_SR: Int = 0x10
    private val RTD_URI = byteArrayOf(0x55) // 'U'
    private val RTD_ANDROID_PKG = "android.com:pkg".toByteArray(Charsets.US_ASCII)

    // NFC Forum URI prefix codes, most specific first.
    private val URI_PREFIXES = listOf(
        "https://www." to 0x02,
        "http://www." to 0x01,
        "https://" to 0x04,
        "http://" to 0x03,
    )

    /** Full NDEF file: 2-byte big-endian NLEN followed by the NDEF message. */
    fun buildNdefFile(url: String, packageName: String): ByteArray {
        val message = buildMessage(url, packageName)
        val nlen = byteArrayOf(
            ((message.size shr 8) and 0xFF).toByte(),
            (message.size and 0xFF).toByte(),
        )
        return nlen + message
    }

    /** URI record first (MB set) + AAR record last (ME set). */
    fun buildMessage(url: String, packageName: String): ByteArray {
        val uriRecord = record(TNF_WELL_KNOWN, RTD_URI, uriPayload(url), mb = true, me = false)
        val aarRecord = record(
            TNF_EXTERNAL_TYPE,
            RTD_ANDROID_PKG,
            packageName.toByteArray(Charsets.US_ASCII),
            mb = false,
            me = true,
        )
        return uriRecord + aarRecord
    }

    /** URI payload: 1-byte NFC Forum prefix code + UTF-8 remainder. */
    fun uriPayload(url: String): ByteArray {
        val match = URI_PREFIXES.firstOrNull { url.startsWith(it.first) }
        val prefixCode = match?.second ?: 0x00
        val body = if (match != null) url.removePrefix(match.first) else url
        return byteArrayOf(prefixCode.toByte()) + body.toByteArray(Charsets.UTF_8)
    }

    /**
     * NDEF short record: [MB|ME|SR|TNF, TYPE_LEN, TYPE..., PAYLOAD...] with
     * IL=0 and no ID field. Rejects payloads over 255 bytes (SR limit).
     */
    fun record(tnf: Int, type: ByteArray, payload: ByteArray, mb: Boolean, me: Boolean): ByteArray {
        require(payload.size < 256) { "SR record payload must be < 256 bytes, was ${payload.size}" }
        var header = tnf and 0x07
        if (mb) header = header or FLAG_MB
        if (me) header = header or FLAG_ME
        header = header or FLAG_SR
        return byteArrayOf(header.toByte(), type.size.toByte()) + type + payload
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.NdefSnapshotBuilderTest"` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, 5 tests passed

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilder.kt app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/NdefSnapshotBuilderTest.kt
git commit -m "feat(nfc): add pure-Kotlin NDEF URI plus AAR builder"
```

### Task 5: ApduProcessor (Type 4 state machine)

**Files:**
- Create: `app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduProcessorTest.kt`
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/ApduProcessor.kt`

Fixes the vendor flaws: no field-initializer file reads, no `!!`, no unbounded slicing (offset beyond the file returns `A_ERROR`, over-long reads clamp), no payload logging (logging lives in the service under a debug gate).

- [ ] **Step 1: Write the failing test**

```kotlin
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
            processor.process(byteArrayOf(0x00, 0xB0.toByte(), 0x00, 0x00, 0x02)),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.ApduProcessorTest"` (workdir `app/android`)
Expected: FAIL — unresolved reference `ApduProcessor`

- [ ] **Step 3: Write minimal implementation**

```kotlin
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew :app:testDebugUnitTest --tests "com.shiyuki.swap.nfc.ApduProcessorTest"` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, 8 tests passed

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/ApduProcessor.kt app/android/app/src/test/kotlin/com/shiyuki/swap/nfc/ApduProcessorTest.kt
git commit -m "feat(nfc): add defensive Type 4 APDU state machine"
```

### Task 6: SwapHostApduService + manifest swap

**Files:**
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/SwapHostApduService.kt`
- Modify: `app/android/app/src/main/AndroidManifest.xml:76-89`

No unit test for a `HostApduService` subclass (framework-bound); verification is a full debug build, which compiles the service against the real Android APIs.

- [ ] **Step 1: Create the service**

```kotlin
package com.shiyuki.swap.nfc

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log
import com.shiyuki.swap.BuildConfig

/**
 * App-owned HCE service emulating an NFC Forum Type 4 NDEF tag.
 *
 * Serves a frozen NDEF URI + AAR snapshot from [PendingNfcSessionStore.shared]
 * for the current pending session. Works without Flutter attached. Never
 * performs network, Nearby, or permission work here — processCommandApdu
 * runs on the main thread and must not block.
 */
class SwapHostApduService : HostApduService() {

    private val processor = ApduProcessor(ndefFile = { activeNdefFile() })

    private fun activeNdefFile(): ByteArray? {
        val session = PendingNfcSessionStore.shared.active() ?: return null
        return NdefSnapshotBuilder.buildNdefFile(session.url, packageName)
    }

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "APDU ${commandApdu.size}B ${commandApdu.toHex()}")
        }
        return processor.process(commandApdu)
    }

    override fun onDeactivated(reason: Int) {
        if (BuildConfig.DEBUG) Log.d(TAG, "Deactivated, reason=$reason")
        processor.reset()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02X".format(it) }

    companion object {
        private const val TAG = "SwapNfc"
    }
}
```

Logs stay debug-gated and redacted: APDU bytes never contain the secret (the NDEF file bytes are only built inside `activeNdefFile`, never logged).

- [ ] **Step 2: Point the manifest at the owned service**

```xml
<!-- HCE Service for NFC NDEF Tag Emulation (app-owned, replaces flutter_nfc_hce) -->
<service
    android:name="com.shiyuki.swap.nfc.SwapHostApduService"
    android:exported="true"
    android:enabled="true"
    android:permission="android.permission.BIND_NFC_SERVICE">
    <intent-filter>
        <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
        <category android:name="android.intent.category.DEFAULT" />
    </intent-filter>
    <meta-data
        android:name="android.nfc.cardemulation.host_apdu_service"
        android:resource="@xml/apduservice" />
</service>
```

`apduservice.xml` stays untouched: same generic Type 4 AID `D2760000850101`, same screen-on/unlock flags (audit line 58).

- [ ] **Step 3: Build to verify compile**

Run: `./gradlew :app:assembleDebug` (workdir `app/android`)
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/SwapHostApduService.kt app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(nfc): add owned HCE service and register in manifest"
```

### Task 7: NfcMethodChannel + MainActivity registration

**Files:**
- Create: `app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcMethodChannel.kt`
- Modify: `app/android/app/src/main/kotlin/com/shiyuki/swap/MainActivity.kt`

- [ ] **Step 1: Create the channel handler**

```kotlin
package com.shiyuki.swap.nfc

import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Method channel (swap/nfc) exposing the native HCE implementation to Dart.
 * startSession stores the parsed session pair; the HCE service is statically
 * registered in the manifest so no explicit service start is required.
 */
object NfcMethodChannel {
    private const val CHANNEL = "swap/nfc"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(hasNfcHce(context))
                "isEnabled" -> result.success(isNfcEnabled(context))
                "startSession" -> {
                    val url = call.argument<String>("url")
                    val session = url?.let { PendingNfcSessionStore.shared.set(it) }
                    result.success(session != null)
                }
                "stopSession" -> {
                    PendingNfcSessionStore.shared.clear()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasNfcHce(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HCE)

    private fun isNfcEnabled(context: Context): Boolean =
        NfcAdapter.getDefaultAdapter(context)?.isEnabled == true
}
```

- [ ] **Step 2: Register from MainActivity**

```kotlin
package com.shiyuki.swap

import com.shiyuki.swap.nfc.NfcMethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NfcMethodChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }
}
```

- [ ] **Step 3: Build to verify compile**

Run: `./gradlew :app:assembleDebug` (workdir `app/android`)
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add app/android/app/src/main/kotlin/com/shiyuki/swap/nfc/NfcMethodChannel.kt app/android/app/src/main/kotlin/com/shiyuki/swap/MainActivity.kt
git commit -m "feat(nfc): wire swap/nfc method channel into MainActivity"
```

### Task 8: Dart NFCService rewrite + dependency removal

**Files:**
- Create: `app/test/nfc_service_test.dart`
- Modify: `app/lib/services/nfc_service.dart`
- Modify: `app/pubspec.yaml:66-69`

Public API stays identical so `SwapSessionManager`, `share_screen.dart:49`, and `join_screen.dart:45` need no changes.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swap/services/nfc_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('swap/nfc');
  late NFCService service;
  Object? Function(MethodCall)? handler;

  setUp(() {
    service = NFCService();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler?.call(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writeUUID activates HCE when native accepts the session', () async {
    handler = (call) async {
      expect(call.method, 'startSession');
      expect(call.arguments['url'], 'https://example.com/view/abc?sig=xyz');
      return true;
    };
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    expect(service.isHceActive, isTrue);
  });

  test('writeUUID stays inactive when native rejects the session', () async {
    handler = (call) async => false;
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    expect(service.isHceActive, isFalse);
  });

  test('stopSession deactivates HCE', () async {
    handler = (call) async => true;
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    await service.stopSession();
    expect(service.isHceActive, isFalse);
  });

  test('isNFCAvailable reflects the native support check', () async {
    handler = (call) async => call.method == 'isSupported';
    expect(await service.isNFCAvailable(), isTrue);
  });

  test('platform errors are swallowed and report unavailable', () async {
    handler = (call) async => throw PlatformException(code: 'error');
    expect(await service.isNFCAvailable(), isFalse);
    expect(await service.isNFCEnabled(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/nfc_service_test.dart` (workdir `app`)
Expected: FAIL — `package:flutter_nfc_hce` import missing after dep removal, or channel mismatch. (Order: remove deps first, then the rewritten wrapper fails to compile against the stale import.)

- [ ] **Step 3: Remove the dead dependencies and rewrite the wrapper**

In `app/pubspec.yaml`, delete:

```yaml
  # NFC 
  flutter_nfc_kit: ^3.6.1
  flutter_nfc_hce: ^0.1.8
  ndef: ^0.4.0
```

Replace `app/lib/services/nfc_service.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// NFC Service for URL sharing via HCE (Host Card Emulation).
/// Talks to the app-owned Kotlin HCE implementation over the `swap/nfc`
/// method channel. HCE is only available on Android; iOS does not support
/// third-party HCE.
class NFCService {
  static const MethodChannel _channel = MethodChannel('swap/nfc');
  bool _isHceActive = false;

  /// Check if NFC HCE is supported on this device.
  Future<bool> isNFCAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') == true;
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error checking NFC support: ${e.message}');
      return false;
    }
  }

  /// Check if NFC is enabled on the device.
  Future<bool> isNFCEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') == true;
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error checking NFC enabled: ${e.message}');
      return false;
    }
  }

  /// Start broadcasting the URL via NFC HCE.
  /// The native side parses the session pair from the URL and stores an
  /// immutable NDEF snapshot served by SwapHostApduService.
  Future<void> writeUUID(String urlToSend) async {
    debugPrint('[NFC] Starting HCE session');
    try {
      final started =
          await _channel.invokeMethod<bool>('startSession', {'url': urlToSend});
      _isHceActive = started == true;
      if (!_isHceActive) {
        debugPrint('[NFC] Native side rejected the session URL');
      }
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error starting HCE: ${e.message}');
    }
  }

  /// Stop NFC HCE broadcasting.
  Future<void> stopSession() async {
    debugPrint('[NFC] Stopping HCE session');
    try {
      await _channel.invokeMethod<bool>('stopSession');
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error stopping HCE: ${e.message}');
    } finally {
      _isHceActive = false;
    }
  }

  bool get isHceActive => _isHceActive;
}
```

Then run `flutter pub get` (workdir `app`).

- [ ] **Step 4: Run tests and analyzer to verify**

Run: `flutter test test/nfc_service_test.dart` (workdir `app`)
Expected: All tests passed

Run: `flutter analyze` (workdir `app`)
Expected: No issues found (baseline was clean per audit line 7)

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/nfc_service.dart app/pubspec.yaml app/pubspec.lock app/test/nfc_service_test.dart
git commit -m "feat(nfc): route NFCService through owned Kotlin HCE channel"
```

### Task 9: Remove patch workflow + full verification

**Files:**
- Delete: `app/.agent/workflows/patch-nfc-uri.md`
- No code changes otherwise.

- [ ] **Step 1: Delete the obsolete workflow**

```bash
git rm app/.agent/workflows/patch-nfc-uri.md
```

- [ ] **Step 2: Run the full verification suite**

Run: `./gradlew :app:testDebugUnitTest` (workdir `app/android`)
Expected: BUILD SUCCESSFUL, all `com.shiyuki.swap.nfc.*` tests pass (28 total)

Run: `flutter analyze` (workdir `app`)
Expected: No issues found

Run: `flutter test` (workdir `app`)
Expected: All tests passed

Run: `flutter build apk --debug` (workdir `app`)
Expected: Built `build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore(nfc): drop pub-cache URI patch workflow after native HCE migration"
```

### Task 10: Device checks before declaring support complete (manual)

No NFC hardware transaction is available in this environment. Before release, test a real reader against each row; force-stopped and never-launched app cases stay documented as unsupported, never promised:

- [ ] Sender foreground: tap receiver, profile URL opens.
- [ ] Sender app closed after prior swap start (process alive): tap still serves the snapshot.
- [ ] Interrupted read (pull away mid-transaction), then immediate re-tap: second read completes.
- [ ] Repeated taps within the TTL: same URL served (snapshot is immutable).
- [ ] Tap after TTL expiry: reader sees an empty tag (NLEN=0), no URL.
- [ ] Another app with a generic-NDEF HCE service installed: duplicate-AID selection prompt appears; SWAP is selectable.
- [ ] Nearby permissions denied: HCE still serves the URL; Wi-Fi Direct fails independently as before.
- [ ] Android 16: HTTPS scan arrives as `ACTION_VIEW` (not `ACTION_NDEF_DISCOVERED`).
- [ ] Android 17: explicit open-link notification interaction opens the URL.

## Self-review

1. **Spec coverage.** Audit Phase 2 boundary (lines 72-79): secure native session-pair generator → Task 2; atomic `PendingNfcSessionStore` with existing TTL → Task 3; immutable NDEF URI + AAR snapshot for one activation → Task 4 (memory-only, TTL-bound, cleared on stop — one activation lifetime); defensive APDU/state handling with debug-only redacted logs → Tasks 5-6. Works without Flutter, no Nearby/server work → Tasks 6-7 add no such calls. Flutter handoff (forced pair into `startSwap`), App Links, waiting-receiver behavior, AID diagnostics are explicitly deferred. All device checks → Task 10.
2. **Placeholder scan.** No TBD/TODO/later placeholders: every code step shows complete code; the one deliberate deferral is the named Phase 4 entry point, which is out of scope by audit boundary.
3. **Type consistency.** `PendingNfcSession(url, sessionId, sessionSecret, ...)` fields line up with `NdefSnapshotBuilder.buildNdefFile(session.url, packageName)` usage in Task 6; channel contract (`isSupported`/`isEnabled`/`startSession(url)`/`stopSession`) matches the Dart wrapper in Task 8; test doubles (`FakeClock` `() -> Long`) match the store's `nowMillis` signature; `Apdu` object names match `ApduProcessor` references in Task 5.
