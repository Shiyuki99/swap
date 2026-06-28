import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import '../constants/platform_config.dart';
import '../models/profile.dart';
import 'wifi_direct_service.dart';
import 'nfc_service.dart';

/// The current state of the swap session.
enum SwapState {
  /// No swap in progress.
  idle,

  /// Advertising WiFi Direct, showing QR, running NFC toggle loop.
  advertising,

  /// Role determined, attempting WiFi Direct connection.
  connecting,

  /// WiFi Direct connected, exchanging profile data.
  exchanging,

  /// Swap completed successfully.
  complete,

  /// An error occurred.
  error,
}

/// Result of the connection race.
class ConnectionResult {
  final String remoteUUID;

  ConnectionResult({required this.remoteUUID});
}

class SwapSessionManager extends ChangeNotifier {
  final WifiDirectService _wifiDirectService;
  final NFCService _nfcService;
  final _dio = Dio();

  SwapState _state = SwapState.idle;
  String? _sessionID;
  String? _sessionURL;
  String? _sessionSECRET;
  Profile? _myProfile;
  Profile? _receivedProfile;
  String? _errorMessage;
  bool? _webAvailable;

  // Cancellation flags
  bool _isCancelled = false;

  // SERVER SESSION CREATION
  // The web server displays the profile page — no polling or race needed
  // since the web view is read-only for now.

  /// Upload profile to server for web view display
  /// POST to: $swapBaseUrl/api/session
  Future<void> _uploadProfileToServer() async {
    if (_sessionID == null || _sessionSECRET == null) {
      debugPrint('[SERVER] Cannot set session — missing ID or secret');
      return;
    }
    const maxRetries = 3;
    String currentId = _sessionID!;
    try {
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        final response = await _dio.post(
          '$swapBaseUrl/api/session',
          data: {
            'sessionId': _sessionID,
            'token': _sessionSECRET,
            'profile': _myProfile!.toJson(),
          },
        );

        if (response.statusCode == 201) {
          debugPrint('[SERVER] Session created on web server: $currentId');
          // Update session ID if it changed due to conflict
          if (currentId != _sessionID) {
            _sessionID = currentId;
            _sessionURL = swapProfileUrl(currentId, _sessionSECRET!);
          }
          _webAvailable = true;
          notifyListeners();
          return;
        } else if (response.statusCode == 409 && attempt < maxRetries - 1) {
          // Session ID conflict — regenerate and retry
          currentId = _generateRandomString(8);
          debugPrint(
            '[SERVER] Session ID conflict, retrying with: $currentId (attempt ${attempt + 2}/$maxRetries)',
          );
          continue;
        } else {
          debugPrint(
            '[SERVER] Failed to create session: ${response.statusCode} ${response.data}',
          );
          _webAvailable = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      // Don't throw — server upload is non-critical, swap works via WiFi Direct
      debugPrint('[SERVER] Error creating session: $e');
      _webAvailable = false;
      notifyListeners();
    }
    return;
  }

  // Getters
  SwapState get state => _state;
  String? get sessionID => _sessionID;
  String? get sessionURL => _sessionURL;
  Profile? get receivedProfile => _receivedProfile;
  String? get errorMessage => _errorMessage;
  bool? get webAvailable => _webAvailable;
  bool get isNfcActive => _nfcService.isHceActive;

  SwapSessionManager({
    required WifiDirectService wifiDirectService,
    required NFCService nfcService,
  }) : _wifiDirectService = wifiDirectService,
       _nfcService = nfcService;

  /// Start the swap session.
  ///
  /// This triggers:
  /// 1. UUID generation
  /// 2. WiFi Direct advertising
  /// 3. NFC (DISABLED)
  /// 4. QR code display (handled by UI using sessionUUID)
  ///
  /// Returns the profile received from the other device.
  Future<Profile?> startSwap(Profile myProfile) async {
    if (_state != SwapState.idle) {
      throw StateError('Swap already in progress');
    }

    // Validate profile before starting swap
    if (!myProfile.isValidForSwap) {
      throw Exception(
        'Profile is not valid for swapping. Please add your name and at least one social link.',
      );
    }

    _myProfile = myProfile;
    _isCancelled = false;

    debugPrint('[SWAP] === STARTING SWAP ===');
    debugPrint('[SWAP] Profile: ${myProfile.name}');

    try {
      // Phase 1: Initialize - Generate random 8-char session ID and secret
      _sessionID = _generateRandomString(8);
      _sessionSECRET = _generateRandomString(8);

      _updateState(SwapState.advertising);

      _sessionURL = await createUrl();

      // Check cancellation before starting operations
      if (_isCancelled) return null;

      // Phase 2: Start concurrent operations
      await _startConcurrentOperations(); // we make them locally available before server
      await _uploadProfileToServer();

      // Check cancellation after starting operations
      if (_isCancelled) return null;

      // Phase 3: Wait for incoming connection
      try {
        await _wifiDirectService.waitForIncomingConnection();
      } catch (e) {
        if (_isCancelled) return null;
        rethrow;
      }

      // Check cancellation before exchange
      if (_isCancelled) return null;

      // Phase 5: Connect and exchange
      await _connectAndExchange();

      // Check cancellation before saving
      if (_isCancelled) return null;

      // Return immediately when we have the profile
      // The background cleanup can continue while user views ResultScreen
      if (_receivedProfile != null) {
        _updateState(SwapState.complete);

        // History is now saved in ResultScreen with the user's note
        _wifiDirectService.markExchangeComplete();

        return _receivedProfile;
      }

      _updateState(SwapState.complete);
      return _receivedProfile;
    } catch (e) {
      _errorMessage = e.toString();
      _updateState(SwapState.error);
      rethrow;
    } finally {
      // Background cleanup - don't block the UI
      stopAllOperations();
    }
  }

  Future<String?> createUrl() async {
    // Uses swapProfileUrl from platform_config.dart
    // Update swapDomain constant when you host your backend
    if (_sessionID == null || _sessionSECRET == null) return null;
    return swapProfileUrl(_sessionID!, _sessionSECRET!);
  }

  /// Join an existing swap session by scanning QR/NFC.
  ///
  /// This is called by the scanning device. It:
  /// 1. Parses the session ID from the URL
  /// 2. Stops local advertising (if any)
  /// 3. Connects to the advertising device via WiFi Direct
  /// 4. Performs the profile exchange
  ///
  /// Returns the received profile from the other device.
  Future<Profile?> joinSwap(String scannedUrl, Profile myProfile) async {
    if (_state != SwapState.idle && _state != SwapState.advertising) {
      throw StateError('Cannot join swap in current state: $_state');
    }

    _myProfile = myProfile;
    _isCancelled = false;

    // Validate profile before starting swap
    if (!myProfile.isValidForSwap) {
      throw Exception(
        'Profile is not valid for swapping. Please add your name and at least one social link.',
      );
    }

    debugPrint('[SWAP] === JOINING SWAP ===');
    debugPrint('[SWAP] Profile: ${myProfile.name}');

    try {
      // Parse session ID from URL
      // URL format: https://website/view/{sessionID}?sig={secret}
      _parseSessionInfoFromUrl(scannedUrl);
      if (_sessionID == null) {
        throw Exception('Invalid QR code URL: could not extract session ID');
      }

      debugPrint('[SWAP] Session ID: $_sessionID');

      // Stop our own advertising if we were advertising
      await stopAllOperations();
      _isCancelled = false; // Reset since stopAllOperations sets this

      _updateState(SwapState.connecting);

      // Set our profile data for exchange
      _wifiDirectService.setLocalProfileData(_myProfile!.toBytes());

      // Connect to the advertising device using the session ID
      await _wifiDirectService.connectSession(_sessionID!, _sessionSECRET!);

      if (_isCancelled) return null;

      // Exchange profiles
      await _connectAndExchange();

      if (_isCancelled) return null;

      // Return immediately when we have the profile
      if (_receivedProfile != null) {
        _updateState(SwapState.complete);

        // History is now saved in ResultScreen with the user's note
        _wifiDirectService.markExchangeComplete();

        return _receivedProfile;
      }

      _updateState(SwapState.complete);
      return _receivedProfile;
    } catch (e) {
      _errorMessage = e.toString();
      _updateState(SwapState.error);
      rethrow;
    } finally {
      // Background cleanup
      stopAllOperations();
    }
  }

  /// Parse session ID from a swap URL.
  /// URL format: https://website/view/{sessionID}?sig={secret}
  void _parseSessionInfoFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      final viewIndex = pathSegments.indexOf('view');
      if (viewIndex != -1 && viewIndex + 1 < pathSegments.length) {
        _sessionID = pathSegments[viewIndex + 1];
        _sessionSECRET = uri.queryParameters['sig'];
      }
    } catch (e) {
      debugPrint('Error parsing URL: $e');
    }
  }

  /// Start all concurrent detection methods.
  Future<void> _startConcurrentOperations() async {
    if (_isCancelled) return;

    // Set profile data for exchange
    _wifiDirectService.setLocalProfileData(_myProfile!.toBytes());

    // Start WiFi Direct advertising
    await _wifiDirectService.createSession(_sessionID!, _sessionSECRET ?? '');

    if (_isCancelled) return;

    // Start NFC URL broadcasting via HCE
    await _nfcService.writeUUID(_sessionURL!);

    // QR display is handled by the UI using sessionURL getter
  }

  /// Connect (if client) and exchange profile data.
  Future<void> _connectAndExchange() async {
    _updateState(SwapState.exchanging);

    debugPrint('[SWAP] === EXCHANGING ===');
    final myProfileJson = jsonEncode(_myProfile!.toJson());

    // Set local profile data for the WifiDirectService to send
    _wifiDirectService.setLocalProfileData(
      Uint8List.fromList(utf8.encode(myProfileJson)),
    );

    // Poll for received data - check every 100ms, timeout after 30 seconds
    const pollInterval = Duration(milliseconds: 100);
    const maxWait = Duration(seconds: 30);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWait) {
      // Check if we received data
      final receivedData = _wifiDirectService.receivedProfileData;
      if (receivedData != null && receivedData.isNotEmpty) {
        try {
          final receivedJson = utf8.decode(receivedData);
          final decoded = jsonDecode(receivedJson) as Map<String, dynamic>;
          _receivedProfile = Profile.fromJson(decoded);
          debugPrint('[SWAP] Received profile: ${_receivedProfile!.name}');
          notifyListeners();
          return; // Exit immediately with data!
        } catch (e) {
          debugPrint('[SWAP] Parse error: $e');
          // Try fallback
          _receivedProfile = Profile.fromBytes(receivedData);
          debugPrint('[SWAP] Fallback parsed: ${_receivedProfile!.name}');
          notifyListeners();
          return;
        }
      }

      // Check cancellation
      if (_isCancelled) return;

      // Wait before next poll
      await Future.delayed(pollInterval);
    }

    debugPrint('[SWAP] Exchange timeout - no data received');
    notifyListeners();
  }

  /// Stop all operations and clean up.
  Future<void> stopAllOperations() async {
    _isCancelled = true;
    //_nfcToggleTimer?.cancel();
    //_nfcToggleTimer = null;

    try {
      await _wifiDirectService.stopAdvertising();
      await _nfcService.stopSession();
    } catch (e) {
      // Ignore cleanup errors
      if (kDebugMode) {
        print('Cleanup error: $e');
      }
    }
  }

  /// Cancel the current swap session.
  Future<void> cancel() async {
    _isCancelled = true;

    // Cancel the incoming connection wait in WiFi Direct service
    _wifiDirectService.cancelWaitForConnection();

    // Tell the server to delete this session
    _deleteServerSession();

    await stopAllOperations();
    _reset();
  }

  /// Send DELETE to the server to clean up the session immediately.
  void _deleteServerSession() {
    if (_sessionID == null || _sessionSECRET == null) return;
    final id = _sessionID;
    final secret = _sessionSECRET;
    // Fire-and-forget — don't block the UI
    _dio
        .delete('$swapBaseUrl/api/session/$id?sig=$secret')
        .then((_) => debugPrint('[SERVER] Session cancelled: $id'))
        .catchError((e) => debugPrint('[SERVER] Error cancelling session: $e'));
  }

  /// Reset the manager to idle state.
  void _reset() {
    _state = SwapState.idle;
    _sessionID = null;
    _sessionURL = null;
    _sessionSECRET = null;
    _myProfile = null;
    _receivedProfile = null;
    _errorMessage = null;
    _isCancelled = false;
    notifyListeners();
  }

  void _updateState(SwapState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    //_nfcToggleTimer?.cancel();
    super.dispose();
  }

  /// Generate a random alphanumeric string of the specified length
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
