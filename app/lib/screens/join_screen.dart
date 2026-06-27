import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/nfc_service.dart';

import '../constants/colors.dart';
import '../constants/typography.dart';
import '../models/profile.dart';
import '../services/storage_service.dart';
import '../services/swap_session_manager.dart';
import '../services/wifi_direct_service.dart';
import 'result_screen.dart';

class JoinScreen extends StatefulWidget {
  final int profileIndex;
  final String deepLinkUrl;

  const JoinScreen({
    super.key,
    required this.profileIndex,
    required this.deepLinkUrl,
  });

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late SwapSessionManager _sessionManager;
  late WifiDirectService _wifiDirectService;
  final StorageService _storageService = StorageService();

  Profile? _profile;
  String? _errorMessage;
  bool _isSelectingMethod = true;

  @override
  void initState() {
    super.initState();

    _wifiDirectService = WifiDirectService();
    _sessionManager = SwapSessionManager(
      wifiDirectService: _wifiDirectService,
      nfcService:
          NFCService(), // NFC only needed for broadcasting, but required parameter
    );

    _sessionManager.addListener(_onSessionStateChanged);

    _loadProfile();
  }

  Future<void> _loadProfile() async {
    _profile = await _storageService.loadProfileToSocialRow(
      widget.profileIndex,
    );

    if (_profile == null && mounted) {
      setState(() {
        _errorMessage = "Profile not loaded.";
      });
    }
  }

  Future<void> _startNearbySwap() async {
    setState(() {
      _errorMessage = null;
    });

    if (_profile == null) {
      setState(() => _errorMessage = "Profile not loaded.");
      return;
    }

    final requirements = await _wifiDirectService.checkRequirements();

    // Check if Bluetooth or Location services are off
    if (!requirements['bluetoothOn']! || !requirements['locationOn']!) {
      if (!mounted) return;

      final shouldRetry = await _wifiDirectService.promptEnableServices();

      if (shouldRetry == true) {
        // Retry connection
        if (mounted) {
          _startNearbySwap();
        }
        return;
      } else {
        // User cancelled, remain on selection screen
        if (mounted) {
          setState(() {
            _isSelectingMethod = true;
            _errorMessage = 'Bluetooth and Location must be enabled.';
          });
        }
        return;
      }
    }

    if (!requirements['permissionsGranted']!) {
      if (mounted) {
        setState(() {
          _errorMessage = "Permissions required for Nearby Connection.";
          _isSelectingMethod = true;
        });
      }
      return;
    }

    // Requirements met, proceed to UI loading state
    setState(() {
      _isSelectingMethod = false;
    });

    try {
      final receivedProfile = await _sessionManager.joinSwap(
        widget.deepLinkUrl,
        _profile!,
      );
      if (receivedProfile != null && mounted) {
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
          _errorMessage = "Connection Failed: ${e.toString()}";
          _isSelectingMethod = true;
        });
      }
    }
  }

  Future<void> _startWebSwap() async {
    setState(() {
      _isSelectingMethod = false;
      _errorMessage = null;
    });

    if (_profile == null) {
      setState(() => _errorMessage = "Profile not loaded.");
      return;
    }

    try {
      final uri = Uri.parse(widget.deepLinkUrl);
      if (uri.path.startsWith('/view/')) {
        final sessionId = uri.pathSegments.last;
        final sig = uri.queryParameters['sig'];

        if (sessionId.isNotEmpty && sig != null) {
          final apiUrl = uri.replace(
            path: '/api/session/$sessionId',
            queryParameters: {'sig': sig},
          );

          final response = await http
              .get(apiUrl)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['profile'] != null) {
              final fetchedProfile = Profile.fromJson(data['profile']);
              if (mounted) {
                await Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResultScreen(
                      receivedProfile: fetchedProfile,
                      wifiDirectService: _wifiDirectService,
                    ),
                  ),
                );
                return;
              }
            }
          }
        }
      }
      throw Exception("Invalid web link or server error");
    } catch (httpError) {
      debugPrint('HTTP Fallback failed: $httpError');
      if (mounted) {
        setState(() {
          _errorMessage = "Web Connection Failed: ${httpError.toString()}";
          _isSelectingMethod = true;
        });
      }
    }
  }

  void _onSessionStateChanged() {
    if (!mounted) return;
    setState(() {});

    // Fallback navigation check if state magically completed
    if (_sessionManager.state == SwapState.complete &&
        _sessionManager.receivedProfile != null) {
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

  /// Cleanup method to properly stop services before navigating away
  Future<void> _cleanup() async {
    // Stop the swap session
    _sessionManager.cancel();
  }

  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionStateChanged);
    _sessionManager.cancel();
    _sessionManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        await _cleanup();
      },
      child: Scaffold(
        backgroundColor: AppColors.mainBg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text('JOINING SESSION', style: AppTypography.header),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
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
              const Spacer(),
              if (_isSelectingMethod)
                Expanded(flex: 4, child: _buildSelectionView())
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        style: AppTypography.body.copyWith(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.buttonBg,
                          foregroundColor: AppColors.mainText,
                        ),
                        onPressed: () =>
                            setState(() => _isSelectingMethod = true),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.openBg),
                    const SizedBox(height: 24),
                    Text(
                      _getJoinStatusText(),
                      style: AppTypography.body.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_calls, size: 60, color: AppColors.openBg),
          const SizedBox(height: 20),
          Text(
            'Connection Method',
            style: AppTypography.header,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'How are you connecting?',
            style: AppTypography.body.copyWith(
              fontSize: 15,
              color: AppColors.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: AppTypography.body.copyWith(
                color: AppColors.deleteBg,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          _buildMethodButton(
            icon: Icons.wifi,
            title: 'Nearby',
            subtitle: 'Uses Wi-Fi & Bluetooth directly.',
            onTap: _startNearbySwap,
          ),
          const SizedBox(height: 16),
          _buildMethodButton(
            icon: Icons.language,
            title: 'Via Web',
            subtitle: 'Uses the internet for remote swaps.',
            onTap: _startWebSwap,
          ),
        ],
      ),
    );
  }

  Widget _buildMethodButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mainBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.openBg, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.subHeader),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.body.copyWith(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }

  String _getJoinStatusText() {
    switch (_sessionManager.state) {
      case SwapState.idle:
        return 'Initializing...';
      case SwapState.connecting:
        return 'Discovering session...\nKeep phones near each other.';
      case SwapState.exchanging:
        return 'Exchanging profiles...';
      case SwapState.complete:
        return 'Swap complete!';
      case SwapState.error:
        return 'Connection error.';
      default:
        return 'Connecting...';
    }
  }
}
