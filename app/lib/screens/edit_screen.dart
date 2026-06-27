import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';
import '../constants/platform_config.dart';
import '../services/storage_service.dart';
import '../services/guide_tour_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/social_icon_row.dart';
import '../widgets/profile_tab_switcher.dart';

class EditScreen extends StatefulWidget {
  final int initialProfileIndex;

  const EditScreen({super.key, this.initialProfileIndex = 0});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late int _activeProfile;
  final TextEditingController _profileNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // Store username values for each social
  final Map<String, TextEditingController> _socialUsernames = {};
  // Store optional profile links for platforms that require them
  final Map<String, TextEditingController> _socialLinks = {};

  final Map<String, bool> _selectedSocials = {
    'instagram': false,
    'twitter': false,
    'snapchat': false,
    'discord': false,
    'tiktok': false,
    'github': false,
    'email': false,
    'phone': false,
  };

  String? _currentlyEditingSocial;
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.initialProfileIndex;
    _initializeControllers();
    _loadProfileData();
  }

  void _initializeControllers() {
    for (var key in _selectedSocials.keys) {
      _socialUsernames[key] = TextEditingController();
      // Create link controller for ALL platforms (optional link support)
      _socialLinks[key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _nameController.dispose();
    for (final c in _socialUsernames.values) {
      c.dispose();
    }
    for (final c in _socialLinks.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0.0, 24.0, 0.0, 16.0),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: EdgeInsetsGeometry.symmetric(vertical: 2),
                        margin: EdgeInsetsGeometry.symmetric(horizontal: 10),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text('EDIT PROFILE', style: AppTypography.header),
                            // Top Right Button
                            Positioned(
                              right: 0,
                              child: GestureDetector(
                                child: Icon(
                                  Icons.close,
                                  color: AppColors.mainText,
                                  size: 26,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Profile tab switcher
                      ProfileTabSwitcher(
                        key: GuideTourService.editProfileTabKey,
                        activeProfile: _activeProfile,
                        onProfileChanged: _onProfileChanged,
                      ),

                      const SizedBox(height: 32),

                      // Profile name input
                      Column(
                        key: GuideTourService.editNameFieldsKey,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: CustomTextField(
                              hintText: 'Profile Name',
                              controller: _profileNameController,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: CustomTextField(
                              hintText: 'Name',
                              controller: _nameController,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Social icons
                      SocialIconRow(
                        key: GuideTourService.editSocialIconsKey,
                        selectedSocials: _selectedSocials,
                        socialData: _getSocialDataMap(),
                        onSocialTap: _onSocialTap,
                      ),

                      const SizedBox(height: 24),

                      // Dynamic inputs based on which icon is being edited
                      if (_currentlyEditingSocial != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: CustomTextField(
                            hintText: getPlaceholderFor(
                              _currentlyEditingSocial!,
                            ),
                            controller:
                                _socialUsernames[_currentlyEditingSocial],
                            onChanged: (_) => setState(
                              () {},
                            ), // Refresh to update icon selection
                          ),
                        ),

                        // Show optional link field ONLY for non-contact platforms
                        if (!contactPlatforms.contains(
                          _currentlyEditingSocial,
                        )) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: CustomTextField(
                              hintText: getLinkPlaceholder(
                                _currentlyEditingSocial!,
                              ),
                              controller: _socialLinks[_currentlyEditingSocial],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Text(
                              getLinkHelpText(_currentlyEditingSocial!),
                              style: AppTypography.body.copyWith(
                                fontSize: 12,
                                color: AppColors.secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ] else ...[
                        Text(
                          'Tap an icon to add your social info',
                          style: AppTypography.body.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Save button - fixed at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
              child: CustomButton(
                key: GuideTourService.editSaveButtonKey,
                width: 150,
                text: 'SAVE',
                icon: Icons.check,
                onPressed: _onSavePressed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onProfileChanged(int index) {
    setState(() {
      _activeProfile = index;
    });
    _loadProfileData();
  }

  void _onSocialTap(String platform) {
    setState(() {
      // Clear previous selection
      _selectedSocials.updateAll((key, value) => false);
      // Set this platform as selected (being edited)
      _selectedSocials[platform] = true;
      _currentlyEditingSocial = platform;
    });
  }

  /// Build a map of platform -> username for SocialIconRow
  /// Also includes _link keys so the attention badge can determine if a link is present
  Map<String, String> _getSocialDataMap() {
    final dataMap = <String, String>{};
    for (var key in _socialUsernames.keys) {
      dataMap[key] = _socialUsernames[key]?.text ?? '';
    }
    // Include link values for attention badge logic
    for (var key in _socialLinks.keys) {
      final linkKey = getLinkKey(key);
      dataMap[linkKey] = _socialLinks[key]?.text ?? '';
    }
    return dataMap;
  }

  Future<void> _loadProfileData() async {
    setState(() {});

    try {
      final profileData = await _storageService.getProfile(_activeProfile);

      if (profileData != null) {
        _profileNameController.text = profileData['profileName'] ?? '';
        _nameController.text = profileData['name'] ?? '';

        // Load social links
        final socialLinks = profileData['socialLinks'] as Map<String, dynamic>?;
        if (socialLinks != null) {
          for (var key in _socialUsernames.keys) {
            _socialUsernames[key]?.text = socialLinks[key]?.toString() ?? '';
          }
          // Load links for all platforms
          for (var key in _socialLinks.keys) {
            final linkKey = getLinkKey(key);
            _socialLinks[key]?.text = socialLinks[linkKey]?.toString() ?? '';
          }
        }
      } else {
        // Default values for new profile
        _profileNameController.text = _activeProfile == 0
            ? 'Profile 1'
            : 'Profile 2';
        _nameController.text = '';
        for (var controller in _socialUsernames.values) {
          controller.text = '';
        }
        for (var controller in _socialLinks.values) {
          controller.text = '';
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _currentlyEditingSocial = null;
        });
      }
    }
  }

  Future<void> _onSavePressed() async {
    // Build social links map with whitespace handling
    final socialLinks = <String, String>{};
    for (var key in _socialUsernames.keys) {
      // Remove all whitespace from usernames
      final username =
          _socialUsernames[key]?.text.replaceAll(RegExp(r'\s+'), '') ?? '';

      if (username.isNotEmpty) {
        if (key == 'email') {
          // Validate email format
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(username)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter a valid email address.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } else if (key == 'phone') {
          // Validate phone format (optional leading + and numbers)
          if (!RegExp(r'^\+?[0-9]+$').hasMatch(username)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please enter a valid phone number (digits only).',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }
      }

      socialLinks[key] = username;
    }
    // Add profile links for all platforms (when provided)
    for (var key in _socialLinks.keys) {
      String link =
          _socialLinks[key]?.text.replaceAll(RegExp(r'\s+'), '') ?? '';

      // Remove any tracking query parameters (e.g. ?igshid=...)
      if (link.contains('?')) {
        link = link.split('?').first;
      }

      if (link.isNotEmpty) {
        // Validate the link format
        if (!isValidUrlForPlatform(key, link)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Invalid link for ${key.toUpperCase()}. Ensure it is a valid platform link.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return; // Abort save step
        }
        socialLinks[getLinkKey(key)] = link;
      }
    }

    // Build profile data with trimmed name fields
    final profileData = {
      'profileName': _profileNameController.text.trim(),
      'name': _nameController.text.trim(),
      'socialLinks': socialLinks,
    };

    try {
      await _storageService.saveProfile(_activeProfile, profileData);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    }
  }
}
