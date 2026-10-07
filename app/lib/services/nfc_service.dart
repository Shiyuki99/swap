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
