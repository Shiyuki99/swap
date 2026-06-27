---
description: Patch flutter_nfc_hce to create URI records instead of TEXT records for iOS URL compatibility
---

# Patch flutter_nfc_hce for URI Records

The `flutter_nfc_hce` plugin creates TEXT records (`RTD_TEXT`) instead of URI records (`RTD_URI`). iOS doesn't recognize TEXT records as clickable URLs. This patch fixes that.

## When to run this

Run this workflow after:
- Running `flutter clean`
- Running `flutter pub get` or `flutter pub upgrade`
- Reinstalling Flutter packages
- Getting NFC URLs that won't open on iOS (shows as text instead of URL)

## Steps

1. Patch the KHostApduService.kt to create URI records for URLs:

// turbo
```bash
sed -i 's/if(mimeType == "text\/plain") {/if(mimeType == "text\/plain" \&\& !content.startsWith("http")) {/' ~/.pub-cache/hosted/pub.dev/flutter_nfc_hce-0.1.8/android/src/main/kotlin/com/novice/flutter_nfc_hce/KHostApduService.kt
```

2. Add URI record creation method after the createTextRecord method:

// turbo
```bash
sed -i '/return NdefRecord(NdefRecord.TNF_WELL_KNOWN, NdefRecord.RTD_TEXT, id, recordPayload)/a\    }\n\n    private fun createUriRecord(uri: String, id: ByteArray): NdefRecord {\n        val prefixCode: Byte\n        val uriBody: String\n        if (uri.startsWith("https:\/\/www.")) {\n            prefixCode = 0x02.toByte()\n            uriBody = uri.substring(12)\n        } else if (uri.startsWith("http:\/\/www.")) {\n            prefixCode = 0x01.toByte()\n            uriBody = uri.substring(11)\n        } else if (uri.startsWith("https:\/\/")) {\n            prefixCode = 0x04.toByte()\n            uriBody = uri.substring(8)\n        } else if (uri.startsWith("http:\/\/")) {\n            prefixCode = 0x03.toByte()\n            uriBody = uri.substring(7)\n        } else {\n            prefixCode = 0x00.toByte()\n            uriBody = uri\n        }\n        val uriBytes = uriBody.toByteArray(charset("UTF-8"))\n        val payload = ByteArray(1 + uriBytes.size)\n        payload[0] = prefixCode\n        System.arraycopy(uriBytes, 0, payload, 1, uriBytes.size)\n        return NdefRecord(NdefRecord.TNF_WELL_KNOWN, NdefRecord.RTD_URI, id, payload)' ~/.pub-cache/hosted/pub.dev/flutter_nfc_hce-0.1.8/android/src/main/kotlin/com/novice/flutter_nfc_hce/KHostApduService.kt
```

3. Modify createNdefRecord to call createUriRecord for URLs:

// turbo
```bash
sed -i 's/return createTextRecord("en", content, id);/if(content.startsWith("http")) {\n            return createUriRecord(content, id)\n        }\n        return createTextRecord("en", content, id);/' ~/.pub-cache/hosted/pub.dev/flutter_nfc_hce-0.1.8/android/src/main/kotlin/com/novice/flutter_nfc_hce/KHostApduService.kt
```

4. Verify the patch was applied:

// turbo
```bash
grep -A 5 "createUriRecord" ~/.pub-cache/hosted/pub.dev/flutter_nfc_hce-0.1.8/android/src/main/kotlin/com/novice/flutter_nfc_hce/KHostApduService.kt | head -10
```

5. Rebuild:

```bash
flutter clean && flutter pub get && flutter run --debug
```

## Notes

- This patch modifies `mimeType == "text/plain"` to only apply to non-URL content
- URLs (starting with "http") now get proper URI NDEF records
- URI records use TNF_WELL_KNOWN (0x01) with RTD_URI ('U' = 0x55)
- iOS recognizes URI records as clickable links
