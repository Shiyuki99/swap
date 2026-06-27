import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/platform_config.dart';

class UrlLauncherUtils {
  /// Opens a social profile URL.
  /// If profileLink is provided and valid, use it directly.
  /// Otherwise, construct URL from username.
  static Future<void> openSocialProfile(
    String platform,
    String username, {
    String? profileLink,
  }) async {
    String urlString;

    // If profile link is provided, validate and use it
    if (profileLink != null && profileLink.isNotEmpty) {
      if (!isValidUrlForPlatform(platform, profileLink)) {
        throw Exception('Security Block: Invalid link format for $platform');
      }
      urlString = profileLink;
    } else {
      urlString = _getSocialUrl(platform, username);
      if (urlString.isEmpty) return; // Nothing to open
    }

    final Uri url = Uri.parse(urlString);
    debugPrint('Opening social profile URL: $url');

    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  /// Check if the Open button should be enabled for a platform.
  /// Returns true if the platform can construct a URL from username,
  /// or if a profile link is provided for link-required platforms.
  static bool canOpen(String platform, String username, {String? profileLink}) {
    if (requiresOptionalLink(platform)) {
      return profileLink != null && profileLink.isNotEmpty;
    }
    return username.isNotEmpty;
  }

  static String _getSocialUrl(String platform, String username) {
    switch (platform) {
      case 'instagram':
        return 'https://instagram.com/$username';
      case 'twitter':
        return 'https://twitter.com/$username';
      case 'discord':
        // Discord can't construct URL from username alone
        return '';
      case 'tiktok':
        return 'https://tiktok.com/@$username';
      case 'snapchat':
        return 'https://snapchat.com/add/$username';
      case 'github':
        return 'https://github.com/$username';
      case 'email':
        return 'mailto:$username';
      case 'phone':
        return 'tel:$username';
      default:
        return '';
    }
  }

  /// Extract a username from a profile URL (inverse of _getSocialUrl).
  /// Returns the original string if no pattern matches.
  static String extractUsername(String platform, String url) {
    if (url.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      switch (platform) {
        case 'instagram':
        case 'twitter':
        case 'github':
          // Pattern: https://platform.com/{username}
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) return segments.first;
          break;
        case 'tiktok':
          // Pattern: https://tiktok.com/@{username}
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            final raw = segments.first;
            return raw.startsWith('@') ? raw.substring(1) : raw;
          }
          break;
        case 'snapchat':
          // Pattern: https://snapchat.com/add/{username}
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments.first == 'add') {
            return segments[1];
          }
          break;
        case 'email':
          // mailto:user@example.com
          if (url.startsWith('mailto:')) return url.substring(7);
          break;
        case 'phone':
          // tel:+1234567890
          if (url.startsWith('tel:')) return url.substring(4);
          break;
      }
    } catch (_) {
      // If parsing fails, return original
    }
    return url;
  }
}
