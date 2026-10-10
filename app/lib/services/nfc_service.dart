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
  /// immutable NDEF snapshot served by SwapHostApduService. On success the
  /// service is also set as the foreground preferred HCE service so our AIDs
  /// win routing against other NDEF-HCE apps while sharing.
  Future<void> writeUUID(String urlToSend) async {
    debugPrint('[NFC] Starting HCE session');
    try {
      final started =
          await _channel.invokeMethod<bool>('startSession', {'url': urlToSend});
      _isHceActive = started == true;
      if (!_isHceActive) {
        debugPrint('[NFC] Native side rejected the session URL');
        return;
      }
      await setPreferredService();
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error starting HCE: ${e.message}');
    }
  }

  /// Stop NFC HCE broadcasting.
  Future<void> stopSession() async {
    debugPrint('[NFC] Stopping HCE session');
    try {
      await _channel.invokeMethod<bool>('stopSession');
      await unsetPreferredService();
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error stopping HCE: ${e.message}');
    } finally {
      _isHceActive = false;
    }
  }

  /// Route our AIDs to SwapHostApduService while the app is foreground.
  /// Returns false when the OS rejects the request (activity not resumed or
  /// user forbids foreground override of the wallet) — HCE still serves,
  /// just without routing priority.
  Future<bool> setPreferredService() async {
    try {
      final preferred =
          await _channel.invokeMethod<bool>('setPreferred') == true;
      debugPrint('[NFC] Preferred service set: $preferred');
      if (!preferred) {
        final allowed =
            await _channel.invokeMethod<bool>('allowsForegroundPreference');
        debugPrint('[NFC] Foreground override allowed: $allowed');
      }
      return preferred;
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error setting preferred service: ${e.message}');
      return false;
    }
  }

  /// Release the foreground preferred-service routing.
  Future<void> unsetPreferredService() async {
    try {
      await _channel.invokeMethod<bool>('unsetPreferred');
    } on PlatformException catch (e) {
      debugPrint('[NFC] Error unsetting preferred service: ${e.message}');
    }
  }

  bool get isHceActive => _isHceActive;
}
