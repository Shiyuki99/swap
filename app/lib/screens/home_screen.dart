import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../constants/typography.dart';
import '../constants/platform_config.dart';
import '../models/profile.dart';
import '../services/guide_tour_service.dart';
import '../services/storage_service.dart';
import '../services/theme_provider.dart';
import '../widgets/custom_button.dart';
import 'edit_screen.dart';
import 'history_screen.dart';
import 'join_screen.dart';
import 'share_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentProfileName = 'PROFILE 1';
  int _currentProfileIndex = 0;
  final StorageService _storageService = StorageService();
  String? _lastProcessedLink;
  Timer? _timer;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  // GlobalKeys for guide tour spotlight
  final _swapButtonKey = GlobalKey();
  final _editButtonKey = GlobalKey();
  final _historyIconKey = GlobalKey();
  final _settingsIconKey = GlobalKey();

  // Profiles loaded from storage
  List<Profile> _profiles = [];

  Profile? get _currentProfile =>
      _profiles.isNotEmpty ? _profiles[_currentProfileIndex] : null;

  @override
  void initState() {
    super.initState();
    _loadProfiles().then((_) {
      _checkGuideTour();
      _initDeepLinks();
      _checkForUpdates();
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle incoming links when app is in background or terminated
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Failed to get initial uri: $e');
    }

    // Handle incoming links when app is running in foreground
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep link stream error: $err');
      },
    );
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received deep link: $uri');
    // Ensure we are mounted and have a valid profile before proceeding
    if (!mounted ||
        _currentProfile == null ||
        !_currentProfile!.isValidForSwap) {
      debugPrint('Deep link neglected: profile invalid or not loaded');
      return;
    }

    // Expected format: swapapp.ddns.net/view/{sessionId}?sig={secret}
    final pathSegments = uri.pathSegments;
    int viewIndex = pathSegments.indexOf('view');

    if (viewIndex != -1 && viewIndex + 1 < pathSegments.length) {
      final sessionId = pathSegments[viewIndex + 1];
      final secret = uri.queryParameters['sig'];

      if (sessionId.isNotEmpty && secret != null && secret.isNotEmpty) {
        final linkStr = uri.toString();
        if (_lastProcessedLink == linkStr) {
          debugPrint('Deep link already processed: $linkStr');
          return;
        }
        _lastProcessedLink = linkStr;
        debugPrint('Deep link processed. Session: $sessionId, Secret: $secret');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => JoinScreen(
              profileIndex: _currentProfileIndex,
              deepLinkUrl: linkStr,
            ),
          ),
        ).then((_) {
          // Allow joining it again if they exit
          _lastProcessedLink = null;
        });
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      // We also track build numbers, so format as X.Y.Z+B
      final fullVersion = '$currentVersion+${packageInfo.buildNumber}';

      final encodedVersion = Uri.encodeComponent(fullVersion);
      final uri = Uri.parse(
        '$swapBaseUrl/api/check-update?version=$encodedVersion',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool updateAvailable = data['updateAvailable'] ?? false;
        final String latestVersion = data['latestVersion'] ?? 'Unknown';

        if (updateAvailable && mounted) {
          _showUpdateDialog(latestVersion);
        }
      }
    } catch (e) {
      debugPrint('Failed to check for updates: $e');
    }
  }

  void _showUpdateDialog(String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'A new version of SWAP ($latestVersion) is available. Please update to continue getting the best experience.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('LATER'),
          ),
          TextButton(
            // Since we're not on the app store yet, send them to the web server index or github
            onPressed: () async {
              Navigator.pop(context);
              final url = Uri.parse(swapBaseUrl);
              try {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('Failed to open update URL: $e');
              }
            },
            child: const Text('UPDATE NOW'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkGuideTour() async {
    if (await GuideTourService.shouldShowTour() && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          GuideTourService.startTour(
            context,
            swapButtonKey: _swapButtonKey,
            editButtonKey: _editButtonKey,
            historyIconKey: _historyIconKey,
            settingsIconKey: _settingsIconKey,
          );
        }
      });
    }
  }

  Future<void> _loadProfiles() async {
    debugPrint('_loadProfiles() CALLED');

    try {
      final loadedProfiles = <Profile>[];

      // Load all profiles from storage
      for (int i = 0; i < profilesNumber; i++) {
        Profile profile = await _storageService.loadProfileToSocialRow(i);
        loadedProfiles.add(profile);
      }

      if (mounted) {
        setState(() {
          _profiles = loadedProfiles;
          _currentProfileName =
              _currentProfile?.profileName.toUpperCase() ?? 'PROFILE 1';
        });
      }

      debugPrint('LOADED PROFILES');
      for (final p in _profiles) {
        debugPrint('Profile: ${p.profileName}, Name: ${p.name}');
        debugPrint('Social links: ${p.socialLinks}');
      }
    } catch (e, stackTrace) {
      debugPrint('ERROR IN _loadProfiles()');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showSettingsPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.mainBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.secondaryText.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'SETTINGS',
                      style: AppTypography.header.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 24),
                    // Dark mode toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              themeProvider.isDarkMode
                                  ? Icons.dark_mode
                                  : Icons.light_mode,
                              color: AppColors.mainText,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Text('Dark Mode', style: AppTypography.body),
                          ],
                        ),
                        Switch(
                          value: themeProvider.isDarkMode,
                          onChanged: (_) => themeProvider.toggleDarkMode(),
                          activeThumbColor: const Color(0xFF806CF1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final buttonSize = screenWidth * 0.65;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Header with settings icon (left) and history icon (right)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsetsGeometry.symmetric(vertical: 2),
                          margin: EdgeInsetsGeometry.symmetric(horizontal: 10),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                'ACTIVE PROFILE',
                                style: AppTypography.header,
                              ),
                              // Top Left - Settings
                              Positioned(
                                left: 0,
                                child: GestureDetector(
                                  onTap: _showSettingsPopup,
                                  child: SvgPicture.asset(
                                    'assets/icons/ui/settings.svg',
                                    key: _settingsIconKey,
                                    width: 26,
                                    height: 26,
                                    colorFilter: ColorFilter.mode(
                                      AppColors.mainText,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                              // Top Right - History
                              Positioned(
                                right: 0,
                                child: GestureDetector(
                                  onTap: _onHistoryPressed,
                                  child: Icon(
                                    key: _historyIconKey,
                                    Icons.history,
                                    color: AppColors.mainText,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Subheader outside the Stack for proper icon centering
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GestureDetector(
                            onHorizontalDragEnd: _onSwipe,
                            child: Text(
                              _currentProfileName,
                              style: AppTypography.subHeader,
                            ),
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.15),

                        // Large swap button - rectangular with gradient
                        GestureDetector(
                          onTap: _onCirclePressed,
                          onTapDown: (_) {
                            _timer = Timer(Duration(milliseconds: 10000), () {
                              launchUrl(
                                Uri.parse(
                                  'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
                                ),
                              );
                            });
                          },
                          onTapUp: (_) => _timer?.cancel(),
                          onTapCancel: () => _timer?.cancel(),
                          onHorizontalDragEnd: _onSwipe,
                          child: Container(
                            key: _swapButtonKey,
                            width: buttonSize,
                            height: buttonSize,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0xFF1CB1D3), // Bottom - cyan
                                  Color(0xFF792EA4), // Top - purple
                                ],
                              ),
                              borderRadius: BorderRadius.circular(120),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF792EA4,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/swap_logo.svg',
                                width: buttonSize * 1,
                                height: buttonSize * 1,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Instructions
                        Text(
                          'Press To Start Profile swapping',
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'Slide to switch to Another Profile',
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),

                        const Spacer(),

                        // Edit button
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
              child: CustomButton(
                key: _editButtonKey,
                width: 150,
                text: 'EDIT',
                icon: Icons.edit,
                onPressed: _onEditPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSwipe(DragEndDetails details) {
    if (details.primaryVelocity == null || _profiles.isEmpty) return;

    // Require a deliberate swipe — ignore slow/accidental drags
    if (details.primaryVelocity!.abs() < 500) return;

    setState(() {
      if (details.primaryVelocity! < 0) {
        // Swipe left - next profile
        _currentProfileIndex = (_currentProfileIndex + 1) % _profiles.length;
      } else {
        // Swipe right - previous profile
        _currentProfileIndex =
            (_currentProfileIndex - 1 + _profiles.length) % _profiles.length;
      }
      _currentProfileName =
          _currentProfile?.profileName.toUpperCase() ?? 'PROFILE';
    });
  }

  void _onCirclePressed() async {
    final profile = _currentProfile;
    if (profile == null || !profile.isValidForSwap) {
      // Profile is empty — redirect to edit
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile is empty — please fill in your info first'),
          ),
        );
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EditScreen(initialProfileIndex: _currentProfileIndex),
        ),
      );
      // Reload and check if now valid
      await _loadProfiles();
      if (_currentProfile != null &&
          _currentProfile!.isValidForSwap &&
          mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ShareScreen(profileIndex: _currentProfileIndex),
          ),
        );
      }
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareScreen(profileIndex: _currentProfileIndex),
      ),
    );
  }

  void _onHistoryPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryListScreen()),
    );
  }

  void _onEditPressed() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditScreen()),
    );
    // Reload profiles after returning from edit screen
    _loadProfiles();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
