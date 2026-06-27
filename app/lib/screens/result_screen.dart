import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/guide_tour_service.dart';
import '../utils/url_launcher_utils.dart';
import '../constants/colors.dart';
import '../constants/platform_config.dart';
import '../constants/typography.dart';
import '../models/profile.dart';
import '../models/swap_history.dart';
import '../services/storage_service.dart';
import '../services/wifi_direct_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/social_icon_row.dart';

class ResultScreen extends StatefulWidget {
  final Profile receivedProfile;
  final WifiDirectService? wifiDirectService;

  const ResultScreen({
    super.key,
    required this.receivedProfile,
    this.wifiDirectService,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final TextEditingController _noteController = TextEditingController();
  late TextEditingController _usernameController;

  // Track which socials were swapped based on received profile
  late Map<String, bool> _swappedSocials;
  String? _selectedPlatform;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();

    // Start disconnect in background - don't wait for it
    if (widget.wifiDirectService != null) {
      debugPrint('[SWAPPED] Starting background disconnect...');
      widget.wifiDirectService!.stopAdvertising();
    }

    // Build swapped socials map using platform config's canonical list
    _swappedSocials = {};
    for (final platform in allPlatforms) {
      final username = widget.receivedProfile.socialLinks[platform] ?? '';
      final link =
          widget.receivedProfile.socialLinks[getLinkKey(platform)] ?? '';
      if (username.isNotEmpty || link.isNotEmpty) {
        _swappedSocials[platform] = true;
      }
    }

    // Select first available platform by default
    if (_swappedSocials.isNotEmpty) {
      _selectedPlatform = _swappedSocials.keys.first;
      _updateUsernameDisplay();
    }
  }

  void _updateUsernameDisplay() {
    if (_selectedPlatform != null) {
      final username =
          widget.receivedProfile.socialLinks[_selectedPlatform] ?? '';
      if (username.isNotEmpty) {
        _usernameController.text = username;
      } else {
        // Fall back to the _link value, extracting the username from the URL
        final linkKey = '${_selectedPlatform}_link';
        final link = widget.receivedProfile.socialLinks[linkKey] ?? '';
        _usernameController.text = link.isNotEmpty
            ? UrlLauncherUtils.extractUsername(_selectedPlatform!, link)
            : '';
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveHistory();
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // Header
                          Container(
                            width: double.infinity,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('SWAPPED', style: AppTypography.header),
                                const SizedBox(height: 4),
                                Text(
                                  widget.receivedProfile.name.toUpperCase(),
                                  style: AppTypography.subHeader.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Swapped links label
                          Text(
                            'SWAPPED LINKS:',
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Social icons
                          SocialIconRow(
                            selectedSocials: _swappedSocials,
                            socialData: widget.receivedProfile.socialLinks,
                            onSocialTap: (platform) {
                              if (_swappedSocials.containsKey(platform)) {
                                setState(() {
                                  _selectedPlatform = platform;
                                  _updateUsernameDisplay();
                                });
                              }
                            },
                            isEditable: false,
                          ),

                          const SizedBox(height: 24),

                          // Username/Link Input + Open Button Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                Expanded(
                                  child: CustomTextField(
                                    hintText: '@Username',
                                    controller: _usernameController,
                                    isReadOnly: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                CustomButton(
                                  key: GuideTourService.resultOpenButtonKey,
                                  width: 100,
                                  text: 'OPEN',
                                  icon: Icons.link,
                                  backgroundColor: AppColors.openBg,
                                  onPressed:
                                      _selectedPlatform != null &&
                                          _usernameController.text.isNotEmpty
                                      ? _onOpenPressed
                                      : null,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Note input
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: CustomTextField(
                              hintText: 'Add a note...',
                              controller: _noteController,
                              maxLines: 5,
                              maxLength: 100,
                            ),
                          ),

                          const Spacer(),

                          // Done button
                          CustomButton(
                            width: 150,
                            text: 'DONE',
                            icon: Icons.check,
                            onPressed: _onDonePressed,
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _onOpenPressed() {
    // Get profile link for platforms that require it
    final linkKey = '${_selectedPlatform}_link';
    final profileLink = widget.receivedProfile.socialLinks[linkKey];

    UrlLauncherUtils.openSocialProfile(
      _selectedPlatform!,
      _usernameController.text,
      profileLink: profileLink,
    );
  }

  Future<void> _saveHistory() async {
    // Save swap to history with the note
    final history = SwapHistory(
      id: const Uuid().v4(),
      username: widget.receivedProfile.name,
      note: _noteController.text.trim(),
      timestamp: DateTime.now(),
      swappedLinks: widget.receivedProfile.socialLinks,
    );

    await StorageService().saveSwapHistory(history);
  }

  Future<void> _onDonePressed() async {
    await _saveHistory();

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
