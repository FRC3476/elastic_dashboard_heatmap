/// Configuration for default subscription periods based on topic patterns.
/// This allows different topics to have different update frequencies,
/// reducing load on topics that update slowly (like cameras).

/// Default subscription periods for different topic types
class SubscriptionPeriodDefaults {
  // Pattern -> Period in seconds
  static const Map<String, double> patterns = {
    '*.camera*': 0.5,      // 500ms for camera topics
    '*.stream*': 0.5,      // 500ms for stream topics
    '*.mjpeg*': 0.5,       // 500ms for mjpeg topics
    '*/match_time': 0.1,   // 100ms for match time (needs frequent updates)
    '*': 0.2,              // 200ms default (up from 100ms)
  };

  /// Get the appropriate subscription period for a topic
  static double getPeriodForTopic(String topic) {
    // Check patterns in order (more specific patterns first)
    for (final pattern in patterns.keys) {
      if (_topicMatchesPattern(topic, pattern)) {
        return patterns[pattern]!;
      }
    }
    return patterns['*']!;
  }

  /// Helper function to match topic patterns (supports simple wildcards)
  static bool _topicMatchesPattern(String topic, String pattern) {
    if (pattern == '*') {
      return true;
    }

    // Simple glob-style pattern matching
    // Converts patterns like "*.camera*" to regex
    RegExp regex = RegExp(
      '^${pattern.replaceAll('*', '.*').replaceAll('.', r'\.')}$',
    );
    return regex.hasMatch(topic);
  }
}
