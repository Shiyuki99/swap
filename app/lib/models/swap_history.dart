class SwapHistory {
  final String id;
  final String username;
  final String note;
  final DateTime timestamp;
  final Map<String, String> swappedLinks;

  SwapHistory({
    required this.id,
    required this.username,
    required this.note,
    required this.timestamp,
    required this.swappedLinks,
  });

  /// Get only the social links that have non-empty values
  Map<String, String> get nonEmptyLinks {
    return Map.fromEntries(
      swappedLinks.entries.where(
        (e) => e.value.isNotEmpty && e.key != 'discord_id',
      ),
    );
  }

  /// Get username for a specific platform
  String? getUsernameFor(String platform) {
    final value = swappedLinks[platform];
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'note': note,
    'timestamp': timestamp.toIso8601String(),
    'swappedLinks': swappedLinks,
  };

  factory SwapHistory.fromJson(Map<String, dynamic> json) {
    return SwapHistory(
      id: json['id'] as String,
      username: json['username'] as String,
      note: json['note'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      swappedLinks: Map<String, String>.from(json['swappedLinks'] as Map),
    );
  }
}
