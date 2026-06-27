import 'package:swap/constants/platform_config.dart';
import 'package:swap/constants/typography.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SocialIconRow extends StatelessWidget {
  /// Map of platform -> is selected (has data)
  final Map<String, bool> selectedSocials;

  /// Map of platform -> username/value (used to determine if has data)
  final Map<String, String>? socialData;

  final Function(String) onSocialTap;
  final bool isEditable;

  const SocialIconRow({
    super.key,
    required this.selectedSocials,
    required this.onSocialTap,
    this.socialData,
    this.isEditable = true,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate icon size
    final screenWidth =
        MediaQuery.of(context).size.width - 48; // Account for padding
    final iconSize =
        ((screenWidth - (4 * 12)) / 5) * 0.8; // 5 icons, 4 gaps of 12px

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Use centralized platform lists from platform_config
        _buildSection('Socials', socialPlatforms, iconSize),
        const SizedBox(height: 16),
        _buildSection('Contact', contactPlatforms, iconSize),
      ],
    );
  }

  Widget _buildSection(String title, List<String> platforms, double iconSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: AppTypography.body.copyWith(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: platforms.map((platform) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: _buildSocialIcon(platform, iconSize),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSocialIcon(String platform, double iconSize) {
    // Check if this platform has data (username is not null or empty)
    final hasData = _hasData(platform);
    // Selected state is based on selectedSocials map (set when tapped)
    final isSelected = _isSelected(platform);
    final svgPath = _getSvgPath(platform);

    // Opacity: 100% if selected (being edited) OR has data, otherwise 60%
    final opacity = (isSelected || hasData) ? 1.0 : 0.6;

    // Determine which badge to show
    final bool needsAttention = _needsAttentionBadge(platform);

    return GestureDetector(
      // In non-editable mode, only allow tap if platform has data
      onTap: (isEditable || hasData) ? () => onSocialTap(platform) : null,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SvgPicture.asset(
                svgPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
              if (hasData && needsAttention)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: SvgPicture.asset(
                    'assets/icons/ui/attention.svg',
                    width: 18,
                    height: 18,
                  ),
                )
              else if (hasData)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.checkmarkGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Check if platform has data (non-empty username OR link)
  bool _hasData(String platform) {
    if (socialData == null) {
      // Fallback to selectedSocials if no socialData provided
      return selectedSocials[platform] ?? false;
    }
    final value = socialData![platform];
    final linkKey = getLinkKey(platform);
    final link = socialData![linkKey];
    return (value != null && value.isNotEmpty) ||
        (link != null && link.isNotEmpty);
  }

  /// Check if this platform needs the attention badge instead of check.
  /// A platform needs attention when:
  /// 1. It requires a link (from platform_config)
  /// 2. It has a username but NO link provided
  /// If only the link is provided (no username), show the green check.
  bool _needsAttentionBadge(String platform) {
    if (!_hasData(platform)) return false;
    if (!requiresOptionalLink(platform)) return false;

    // Check if link is provided in socialData
    if (socialData == null) return true; // No data map, assume needs attention
    final linkKey = getLinkKey(platform);
    final link = socialData![linkKey];
    final hasLink = link != null && link.isNotEmpty;
    return !hasLink; // Only needs attention if link is missing
  }

  bool _isSelected(String platform) {
    return selectedSocials[platform] ?? false;
  }

  String _getSvgPath(String platform) {
    switch (platform) {
      case 'twitter':
        return 'assets/icons/scocial/twitter-x.svg';
      case 'instagram':
        return 'assets/icons/scocial/instagram.svg';
      case 'discord':
        return 'assets/icons/scocial/discord.svg';
      case 'tiktok':
        return 'assets/icons/scocial/tiktok.svg';
      case 'snapchat':
        return 'assets/icons/scocial/snapchat.svg';
      case 'github':
        return 'assets/icons/scocial/github.svg';
      case 'email':
        return 'assets/icons/scocial/email.svg';
      case 'phone':
        return 'assets/icons/scocial/phone.svg';
      default:
        return 'assets/icons/SWAP-LOGO.svg';
    }
  }
}
