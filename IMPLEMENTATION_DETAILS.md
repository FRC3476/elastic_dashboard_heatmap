## Implementation Details: Network Optimization Code Changes

This document provides code-level details about the implementation.

### New Files

#### 1. `lib/services/subscription_retry_strategy.dart`

**Purpose**: Provides retry strategy framework and metadata tracking for subscriptions.

**Key Classes**:
- `SubscriptionRetryMetadata` - Per-subscription retry state
  - Tracks last attempt time, failure count, current retry interval
  - `shouldRetrySubscription()` - Checks if enough time has passed for retry
  - `updateRetryIntervalOnFailure()` - Implements exponential backoff per topic
  - `resetOnSuccess()` - Called when subscription receives first data

- `SubscriptionRetryStrategy` - Defines retry behavior for topic patterns
  - `topicPattern` - Glob pattern (e.g., "*.camera*", "*")
  - `minRetryInterval` - Starting retry interval (1-10 seconds)
  - `maxRetryInterval` - Maximum retry interval (15-60 seconds)
  - `maxRetries` - Max retry attempts (-1 = infinite)
  - `matches()` - Check if pattern matches topic
  - `shouldRetry()` - Check if subscription should be retried

- `SubscriptionRetryStrategies` - Default strategies
  - Camera topics: 10-60 second retry interval
  - Stream topics: 10-60 second retry interval
  - Standard topics: 1-15 second retry interval
  - `getStrategyForTopic()` - Get appropriate strategy for a topic

**Pattern Matching**:
- Uses simple glob pattern to regex conversion
- `*.camera*` → regex `^.*\.camera.*$`
- Checked in order, first match wins

#### 2. `lib/services/subscription_period_config.dart`

**Purpose**: Provides topic-aware defaults for subscription update periods.

**Key Class**:
- `SubscriptionPeriodDefaults`
  - Static patterns map: topic pattern → period in seconds
  - Camera topics: 0.5s (500ms)
  - Stream topics: 0.5s (500ms)
  - MJPEG topics: 0.5s (500ms)
  - Match time: 0.1s (100ms, needs frequent updates)
  - Default: 0.2s (200ms)
  - `getPeriodForTopic()` - Get period for a topic
  - Uses same pattern matching as subscription_retry_strategy.dart

### Modified Files

#### 1. `lib/services/nt4_client.dart`

**New Constants**:
```dart
static const int _initialConnectionDelayMs = 500;
static const int _maxConnectionDelayMs = 5000;
```

**New Class Variables**:
```dart
Timer? _subscriptionRetryTimer;
int _connectionDelayMs = _initialConnectionDelayMs;
int _consecutiveConnectionFailures = 0;
```

**Constructor Changes**:
- Now creates `_subscriptionRetryTimer` that runs every 500ms
- Calls `_scheduleNextConnectionAttempt()` instead of Timer.periodic

**New Methods**:

`_scheduleNextConnectionAttempt()`:
```dart
void _scheduleNextConnectionAttempt() {
  _connectionTimer?.cancel();
  _connectionTimer = Timer(Duration(milliseconds: _connectionDelayMs), () {
    if (_attemptConnection && !mainWebsocketActive) {
      _connect();
      _rttConnect();
    }
    if (_attemptConnection) {
      _scheduleNextConnectionAttempt(); // Recursive scheduling
    }
  });
}
```
- Implements exponential backoff by using variable `_connectionDelayMs`
- Recursively schedules next attempt with new delay

`_resendSubscriptionsStaggered()`:
```dart
void _resendSubscriptionsStaggered() {
  const Duration staggerDelay = Duration(milliseconds: 50);
  int index = 0;
  
  for (NT4Subscription sub in _subscriptions.values) {
    Future.delayed(staggerDelay * index, () {
      if (mainWebsocketActive) {
        _wsSubscribe(sub);
      }
    });
    index++;
  }
}
```
- Spreads out subscription sends by 50ms each
- Only sends if connection is still active

`_retryFailedSubscriptions()`:
```dart
void _retryFailedSubscriptions() {
  if (!mainWebsocketActive) return;
  
  for (NT4Subscription sub in _subscriptions.values) {
    if (sub.currentValue == null) { // Only retry if no data
      final strategy = SubscriptionRetryStrategies.getStrategyForTopic(sub.topic);
      
      if (strategy.shouldRetry(sub.retryMetadata)) {
        _wsSubscribe(sub);
        sub.retryMetadata.recordAttempt();
        sub.retryMetadata.updateRetryIntervalOnFailure(
          strategy.minRetryInterval,
          strategy.maxRetryInterval,
        );
        logger.trace('Retrying subscription for topic "${sub.topic}" '
          '(attempt ${sub.retryMetadata.subscriptionFailureCount}, '
          'next retry in ${sub.retryMetadata.retryInterval.inSeconds}s)');
      }
    }
  }
}
```
- Runs every 500ms on separate timer
- Only retries subscriptions with `currentValue == null`
- Updates per-topic exponential backoff

**Modified _connect() Method**:
```dart
// On failure:
if (mainServerAddr.contains(serverBaseAddress)) {
  _consecutiveConnectionFailures++;
  _connectionDelayMs = ((_initialConnectionDelayMs *
      (1 << _consecutiveConnectionFailures.clamp(0, 8)))
      .clamp(0, _maxConnectionDelayMs)
      .toInt());
  logger.info('Failed to connect... next retry in ${_connectionDelayMs}ms');
  _attemptingNTConnection = false;
}

// On success:
_consecutiveConnectionFailures = 0;
_connectionDelayMs = _initialConnectionDelayMs;
```
- Increments `_consecutiveConnectionFailures` on failure
- Calculates new delay: `initial × 2^failureCount` (capped at max)
- Resets counters on success

**Modified Connection Initialization**:
```dart
// Instead of:
_connectionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) { ... });

// Now:
_resendSubscriptionsStaggered(); // Stagger on reconnect
_subscriptionRetryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
  _retryFailedSubscriptions();
});
_scheduleNextConnectionAttempt(); // Dynamic backoff
```

**Modified setServerBaseAddress()**:
```dart
// Reset backoff when changing server
_consecutiveConnectionFailures = 0;
_connectionDelayMs = _initialConnectionDelayMs;

// Immediately try to connect with new address
_scheduleNextConnectionAttempt();
```

**Updated cancelConnectionTimer()**:
```dart
void cancelConnectionTimer() {
  _connectionTimer?.cancel();
  _subscriptionRetryTimer?.cancel(); // Also cancel retry timer
}
```

#### 2. `lib/services/nt4_client.dart` - NT4Subscription Class

**New Instance Variable**:
```dart
late SubscriptionRetryMetadata retryMetadata;
```

**Constructor Update**:
```dart
NT4Subscription({
  required this.topic,
  this.options = const NT4SubscriptionOptions(),
  this.uid = -1,
}) : super(null) {
  retryMetadata = SubscriptionRetryMetadata(topic: topic);
  // Set initial retry interval based on topic pattern
  final strategy = SubscriptionRetryStrategies.getStrategyForTopic(topic);
  retryMetadata.retryInterval = strategy.minRetryInterval;
}
```

**Modified updateValue() Method**:
```dart
void updateValue(Object? value, int timestamp) {
  // Reset retry metadata when we get data
  if (value != null && currentValue == null) {
    retryMetadata.resetOnSuccess();
  }
  // ... rest of method ...
}
```
- When a subscription receives its first data value, retry counters reset
- Prevents further retries once subscription is satisfied

#### 3. `lib/widgets/nt_widgets/nt_widget.dart`

**New Import**:
```dart
import 'package:elastic_dashboard/services/subscription_period_config.dart';
```

**Updated NTWidgetModel Constructor**:
```dart
NTWidgetModel({
  required this.ntConnection,
  required this.preferences,
  required String topic,
  double? period,
}) : _topic = topic {
  this.period =
      period ??
      preferences.getDouble(PrefKeys.defaultPeriod) ??
      SubscriptionPeriodDefaults.getPeriodForTopic(topic); // NEW
}
```
- Changed from fixed `Defaults.defaultPeriod` to topic-aware `getPeriodForTopic()`

**Updated NTWidgetModel.fromJson()**:
```dart
NTWidgetModel.fromJson({
  required this.ntConnection,
  required this.preferences,
  required Map<String, dynamic> jsonData,
}) {
  _topic = tryCast(jsonData['topic']) ?? '';
  
  _period =
      tryCast(jsonData['period']) ??
      preferences.getDouble(PrefKeys.defaultPeriod) ??
      SubscriptionPeriodDefaults.getPeriodForTopic(_topic); // NEW
}
```

### How It All Works Together

#### Connection Flow:
1. App starts → waits 1.5 seconds → calls `_connect()`
2. `_connect()` attempts WebSocket connection
3. **Success**: Resets backoff counters, calls `_resendSubscriptionsStaggered()`
   - Subscriptions sent every 50ms
   - `_subscriptionRetryTimer` starts checking for failed subscriptions
4. **Failure**: Increments failure counter, calculates new backoff delay
   - Next attempt scheduled with new delay
   - Delay increases exponentially: 500ms → 1s → 2s → 4s → 5s max

#### Subscription Retry Flow:
1. `_subscriptionRetryTimer` fires every 500ms
2. Calls `_retryFailedSubscriptions()`
3. For each subscription with `currentValue == null`:
   - Get retry strategy for topic
   - Check if `strategy.shouldRetry(metadata)`
   - If yes: send subscription, record attempt
   - Update per-topic exponential backoff
4. Once subscription receives data:
   - `updateValue()` is called with non-null value
   - `retryMetadata.resetOnSuccess()` clears retry state
   - Future retry checks skip this subscription

#### Widget Subscription Period:
1. Widget created with topic
2. Constructor calls `SubscriptionPeriodDefaults.getPeriodForTopic(topic)`
3. Patterns checked in order: cameras → streams → mjpeg → match_time → default
4. Period set to matched pattern's value (0.5s, 0.1s, or 0.2s)
5. Widget subscribes with this period
6. Subscriptions delivered at this rate (not 100ms anymore)

### Key Design Decisions

1. **Separate Retry Timer**: Retry logic runs on separate 500ms timer, not connection timer
   - Allows different frequencies for connection vs subscription retry
   - Connection backoff can go up to 5 seconds without blocking subscription retries

2. **Per-Topic Exponential Backoff**: Each topic tracks its own failure count
   - Prevents slow topics from being hammered
   - Cameras get 10-60 second intervals automatically

3. **Stagger on Reconnect**: Even on IP address change, subscriptions are staggered
   - Matches subscription pattern expectation for robot startup

4. **Pattern Matching**: Topic patterns are simple glob-style (not regex)
   - Easy to understand and customize
   - Same format used for periods and retry strategies

5. **Automatic Reset on Data**: No manual unsubscribe needed to stop retries
   - Once data received, subscription is "healthy"
   - Reduces complexity and prevents edge cases

### Future Extensions

Could add:
- Metrics collection for per-topic success rates
- Adaptive backoff based on observed topic startup times
- Dashboard UI for subscription health monitoring
- Per-team configurable retry strategies
- User override capabilities in settings UI
