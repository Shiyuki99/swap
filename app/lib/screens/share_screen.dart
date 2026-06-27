import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../constants/colors.dart';
import '../constants/typography.dart';
import '../models/profile.dart';
import '../services/wifi_direct_service.dart';
import '../services/nfc_service.dart';
import '../services/storage_service.dart';
import '../services/swap_session_manager.dart';
import 'result_screen.dart';

class ShareScreen extends StatefulWidget {
  final int profileIndex;

  const ShareScreen({super.key, required this.profileIndex});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late SwapSessionManager _sessionManager;
  late WifiDirectService _wifiDirectService;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final StorageService _storageService = StorageService();

  bool _showCamera = false;
  String? _errorMessage;
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Initialize services
    _wifiDirectService = WifiDirectService();
    _sessionManager = SwapSessionManager(
      wifiDirectService: _wifiDirectService,
      nfcService: NFCService(),
    );

    _sessionManager.addListener(_onSessionStateChanged);

    // Load profile from storage first, then start swap
    _loadAndStartSwap();
  }

  Future<void> _loadAndStartSwap() async {
    debugPrint('LOADING PROFILE FROM STORAGE');
    debugPrint('Profile index: ${widget.profileIndex}');

    _profile = await _storageService.loadProfileToSocialRow(
      widget.profileIndex,
    );

    if (mounted) {
      setState(() {
        // _isLoadingProfile = false;
      });
    }

    // Start the swap session
    _startSwapSession();
  }

  /// Cleanup method to properly stop services before navigating away
  Future<void> _cleanup() async {
    // Stop the swap session
    _sessionManager.cancel();

    // Stop scanner
    _scannerController.stop();

    // Turn off services if we turned them on
    if (_wifiDirectService.didEnableBluetooth) {
      debugPrint(
        'Bluetooth was enabled by us - user may want to turn it off manually',
      );
    }
    // Note: Location service cannot be programmatically turned off on most devices
    // The user will need to turn it off manually if desired
    if (_wifiDirectService.didEnableLocation) {
      debugPrint(
        'Location was enabled by us - user may want to turn it off manually',
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _sessionManager.removeListener(_onSessionStateChanged);
    _sessionManager.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _startSwapSession() async {
    setState(() {
      _errorMessage = null;
    });

    // Check WiFi Direct and Location requirements first
    final requirements = await _wifiDirectService.checkRequirements();

    // Check if Bluetooth or Location services are off
    if (!requirements['bluetoothOn']! || !requirements['locationOn']!) {
      if (!mounted) return;

      final shouldRetry = await _wifiDirectService.promptEnableServices();

      if (shouldRetry == true) {
        // Retry starting the session
        _startSwapSession();
        return;
      } else {
        // User cancelled
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
    }

    if (!requirements['permissionsGranted']!) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Bluetooth and Location permissions are required for swapping';
        });
      }
      return;
    }

    try {
      if (_profile == null) {
        setState(() {
          _errorMessage = 'Profile not loaded. Please go back and try again.';
        });
        return;
      }

      final receivedProfile = await _sessionManager.startSwap(_profile!);

      if (receivedProfile != null && mounted) {
        // Navigate to ResultScreen with received profile data
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              receivedProfile: receivedProfile,
              wifiDirectService: _wifiDirectService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onSessionStateChanged() {
    if (mounted) {
      setState(() {});

      // Navigate to ResultScreen when swap is complete
      if (_sessionManager.state == SwapState.complete &&
          _sessionManager.receivedProfile != null) {
        // Stop scanner before navigating
        _scannerController.stop();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              receivedProfile: _sessionManager.receivedProfile!,
              wifiDirectService: _wifiDirectService,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        // Cleanup is called when pop is invoked (whether it completes or not)
        await _cleanup();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Header with close icon - no horizontal padding, at screen edge
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsetsGeometry.symmetric(vertical: 2),
                  margin: EdgeInsetsGeometry.symmetric(horizontal: 10),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text('SHARING PROFILE', style: AppTypography.header),
                      // Top Right Button
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Icon(
                            Icons.close,
                            color: AppColors.mainText,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Subheader outside the Stack for proper icon centering
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  child: Text(
                    _profile?.profileName ?? 'Loading...',
                    style: AppTypography.subHeader,
                  ),
                ),
              ),

              if (_sessionManager.state != SwapState.idle) ...[
                Text(
                  _getStatusText(),
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],

              // Content with horizontal padding
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(),

                      // QR Code / Camera with NFC animation
                      GestureDetector(
                        onTap: _onQRTap,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // QR Code or Camera Container
                            Container(
                              width: screenWidth * 0.65,
                              height: screenWidth * 0.65,
                              clipBehavior: Clip.hardEdge,
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 255, 255, 255),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: _showCamera
                                  ? _buildCameraScanner()
                                  : _buildQRDisplay(),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Error message
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: AppTypography.body.copyWith(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // NFC Instructions with status indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Please touch phones back-to-back',
                            style: AppTypography.body.copyWith(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _sessionManager.isNfcActive
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: _sessionManager.isNfcActive
                                ? Colors.green
                                : Colors.red,
                            size: 18,
                          ),
                        ],
                      ),
                      Text(
                        'For NFC Share',
                        style: AppTypography.body.copyWith(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'OR',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan QR Code',
                        style: AppTypography.body.copyWith(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(Tap the QR to switch to camera mode)',
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQRDisplay() {
    final sessionURL = _sessionManager.sessionURL;

    if (sessionURL == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: PrettyQrView.data(
        data: sessionURL,
        errorCorrectLevel: QrErrorCorrectLevel.H,
        decoration: const PrettyQrDecoration(
          shape: PrettyQrSmoothSymbol(),
          image: PrettyQrDecorationImage(
            scale: 0.3,
            padding: EdgeInsets.all(8),
            position: PrettyQrDecorationImagePosition.embedded,
            image: AssetImage('assets/icons/app-icon.png'),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraScanner() {
    return MobileScanner(
      controller: _scannerController,
      onDetect: _onQRCodeDetected,
    );
  }

  String _getStatusText() {
    final webAvailable = _sessionManager.webAvailable;
    final webStatus = webAvailable == null
        ? ''
        : webAvailable
        ? ' (webview available)'
        : ' (webview unavailable)';
    switch (_sessionManager.state) {
      case SwapState.idle:
        return '';
      case SwapState.advertising:
        return 'Waiting for connection...$webStatus';
      case SwapState.connecting:
        return 'Connecting...';
      case SwapState.exchanging:
        return 'Exchanging profiles...';
      case SwapState.complete:
        return 'Swap complete!';
      case SwapState.error:
        return 'Error occurred';
    }
  }

  void _onQRCodeDetected(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null) return;

    debugPrint('QR Code detected: $code');

    // Prevent multiple scans
    if (_sessionManager.state == SwapState.connecting ||
        _sessionManager.state == SwapState.exchanging) {
      return;
    }

    // Stop camera and show connecting state
    _scannerController.stop();
    setState(() {
      _showCamera = false;
    });

    try {
      // Join the scanned session
      final receivedProfile = await _sessionManager.joinSwap(code, _profile!);

      if (receivedProfile != null && mounted) {
        // Navigate to ResultScreen with received profile
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              receivedProfile: receivedProfile,
              wifiDirectService: _wifiDirectService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect: ${e.toString()}';
        });
        // Restart camera for retry
        _scannerController.start();
      }
    }
  }

  void _onQRTap() {
    setState(() {
      _showCamera = !_showCamera;
    });
  }
}
