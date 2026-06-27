/// Centralized platform configuration for easy extensibility
library;

/// The domain for the SWAP web service
/// In debug mode: your local machine's IP (phone must be on same WiFi)
/// In release mode: your production domain
const String _domain = 'swapapp.ddns.net';
const int profilesNumber = 2;

String get swapDomain => _domain;

/// The base URL for SWAP profile sharing
/// Debug uses HTTP (localhost), release uses HTTPS
String get swapBaseUrl => 'https://$swapDomain';

/// Generate a SWAP profile view URL
String swapProfileUrl(String sessionId, String signature) =>
    '$swapBaseUrl/view/$sessionId?sig=$signature';

/// Platforms that require an optional profile link (can't construct URL from username)
/// Add platforms here that don't have a standard username-to-URL format
const List<String> linkRequiredPlatforms = ['discord'];

/// All social platforms (displayed in Socials section)
const List<String> socialPlatforms = [
  'instagram',
  'twitter',
  'discord',
  'snapchat',
  'tiktok',
  'github',
];

/// Contact platforms (displayed in Contact section)
const List<String> contactPlatforms = ['email', 'phone'];

/// All platforms combined
List<String> get allPlatforms => [...socialPlatforms, ...contactPlatforms];

/// Get the link storage key for a platform (e.g., 'discord' -> 'discord_link')
String getLinkKey(String platform) => '${platform}_link';

/// Check if platform requires optional link instead of URL construction
bool requiresOptionalLink(String platform) =>
    linkRequiredPlatforms.contains(platform);

/// URL prefixes for validation - links must contain these to be valid
/// Add new platforms here as needed (e.g., 'discord': 'discord.com/')
const Map<String, String> platformUrlPrefixes = {
  'instagram': 'instagram.com/',
  'twitter': 'x.com/',
  'tiktok': 'tiktok.com/',
  'snapchat': 'snapchat.com/',
  'github': 'github.com/',
  'discord': 'discord.gg/',
};

/// Validate if a URL is valid for a given platform
bool isValidUrlForPlatform(String platform, String url) {
  if (url.isEmpty) return false;
  final prefix = platformUrlPrefixes[platform];
  if (prefix == null || prefix.isEmpty) {
    // No validation defined, accept any non-empty URL
    return url.startsWith('http://') || url.startsWith('https://');
  }
  return url.contains(prefix);
}

/// Get placeholder text for a platform's main input field
String getPlaceholderFor(String platform) {
  switch (platform) {
    case 'email':
      return 'Email Address';
    case 'phone':
      return 'Phone Number';
    default:
      return '@Username';
  }
}

/// Get the optional link field placeholder text
String getLinkPlaceholder(String platform) {
  if (requiresOptionalLink(platform)) {
    return 'Profile Link (Required)';
  }
  return 'Profile Link (Optional)';
}

/// Get help text for platforms that require optional links
String getLinkHelpText(String platform) {
  if (requiresOptionalLink(platform)) {
    return 'Link is required to open this platform.';
  }
  return 'If provided, this link will be used instead of the username.';
}
