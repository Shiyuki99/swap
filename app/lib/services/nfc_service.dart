import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_hce/flutter_nfc_hce.dart';

/// NFC Service for URL sharing via HCE (Host Card Emulation).
/// Uses patched flutter_nfc_hce package that creates proper URI NDEF records.
/// Note: HCE is only available on Android. iOS does not support third-party HCE.
class NFCService {
  final FlutterNfcHce _nfcHce = FlutterNfcHce();
  bool _isHceActive = false;

  /// Check if NFC HCE is supported on this device.
  Future<bool> isNFCAvailable() async {
    try {
      final isSupported = await _nfcHce.isNfcHceSupported();
      return isSupported == true;
    } catch (e) {
      debugPrint('[NFC] Error checking NFC support: $e');
      return false;
    }
  }

  /// Check if NFC is enabled on the device.
  Future<bool> isNFCEnabled() async {
    try {
      final isEnabled = await _nfcHce.isNfcEnabled();
      return isEnabled == true;
    } catch (e) {
      debugPrint('[NFC] Error checking NFC enabled: $e');
      return false;
    }
  }

  /// Start broadcasting the URL via NFC HCE.
  /// The patched flutter_nfc_hce will detect http/https URLs and create
  /// proper URI NDEF records (RTD_URI) instead of TEXT records.
  Future<void> writeUUID(String urlToSend) async {
    debugPrint('[NFC] Starting HCE with URL: $urlToSend');

    try {
      // Check if NFC is supported
      final isSupported = await _nfcHce.isNfcHceSupported();
      if (isSupported != true) {
        debugPrint('[NFC] NFC HCE not supported on this device');
        return;
      }

      // Check if NFC is enabled
      final isEnabled = await _nfcHce.isNfcEnabled();
      if (isEnabled != true) {
        debugPrint('[NFC] NFC is not enabled');
        return;
      }

      // Start NFC HCE with the URL
      // The patched plugin will create a URI record for http/https URLs
      final result = await _nfcHce.startNfcHce(urlToSend);
      debugPrint('[NFC] startNfcHce result: $result');

      _isHceActive = true;
      debugPrint('[NFC] HCE is now active and broadcasting URL');
    } catch (e) {
      debugPrint('[NFC] Error starting HCE: $e');
    }
  }

  /// Stop NFC HCE broadcasting.
  Future<void> stopSession() async {
    debugPrint('[NFC] Stopping HCE session');
    try {
      await _nfcHce.stopNfcHce();
      _isHceActive = false;
      debugPrint('[NFC] HCE session stopped');
    } catch (e) {
      debugPrint('[NFC] Error stopping HCE: $e');
    }
  }

  bool get isHceActive => _isHceActive;
}
