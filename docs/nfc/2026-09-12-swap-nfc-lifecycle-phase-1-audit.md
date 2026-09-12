# SWAP NFC lifecycle — Phase 1 audit

Date: 2026-09-12

## Baseline

`flutter analyze` passes with no findings before NFC changes. This audit makes no production-code changes.

SWAP's exchange transport is `nearby_connections` rather than Android's framework `WifiP2pManager`. The sender advertises its session ID and the receiver discovers that same ID. NFC and QR currently carry a URL that contains both a session ID and a `sig` secret; the receiver needs both values:

- `WifiDirectService.connectSession(sessionId, sessionSecret)` sends the secret as the Nearby connection endpoint name.
- The web fallback requests `GET /api/session/:id?sig=...`.
- The server authorizes reads using the same stored token.

Consequently, a native optimistic record must retain a securely generated **session pair** (`sessionId`, `sessionSecret`), even though the public lifecycle terminology centres on the session ID. An ID-only NFC payload would not preserve the present Wi-Fi Direct or web protocol. The URL remains the existing `/view/:id?sig=:secret` route with NFC metadata added as a non-security query parameter; a new `/nfc/:id` route would require backend/web work that is not yet present.

The existing five-minute server TTL is the baseline expiry for the native pending session, subject to a later decision only if device testing establishes a need to shorten it.

## Existing HCE implementation

`app` depends on the published `flutter_nfc_hce: ^0.1.8`; there is no vendored fork or path override. The manifest registers the package's `com.novice.flutter_nfc_hce.KHostApduService` and its `@xml/apduservice` declares the generic NFC Forum Type 4 NDEF AID `D2760000850101` in `category="other"`.

The installed package implements the expected Type 4 sequence: SELECT NDEF application, SELECT/READ capability container, SELECT NDEF file, then READ BINARY for NDEF length and byte chunks. It currently builds a text NDEF record for `text/plain`, persists the URL in `NdefMessage.txt`, deletes that file in `onDestroy`, and logs full APDUs and payloads. It reads storage in field initializers, trusts a nullable start intent with `!!`, and slices arbitrary APDUs without bounds checks. Those behaviors make it unsuitable as the HCE service used for an app-closed handoff.

The repository's `app/.agent/workflows/patch-nfc-uri.md` documents a manual `~/.pub-cache` modification that creates URI records. That patch is **not present** in the installed package. It is therefore non-reproducible and must be deliberately migrated into app-owned, version-controlled Kotlin rather than relied upon.

The existing Dart wrapper (`NFCService`) starts this package only after Flutter has generated a URL. It cannot generate or persist a session when Flutter is unavailable. Its `startNfcHce()` result only acknowledges starting the Android service; it does not confirm that an HCE transaction has been routed to SWAP.

## Sender/session integration

`SwapSessionManager.startSwap()` presently:

1. creates two eight-character lowercase-alphanumeric values (session ID and secret);
2. starts Nearby advertising and HCE before server registration;
3. uploads the session to the server; and
4. waits for an incoming Nearby connection.

This already has the required optimistic ordering while Flutter is open. The native HCE path must reserve the same pair first, return a frozen NDEF snapshot immediately, and let Flutter later enter this same sender path without replacing either value. Current `startSwap()` cannot accept a forced pair, so Phase 4 needs a narrow sender-start entry point rather than a second Wi-Fi/session implementation.

Current ID entropy is approximately 41 bits (`36^8`) and does not meet this implementation specification's high-entropy requirement. The native generator should generate URL-safe 128-bit values for both ID and secret. Server-side format hardening is deliberately separate security work; current server validation accepts the existing string format.

## Incoming-link and App Link integration

`HomeScreen` owns the sole current `app_links` subscription. It accepts only `/view/:id?sig=:secret`, then navigates to `JoinScreen`; it has no native `ACTION_NDEF_DISCOVERED` normalization and no explicit NFC provenance. The initial link is processed only after profile loading, so an incoming event can be discarded when no valid profile exists. Phase 5 needs one retained/queued incoming-link model and a single parser that identifies NFC metadata while preserving normal links.

There is a deployment mismatch that must be resolved before App Link verification:

- The user-edited Dart configuration currently uses `swapapp-web.onrender.com`.
- The committed Android manifest still declares `swapapp.ddns.net` for both HTTP and HTTPS `/view/` links.
- `server/public/.well-known/assetlinks.json` contains package `com.shiyuki.swap` and two certificate fingerprints, but it will only verify when served from the exact active HTTPS host.

Phase 5 must change only the verified HTTPS host/path after checking that the active Render domain serves this existing asset-links file and that its certificate fingerprints match the release signing configuration. The HTTP App Link must not be retained as a verified-link substitute.

## Permissions and background boundaries

The manifest already declares NFC/HCE, `BIND_NFC_SERVICE`, Nearby Wi-Fi, Bluetooth, and location permissions. `WifiDirectService` requests permissions and may prompt to enable Bluetooth/location itself. This is appropriate only from visible Flutter UI; it must not be reached from `HostApduService`.

The HCE service declaration has `requireDeviceScreenOn="false"` and `requireDeviceUnlock="false"`. Actual screen-off/lock behaviour still depends on Android version and Secure NFC state. No background Activity launch, Flutter initialization, network request, permission prompt, or Nearby startup can become part of `processCommandApdu()`.

The generic Type 4 AID can collide with other NDEF-HCE services. An AAR is NDEF payload metadata and cannot influence service selection, which occurs when Android routes the initial SELECT AID. Diagnostics and foreground preference are appropriate only after the baseline transfer is stable; a custom SWAP AID remains a later native-to-native enhancement.

## Verified platform constraints

Android's current HCE documentation confirms that an HCE service can run in the background, `processCommandApdu()` is called on the application's main thread and must not be blocked, and AID selection precedes service invocation. It also confirms that duplicate AIDs can require user selection and that foreground apps can request a preferred service. See [HCE overview](https://developer.android.com/develop/connectivity/nfc/hce).

For web-link NDEF records, Android 16 dispatches HTTPS/HTTP scans using `ACTION_VIEW` rather than `ACTION_NDEF_DISCOVERED`; Android 17 requires explicit interaction with an open-link notification. Android's current guidance is to use verified App Links. Android 17 also adds NFC intent protections and does not dispatch NFC intents to an app in a stopped state. See [NFC basics](https://developer.android.com/develop/connectivity/nfc/nfc).

For Android 13+ Wi-Fi APIs, `NEARBY_WIFI_DEVICES` is a runtime permission; older and some scan APIs retain location requirements. See [Nearby Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions).

## Phase 2 boundary

The smallest safe first code slice is an app-owned native implementation that preserves the existing generic Type 4 NDEF APDU sequence while adding:

- a secure native session-pair generator;
- an atomic `PendingNfcSessionStore` with the existing TTL;
- an immutable NDEF URI + AAR snapshot for one activation; and
- defensive APDU/state handling with debug-only redacted logs.

It must work without Flutter being attached and must not start Nearby/server work. Flutter handoff, App Links, waiting receiver behaviour, and AID diagnostics remain later, separately tested slices.

## Required device checks before declaring HCE support complete

No NFC hardware transaction was available in this environment. Before release, test an active reader against: sender foreground; sender app closed after prior launch; interrupted/repeated reads; duplicate generic-NDEF HCE services; denied Nearby permission; Android 16 `ACTION_VIEW`; and Android 17 notification-mediated link opening. Force-stopped and never-launched app cases must remain documented as unsupported rather than promised.
