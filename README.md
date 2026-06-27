<p align="center">
  <img src="app/assets/icons/SWAP-LOGO.svg" alt="SWAP" width="120">
</p>

<h1 align="center">SWAP</h1>

<p align="center">
  <strong>Exchange social media profiles instantly</strong> — tap, scan, or connect nearby.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/flutter-3.41%2B-blue" alt="Flutter">
  <img src="https://img.shields.io/badge/node-18%2B-green" alt="Node">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

---

## What is SWAP?

SWAP lets you share all your social media handles and contact info with anyone in seconds. No typing usernames, no searching — just swap.

### Swap Methods

| Method | Description |
|--------|-------------|
| **QR Code** | Display your QR or scan someone else's to swap profiles instantly |
| **NFC Tap** | Tap phones together to share (Android, via Host Card Emulation) |
| **WiFi Direct** | Peer-to-peer exchange via Google Nearby Connections |
| **Web Link** | Share a temporary link viewable in any browser |

### Supported Platforms

Instagram · Twitter/X · Discord · Snapchat · TikTok · GitHub · Email · Phone

---

## Project Structure

```
swap/
├── app/            # Flutter mobile app
│   ├── lib/        # Dart source code
│   ├── assets/     # Icons, logos, animations
│   ├── android/    # Android native config
│   └── ios/        # iOS native config
├── server/         # Node.js companion web server
│   ├── server.js   # Express server entry point
│   ├── views/      # EJS templates
│   └── public/     # Static assets & icons
├── .github/        # CI/CD workflows
└── README.md
```

---

## App (`app/`)

Flutter mobile app for Android and iOS.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| State Management | `provider` |
| Nearby Connections | `nearby_connections` (Google Nearby API) |
| NFC | `flutter_nfc_hce` (Host Card Emulation) |
| QR Code | `pretty_qr_code` + `mobile_scanner` |
| Bluetooth | `flutter_blue_plus` |

### Getting Started

**Prerequisites:** Flutter 3.41+, Android SDK (min API 21), Java 17

```bash
cd app
flutter pub get
flutter run
```

#### Required NFC Patches

After `flutter pub get`, apply two NFC plugin patches:

1. **AGP 8+ compatibility** — Fixes deprecated `package` attribute in `nfc_host_card_emulation`
2. **URI NDEF records** — Creates proper URI records so iOS devices open tappable links (instead of TEXT records)

These patches modify your local pub cache and must be re-applied after `flutter clean` or `flutter pub get`. Without them, NFC sharing still works between Android devices, but iOS won't open the link when tapped.

```bash
# Apply both patches
/fix-nfc-plugin
/patch-nfc-uri
```

### Build Release APK

```bash
cd app
flutter build apk --release
```

The signed APK will be at `app/build/app/outputs/flutter-apk/app-release.apk`.

---

## Server (`server/`)

Node.js + Express companion web server for temporary profile sharing, app update checks, and usage tracking.

### Endpoints

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/api/session` | Create a swap session |
| `GET` | `/view/:sessionId` | View shared profile page |
| `DELETE` | `/api/session/:id` | Cancel a session |
| `GET` | `/api/check-update` | Check for app updates |
| `GET` | `/api/stats` | View usage statistics (JSON) |
| `GET` | `/health` | Health check |

### Getting Started

```bash
cd server
npm install
npm start
```

The server listens on `PORT` (env) or port 3000, bound to `0.0.0.0`.

### Deployment

The server is designed to be deployed on Render or any Node.js host. Just set the `PORT` environment variable and run `npm start`.

---

## CI/CD

A GitHub Actions workflow automatically builds a signed release APK when a version tag is pushed:

```bash
git tag v1.0.1
git push origin main v1.0.1
```

The keystore is stored as GitHub Secrets (`KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and decoded at build time.

---

## License

MIT — see [LICENSE](app/LICENSE)
