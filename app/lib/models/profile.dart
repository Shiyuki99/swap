import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../constants/platform_config.dart';
import '../utils/url_launcher_utils.dart';

class Profile {
  String id;
  String profileName;
  String name;
  Map<String, String> socialLinks; // 'instagram': 'username'
  Profile({
    required this.id,
    required this.profileName,
    required this.name,
    required this.socialLinks,
  });

  /// Encode profile to Uint8List for transmission via Nearby Connections
  Uint8List toBytes() {
    final jsonString = jsonEncode(toJson());
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  /// Decode profile from Uint8List received via Nearby Connections
  static Profile fromBytes(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return Profile.fromJson(json);
  }

  Map<String, dynamic> toJson() {
    final links = <String, dynamic>{};
    for (final platform in allPlatforms) {
      var username = socialLinks[platform] ?? '';
      final linkKey = getLinkKey(platform);
      final link = socialLinks[linkKey];

      // If no username but a link exists, extract the username from it
      if (username.isEmpty && link != null && link.isNotEmpty) {
        username = UrlLauncherUtils.extractUsername(platform, link);
      }

      links[platform] = username;
      if (link != null && link.isNotEmpty) {
        links[linkKey] = link;
      }
    }
    return {"id": id, "name": name, "socialLinks": links};
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    // Handle null values gracefully
    final rawSocialLinks = json["socialLinks"] as Map<String, dynamic>?;
    final socialLinks = <String, String>{};

    if (rawSocialLinks != null) {
      for (final entry in rawSocialLinks.entries) {
        if (entry.value != null) {
          socialLinks[entry.key] = entry.value.toString();
        }
      }
    }

    return Profile(
      id: json["id"]?.toString() ?? '',
      profileName: json["profileName"]?.toString() ?? 'Unknown',
      name: json["name"]?.toString() ?? 'Unknown',
      socialLinks: socialLinks,
    );
  }

  /// Validate if profile has minimum required data for swapping
  bool get isValidForSwap {
    // Must have a name
    final nameValid = name.isNotEmpty;

    // Must have at least one social link with non-empty value
    final hasAnySocial = socialLinks.values.any((value) => value.isNotEmpty);

    // Debug output
    debugPrint('=== PROFILE VALIDATION ===');
    debugPrint('Name: "$name", nameValid: $nameValid');
    debugPrint('Social links: $socialLinks');
    debugPrint('hasAnySocial: $hasAnySocial');
    debugPrint('isValidForSwap: ${nameValid && hasAnySocial}');

    return nameValid && hasAnySocial;
  }
}
