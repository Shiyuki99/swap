import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:location/location.dart';

class WifiDirectService {
  final Nearby _nearby = Nearby();
  String _targetEndpointId = '';
  bool _isAdvertising = false;
  bool _isJoiner = false; // Explicit role flag
  Uint8List? _receivedProfileData;
  Uint8List? _localProfileData;
  final String _serviceId = 'com.SWAPapp';
  Completer<void>? _discoveryCompleter;
  Completer<void>? _exchangeCompleter;
  Completer<void>? _incomingConnectionCompleter;
  bool _exchangeComplete = false;
  String? _secret;

  // Getters
  Uint8List? get receivedProfileData => _receivedProfileData;
  bool get isExchangeComplete =>
      _exchangeComplete && _receivedProfileData != null;
  bool get hasReceivedData => _receivedProfileData != null;

  // Track if we turned on these services so we can turn them back off externally
  bool didEnableBluetooth = false;
  bool didEnableLocation = false;

  String get _role => _isJoiner ? 'JOINER' : 'ADVERTISER';

  /// Check if all required permissions are granted
  Future<bool> _checkPermission() async {
    final locationGranted = await Permission.location.isGranted;
    final bluetoothPermissions = await Future.wait([
      Permission.bluetooth.isGranted,
      Permission.bluetoothAdvertise.isGranted,
      Permission.bluetoothConnect.isGranted,
      Permission.bluetoothScan.isGranted,
    ]);
    final bluetoothGranted = !bluetoothPermissions.any((granted) => !granted);
    final nearbyWifiGranted = await Permission.nearbyWifiDevices.isGranted;

    return locationGranted && (bluetoothGranted || nearbyWifiGranted);
  }

  /// Request all necessary permissions for Nearby Connections
  Future<bool> requestPermissions() async {
    await Permission.location.request();
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    final nearbyWifiStatus = await Permission.nearbyWifiDevices.request();
    if (nearbyWifiStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    return await _checkPermission();
  }

  /// Check if location services are enabled
  Future<bool> isLocationEnabled() async {
    return await Permission.location.serviceStatus.isEnabled;
  }

  /// Check requirements for WiFi Direct
  Future<Map<String, bool>> checkRequirements() async {
    var permissionsGranted = await _checkPermission();
    if (!permissionsGranted) {
      permissionsGranted = await requestPermissions();
    }

    final locationOn = await isLocationEnabled();
    final bluetoothOn = await Permission.bluetooth.serviceStatus.isEnabled;

    return {
      'permissionsGranted': permissionsGranted,
      'bluetoothOn': bluetoothOn,
      'locationOn': locationOn,
    };
  }

  /// Show dialog prompting user to enable Bluetooth/Location natively
  /// Returns [true] if user turned it on successfully, [false] otherwise.
  Future<bool> promptEnableServices() async {
    final locationOn = await isLocationEnabled();
    final bluetoothOn = await Permission.bluetooth.serviceStatus.isEnabled;

    // If Bluetooth is off, show native system dialog to turn it on
    if (!bluetoothOn) {
      try {
        await FlutterBluePlus.turnOn();
        // Check if it's now on
        final isOn = await FlutterBluePlus.adapterState.first;
        if (isOn == BluetoothAdapterState.on) {
          didEnableBluetooth = true; // Track that we turned it on
          // Bluetooth enabled, check if we still need location
          if (!locationOn) {
            // If location is off, show native system dialog to turn it on
            Location location = Location();
            var serviceEnabled = await location.requestService();
            if (!serviceEnabled) {
              return false; // User didn't enable location
            }
            didEnableLocation = true; // Track that we turned it on
          }
          return true; // Both are now enabled
        }
      } catch (e) {
        debugPrint('Failed to turn on Bluetooth: $e');
      }
      return false; // User declined bluetooth
    }

    // If only location is off, show dialog to open location
    if (!locationOn) {
      Location location = Location();
      var serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return false; // User didn't enable location
      }
      didEnableLocation = true; // Track that we turned it on
    }

    return true; // Already on
  }

  /// Create a session (advertise) with the given session ID and secret
  Future<void> createSession(String sessionID, String sessionSecret) async {
    if (!await _checkPermission()) {
      final granted = await requestPermissions();
      if (!granted) {
        throw Exception("Required permissions denied");
      }
    }

    _exchangeComplete = false;
    _receivedProfileData = null;
    _isJoiner = false; // Explicitly set role
    _isAdvertising = true;
    _secret = sessionSecret;

    debugPrint('[SWAP-$_role] Creating session: $sessionID');

    try {
      bool success = await _nearby.startAdvertising(
        sessionID,
        Strategy.P2P_POINT_TO_POINT,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      if (success) {
        debugPrint('[SWAP-$_role] Advertising started');
      }
    } catch (e) {
      _isAdvertising = false;
      throw Exception("Failed to start advertising: $e");
    }
  }

  /// Set the local profile data to send during exchange
  void setLocalProfileData(Uint8List profileData) {
    _localProfileData = profileData;
    debugPrint('[SWAP] Local profile data set: ${profileData.length} bytes');
  }

  /// Connect to a device with the given session ID (as discoverer/joiner)
  Future<void> connectSession(String sessionID, String sessionSecret) async {
    if (!await _checkPermission()) {
      final granted = await requestPermissions();
      if (!granted) {
        throw Exception("Required permissions denied");
      }
    }

    // Stop advertising if we were
    if (_isAdvertising) {
      await _nearby.stopAdvertising();
      _isAdvertising = false;
    }

    _exchangeComplete = false;
    _receivedProfileData = null;
    _isJoiner = true; // Explicitly set role

    debugPrint('[SWAP-$_role] Connecting to session: $sessionID');

    // Discover and connect to the advertiser
    await _discoverDevice(sessionID);
    await _waitForDiscovery();

    try {
      await _nearby.requestConnection(
        sessionSecret,
        _targetEndpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      debugPrint('[SWAP-$_role] Connection request sent');
    } catch (e) {
      throw Exception("Failed to connect: $e");
    }
  }

  Future<void> _discoverDevice(String sessionID) async {
    try {
      _discoveryCompleter = Completer<void>();
      await _nearby.startDiscovery(
        sessionID,
        Strategy.P2P_POINT_TO_POINT,
        onEndpointFound:
            (String endpointId, String name, String serviceId) async {
              debugPrint('[SWAP-$_role] Found: $name ($endpointId)');
              if (name == sessionID) {
                _targetEndpointId = endpointId;
                if (!_discoveryCompleter!.isCompleted) {
                  _discoveryCompleter!.complete();
                }
                await _nearby.stopDiscovery();
              }
            },
        onEndpointLost: (String? endpointId) {
          debugPrint('[SWAP-$_role] Lost endpoint: $endpointId');
        },
        serviceId: _serviceId,
      );
      debugPrint('[SWAP-$_role] Discovery started');
    } catch (e) {
      throw Exception("Couldn't start discovery: $e");
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) async {
    debugPrint(
      '[SWAP-$_role] Connection initiated: $endpointId (${info.endpointName})',
    );

    _targetEndpointId = endpointId;
    if (_isJoiner) {
      // Joiner receives Advertiser's sessionID as endpointName.
      // We already discovered them by sessionID, so we can verify or just accept.
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
      debugPrint('[SWAP-$_role] Connection accepted');
    } else {
      // Advertiser receives Joiner's sessionSecret as endpointName.
      if (info.endpointName == _secret) {
        await _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
          onPayloadTransferUpdate: _onPayloadTransferUpdate,
        );
        debugPrint('[SWAP-$_role] Connection accepted');
      } else {
        debugPrint('[SWAP-$_role] Rejecting connection: incorrect secret');
        await _nearby.rejectConnection(endpointId);
      }
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) async {
    debugPrint('[SWAP-$_role] Payload received, type: ${payload.type}');

    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      Uint8List receivedData = payload.bytes!;
      debugPrint('[SWAP-$_role] Received ${receivedData.length} bytes');

      // Store received data
      _receivedProfileData = receivedData;

      // If we're the advertiser (NOT joiner), we receive first, then send our response
      if (!_isJoiner) {
        debugPrint('[SWAP-$_role] Sending response...');
        if (_localProfileData != null) {
          _exchangeCompleter = Completer<void>();
          await _nearby.sendBytesPayload(_targetEndpointId, _localProfileData!);
          debugPrint(
            '[SWAP-$_role] Response sent: ${_localProfileData!.length} bytes',
          );
        } else {
          debugPrint('[SWAP-$_role] ERROR: No local data to send!');
        }
      }

      // Mark exchange as complete
      _exchangeComplete = true;
      if (_exchangeCompleter != null && !_exchangeCompleter!.isCompleted) {
        _exchangeCompleter!.complete();
      }
    } else {
      debugPrint(
        '[SWAP-$_role] WARNING: Invalid payload (bytes null or wrong type)',
      );
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    if (update.status == PayloadStatus.SUCCESS) {
      debugPrint('[SWAP-$_role] Transfer SUCCESS (our send completed)');
      // NOTE: Don't complete _exchangeCompleter here!
      // We only want to complete it when we RECEIVE data from the other party
      // The completer is completed in _onPayloadReceived when _receivedProfileData is set
    } else if (update.status == PayloadStatus.FAILURE) {
      debugPrint('[SWAP-$_role] Transfer FAILED');
      if (_exchangeCompleter != null && !_exchangeCompleter!.isCompleted) {
        _exchangeCompleter!.completeError("Transfer failed");
      }
    }
  }

  void _onConnectionResult(String endpointId, Status connectionStatus) async {
    debugPrint('[SWAP-$_role] Connection result: $connectionStatus');

    if (connectionStatus == Status.CONNECTED) {
      _targetEndpointId = endpointId;

      // Complete incoming connection wait
      if (_incomingConnectionCompleter != null &&
          !_incomingConnectionCompleter!.isCompleted) {
        _incomingConnectionCompleter!.complete();
      }

      // If we're the joiner, send our data first
      if (_isJoiner && _localProfileData != null) {
        // Small delay to ensure advertiser's acceptConnection is complete
        await Future.delayed(const Duration(milliseconds: 100));

        debugPrint(
          '[SWAP-$_role] Sending initial data: ${_localProfileData!.length} bytes',
        );
        _exchangeCompleter = Completer<void>();
        await _nearby.sendBytesPayload(endpointId, _localProfileData!);
        debugPrint('[SWAP-$_role] Initial data sent');
      } else if (!_isJoiner) {
        debugPrint('[SWAP-$_role] Waiting for joiner to send first...');
      }
    } else if (connectionStatus == Status.ERROR) {
      debugPrint('[SWAP-$_role] Connection ERROR');
      if (_incomingConnectionCompleter != null &&
          !_incomingConnectionCompleter!.isCompleted) {
        _incomingConnectionCompleter!.completeError("Connection failed");
      }
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('[SWAP-$_role] Disconnected: $endpointId');
    _targetEndpointId = '';
  }

  /// Wait for an incoming connection (when advertising)
  Future<void> waitForIncomingConnection() async {
    if (_targetEndpointId.isNotEmpty) {
      debugPrint('[SWAP-$_role] Already connected');
      return;
    }

    _incomingConnectionCompleter = Completer<void>();
    debugPrint('[SWAP-$_role] Waiting for connection...');

    try {
      await _incomingConnectionCompleter!.future;
      debugPrint('[SWAP-$_role] Connection received');
    } catch (e) {
      debugPrint('[SWAP-$_role] Wait error: $e');
      rethrow;
    }
  }

  /// Exchange data and return received profile as String (JSON)
  Future<String?> exchangeData(String data) async {
    _localProfileData = Uint8List.fromList(utf8.encode(data));
    debugPrint('[SWAP-$_role] Waiting for exchange...');

    await waitForExchangeComplete(timeout: const Duration(seconds: 30));

    if (_receivedProfileData != null) {
      debugPrint(
        '[SWAP-$_role] Decoding ${_receivedProfileData!.length} bytes',
      );
      try {
        return utf8.decode(_receivedProfileData!);
      } catch (e) {
        debugPrint('[SWAP-$_role] UTF-8 error, using fallback');
        return String.fromCharCodes(_receivedProfileData!);
      }
    }
    debugPrint('[SWAP-$_role] No data received!');
    return null;
  }

  /// Wait for the data exchange to complete
  Future<void> waitForExchangeComplete({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_exchangeComplete && _receivedProfileData != null) return;

    _exchangeCompleter ??= Completer<void>();

    try {
      await _exchangeCompleter!.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('[SWAP-$_role] Exchange timeout');
    }
  }

  /// Mark exchange as complete
  void markExchangeComplete() {
    _exchangeComplete = true;
    if (_exchangeCompleter != null && !_exchangeCompleter!.isCompleted) {
      _exchangeCompleter!.complete();
    }
  }

  /// Cancel waiting for connection
  void cancelWaitForConnection() {
    if (_incomingConnectionCompleter != null &&
        !_incomingConnectionCompleter!.isCompleted) {
      _incomingConnectionCompleter!.completeError('Cancelled');
    }
    if (_exchangeCompleter != null && !_exchangeCompleter!.isCompleted) {
      _exchangeCompleter!.completeError('Cancelled');
    }
  }

  Future<void> _waitForDiscovery() async {
    try {
      await _discoveryCompleter!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _nearby.stopDiscovery();
          throw TimeoutException(
            "Discovery timed out. Please make sure the other device is displaying the QR code / Session Sharing Screen and is nearby.",
          );
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Stop advertising and all connections
  Future<void> stopAdvertising() async {
    try {
      if (_isAdvertising) {
        await _nearby.stopAdvertising();
        _isAdvertising = false;
      }
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (e) {
      debugPrint('[SWAP] Stop error: $e');
    }
  }

  void dispose() {
    _nearby.stopDiscovery();
    _nearby.stopAllEndpoints();
    _isAdvertising = false;
    _isJoiner = false;
  }
}
