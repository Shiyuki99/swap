# `flutter_nfc_hce` Copyability and Modernization Assessment

## Recommendation

Copying the package's ideas into this repository is viable and preferable to continuing its pub-cache patch workflow. Do not wholesale-copy the package. Retain the MIT notice, reuse the Type 4 Tag protocol core selectively, and build an app-owned Android implementation around current lifecycle, validation, URI-NDEF, and test requirements.

## Legal and maintenance position

`flutter_nfc_hce` 0.1.8 is MIT-licensed, so copying, modifying, and redistributing its code is permitted if its copyright and license notice remain in the derived source. The installed package and [upstream repository](https://github.com/deokgyuhan/flutter_nfc_hce) identify the license.

The latest pub.dev release is 0.1.8, published two years ago, and the upstream branch's latest commit is from September 2023. The package is Android-only and published by an unverified uploader. It should be treated as an unmaintained proof of concept, not an actively maintained compatibility layer. [Package release history](https://pub.dev/packages/flutter_nfc_hce/versions) and [upstream commit history](https://github.com/deokgyuhan/flutter_nfc_hce/commits/master/) support this assessment.

## Current mismatch in this app

`app/lib/services/nfc_service.dart` says the dependency has been patched to emit URI NDEF records for URLs. The installed `flutter_nfc_hce` 0.1.8 `KHostApduService.kt` still creates `RTD_TEXT` for `text/plain`, including URLs. The repository's `app/.agent/workflows/patch-nfc-uri.md` documents a manual edit under `~/.pub-cache`; that edit is outside version control and disappears after dependency restoration.

Consequently, the app can regress to text NDEF records and iPhones may not treat the URL as a tap-to-open link. The package has an open report of intermittent iPhone/Apple Pay behavior, reinforcing that this is not a reliable cross-device path. [Upstream issue #2](https://github.com/deokgyuhan/flutter_nfc_hce/issues/2).

## How much can be copied?

| Area | Assessment | Recommendation |
| --- | --- | --- |
| License | 100% legally reusable with attribution | Add a retained MIT notice to derived Kotlin files. |
| Type 4 Tag APDU constants and read flow | About 60–70% useful as a protocol starting point | Reuse only after tests validate every command and offset. |
| Native service implementation | About 35–45% safe for direct reuse | Rewrite lifecycle, state handling, bounds checks, logging, and NDEF encoding. |
| Dart wrapper API | Small surface is worth keeping | Use an app-owned adapter; avoid copying plugin-platform-interface boilerplate unless publishing a plugin. |

The percentages are engineering estimates from the inspected 404-line Kotlin service and 280-line Dart wrapper/interface code; they are not a legal limitation.

## Defects and rewrite requirements

- The service reads a file through `this` in field initializers before Android attaches a service context. This matches the reported null-context crash in [upstream issue #5](https://github.com/deokgyuhan/flutter_nfc_hce/issues/5). Initialize data in `onCreate` instead.
- `intent?.hasExtra(...)!!` and APDU `sliceArray` calls can crash on null or malformed input. Validate all intent, command length, offsets, and requested lengths before indexing.
- The APDU implementation relies on exact command byte equality and a mutable `READ_CAPABILITY_CONTAINER_CHECK` flag. This is brittle across reader implementations and chunked reads.
- Its capability container declares a 255-byte NDEF file although comments claim 65,534 bytes. The upstream, unmerged [PR #3](https://github.com/deokgyuhan/flutter_nfc_hce/pull/3) documents stricter modern-Android behavior, a 32 KiB Type 4 Tag limit, a needed state-flow change, and short-command crash protection. Decide the supported maximum from the relevant NFC Forum mapping version and test it; do not copy either value blindly.
- URI values must become native `NdefRecord.RTD_URI` records with correct URI prefix compression, not a conditional cache patch over text records.
- `startNfcHce` returns a success string before confirming service activation, and its capability check conflates enabled NFC with HCE support. Return typed states such as unsupported, disabled, started, and failed.
- Persistence stores the current URL—including its session signature—while the README simultaneously describes background persistence and the service deletes the file on destruction. Default to no persistence and make any recovery behavior explicit and time-bounded.
- APDU and URL logging exposes the share URL/signature. Remove payload logging in release builds.

## Current Android considerations

The app's existing manifest is structurally close: it uses `android.permission.BIND_NFC_SERVICE`, an exported host APDU service, and a `category="other"` AID. Android documents that the system-only bind permission protects HCE service interaction and recommends foreground service preference when an app expects to emulate a card. [Android HCE overview](https://developer.android.com/develop/connectivity/nfc/hce).

Android 15 introduces Observe Mode and polling-loop APIs. They are not automatically required for this non-payment sharing service, but Android's current documentation says foreground preference, competing AIDs, default-wallet behavior, and OEM NFC behavior affect routing. Screen-off operation also depends on Android version and Secure NFC state; `requireDeviceScreenOn="false"` only helps where the platform permits it. [Current HCE behavior](https://developer.android.com/develop/connectivity/nfc/hce) and [HostApduService API](https://developer.android.com/reference/android/nfc/cardemulation/HostApduService) are the primary references.

## Proposed owned architecture

- `app/android/.../SwapHostApduService.kt`: validated Type 4 Tag APDU state machine only.
- `app/android/.../NdefUriEncoder.kt`: pure URI-record encoder with Kotlin unit tests.
- `app/android/.../NfcHceChannel.kt`: Flutter method-channel bridge returning typed lifecycle results.
- `app/lib/services/nfc_service.dart`: small Dart adapter that exposes capability, enablement, start, and stop states without assuming success.
- Manifest metadata remains in app control and uses a proprietary `category="other"` AID, with foreground preference only while the share UI is active.

Test the URI bytes, SELECT/read flows, multi-chunk reads, malformed APDUs, null/restart lifecycle, cancellation, and expired URL cleanup in unit tests. Then run device tests on Android 12 through the current Android release, at least Pixel and Samsung hardware, Android readers, and iPhone background URL recognition. NFC hardware/OEM interoperability is the main remaining risk; it cannot be proven by Flutter or Kotlin unit tests alone.

## Bottom line

Reuse the protocol concept and small public API, but own the implementation. A controlled rewrite gives you a reproducible URI record, removes sensitive cache patching, handles current Android behavior, and makes future NFC changes testable in this repository.
