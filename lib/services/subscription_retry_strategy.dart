/// Subscription retry strategies for managing topic subscription behavior.
/// This allows different topics to have different retry behaviors based on their
/// characteristics (e.g., cameras take longer to startup, so they retry less frequently).

import 'package:flutter/foundation.dart';

/// Metadata about a subscription's retry behavior and health
class SubscriptionRetryMetadata {
  final String topic;
  DateTime lastSubscriptionAttempt = DateTime.now();
  int subscriptionFailureCount = 0;
  Duration retryInterval;

  SubscriptionRetryMetadata({
    required this.topic,
    this.retryInterval = const Duration(seconds: 1),
  });

  /// Check if enough time has passed to retry this subscription
  bool shouldRetrySubscription() {
    return DateTime.now().difference(lastSubscriptionAttempt) >= retryInterval;
  }

  /// Update the retry interval based on failure count (exponential backoff per topic)
  void updateRetryIntervalOnFailure(Duration baseInterval, Duration maxInterval) {
    int backoffExponent = subscriptionFailureCount.clamp(0, 10);
    retryInterval = Duration(
      milliseconds: (baseInterval.inMilliseconds *
              (1 << backoffExponent)
                  .clamp(1, 256)) // Cap at 256x to prevent overflow
          .toInt(),
    );
    if (retryInterval > maxInterval) {
      retryInterval = maxInterval;
    }
  }

  /// Reset retry metadata when subscription succeeds
  void resetOnSuccess() {
    subscriptionFailureCount = 0;
    lastSubscriptionAttempt = DateTime.now();
  }

  /// Record a subscription attempt
  void recordAttempt() {
    lastSubscriptionAttempt = DateTime.now();
    subscriptionFailureCount++;
  }
}

/// Defines retry strategy for topics matching a pattern
class SubscriptionRetryStrategy {
  final String topicPattern;
  final Duration minRetryInterval;
  final Duration maxRetryInterval;
  final int maxRetries; // -1 = infinite

  const SubscriptionRetryStrategy({
    required this.topicPattern,
    this.minRetryInterval = const Duration(seconds: 1),
    this.maxRetryInterval = const Duration(seconds: 30),
    this.maxRetries = -1,
  });

  /// Check if this strategy matches the given topic
  bool matches(String topic) {
    return _topicMatchesPattern(topic, topicPattern);
  }

  /// Determine if a subscription should be retried based on this strategy
  bool shouldRetry(SubscriptionRetryMetadata metadata) {
    if (maxRetries > 0 && metadata.subscriptionFailureCount >= maxRetries) {
      return false;
    }
    return metadata.shouldRetrySubscription();
  }
}

/// Default retry strategies for common topic patterns
class SubscriptionRetryStrategies {
  // Camera and stream topics take much longer to startup, so retry less frequently
  static const SubscriptionRetryStrategy cameraStrategy =
      SubscriptionRetryStrategy(
    topicPattern: '*.camera*',
    minRetryInterval: Duration(seconds: 10),
    maxRetryInterval: Duration(seconds: 60),
    maxRetries: -1,
  );

  static const SubscriptionRetryStrategy streamStrategy =
      SubscriptionRetryStrategy(
    topicPattern: '*.stream*',
    minRetryInterval: Duration(seconds: 10),
    maxRetryInterval: Duration(seconds: 60),
    maxRetries: -1,
  );

  // Standard topics retry more frequently
  static const SubscriptionRetryStrategy standardStrategy =
      SubscriptionRetryStrategy(
    topicPattern: '*',
    minRetryInterval: Duration(seconds: 1),
    maxRetryInterval: Duration(seconds: 15),
    maxRetries: -1,
  );

  static const List<SubscriptionRetryStrategy> defaults = [
    cameraStrategy,
    streamStrategy,
    standardStrategy,
  ];

  /// Get the appropriate retry strategy for a topic
  static SubscriptionRetryStrategy getStrategyForTopic(
    String topic, [
    List<SubscriptionRetryStrategy>? customStrategies,
  ]) {
    final strategies = customStrategies ?? defaults;

    // Strategies are checked in order, so more specific patterns should come first
    for (final strategy in strategies) {
      if (strategy.matches(topic)) {
        return strategy;
      }
    }

    return standardStrategy;
  }
}

/// Helper function to match topic patterns (supports simple wildcards)
bool _topicMatchesPattern(String topic, String pattern) {
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
