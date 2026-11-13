import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/gold_card_models.dart';

/// Real-time 60-120 Hz physics & optical controller for GoldCard.
///
/// Enforces strict mathematical axis separation:
/// - [computeLenticularWeights] depends EXCLUSIVELY on [horizontalTilt].
/// - [computeIridescentFoilState] depends on BOTH [horizontalTilt] and [verticalTilt].
class GoldCardEngine extends ChangeNotifier {
  GoldCardEngine({bool attachPlatformChannels = true})
    : _snapshot = _buildSnapshot(
        phase: CardAppPhase.waitingReady,
        transitionProgress: 0.0,
        horizontalTilt: 0.0,
        verticalTilt: 0.0,
        isCalibrated: false,
        hasHardwareAccelerometer: false,
      ) {
    if (attachPlatformChannels) {
      unawaited(startListeningHardware());
    }
  }

  static const String accelerometerChannelName =
      'cloud.orbital8.gold_card/accelerometer';
  static const String deviceChannelName = 'cloud.orbital8.gold_card/device';

  /// Entrance cross-fade duration after pressing `"ready"` (`0.85 s`).
  static const double fadeDurationSeconds = 0.85;

  /// Exponential low-pass responsiveness constant (`1 - exp(-dt * 14.0)`).
  static const double lowPassRate = 14.0;

  /// Soft deadzone eliminating hand micro-tremors around the calibrated zero point.
  static const double softDeadzone = 0.025;

  static const EventChannel _accelerometerChannel = EventChannel(
    accelerometerChannelName,
  );
  static const MethodChannel _deviceChannel = MethodChannel(deviceChannelName);

  StreamSubscription<dynamic>? _sensorSubscription;
  bool _isDisposed = false;

  CardAppPhase _phase = CardAppPhase.waitingReady;
  double _transitionElapsed = 0.0;
  double _transitionProgress = 0.0;

  double _lastRawScreenHorizontal = 0.0;
  double _lastRawScreenVertical = 0.0;
  bool _hasReceivedRawSample = false;

  double _zeroHorizontal = 0.0;
  double _zeroVertical = 0.0;
  bool _isCalibrated = false;
  bool _hasHardwareAccelerometer = false;

  double _targetHorizontalTilt = 0.0;
  double _targetVerticalTilt = 0.0;
  double _horizontalTilt = 0.0;
  double _verticalTilt = 0.0;

  GoldCardSnapshot _snapshot;

  /// Current immutable state snapshot.
  GoldCardSnapshot get snapshot => _snapshot;

  CardAppPhase get phase => _phase;
  double get transitionProgress => _transitionProgress;
  double get horizontalTilt => _horizontalTilt;
  double get verticalTilt => _verticalTilt;
  LenticularBlendWeights get blendWeights => _snapshot.blendWeights;
  IridescentFoilState get foilState => _snapshot.foilState;
  bool get isCalibrated => _isCalibrated;
  bool get hasHardwareAccelerometer => _hasHardwareAccelerometer;
  double get zeroHorizontalOffset => _zeroHorizontal;
  double get zeroVerticalOffset => _zeroVertical;

  /// Whether the engine currently has an active fade-in or unsettled tilt interpolation
  /// requiring frame ticks (`step(dt)`). Allows Ticker idling when stationary.
  bool get hasPendingMotion =>
      _phase == CardAppPhase.fadingIn ||
      (_horizontalTilt - _targetHorizontalTilt).abs() > 1e-4 ||
      (_verticalTilt - _targetVerticalTilt).abs() > 1e-4;

  /// Pure function computing the 3-image lenticular blend weights.
  ///
  /// Depends **ONLY** on [horizontalTilt] (`verticalTilt` is not even an input):
  /// - `h < 0`: smoothstep from `Front.png` (`0.0`) to `Left.png` (`-1.0`).
  /// - `h == 0`: 100% `Front.png`.
  /// - `h > 0`: smoothstep from `Front.png` (`0.0`) to `Right.png` (`+1.0`).
  static LenticularBlendWeights computeLenticularWeights(
    double horizontalTilt,
  ) {
    final double h = horizontalTilt.isNaN
        ? 0.0
        : horizontalTilt.clamp(-1.0, 1.0);
    if (h < 0.0) {
      final double t = (-h).clamp(0.0, 1.0);
      final double s = t * t * (3.0 - 2.0 * t);
      return LenticularBlendWeights(
        leftWeight: s,
        frontWeight: 1.0 - s,
        rightWeight: 0.0,
        normalizedHorizontalTilt: h,
      );
    }
    if (h > 0.0) {
      final double t = h.clamp(0.0, 1.0);
      final double s = t * t * (3.0 - 2.0 * t);
      return LenticularBlendWeights(
        leftWeight: 0.0,
        frontWeight: 1.0 - s,
        rightWeight: s,
        normalizedHorizontalTilt: h,
      );
    }
    return const LenticularBlendWeights.center();
  }

  /// Pure function computing the 2D holographic metallic iridescent foil state.
  ///
  /// Coupled simultaneously to BOTH [horizontalTilt] and [verticalTilt].
  static IridescentFoilState computeIridescentFoilState({
    required double horizontalTilt,
    required double verticalTilt,
  }) {
    final double h = horizontalTilt.isNaN
        ? 0.0
        : horizontalTilt.clamp(-1.0, 1.0);
    final double v = verticalTilt.isNaN ? 0.0 : verticalTilt.clamp(-1.0, 1.0);

    final Offset specularCenter = Offset(
      (0.5 + 0.42 * h).clamp(0.0, 1.0),
      (0.5 + 0.42 * v).clamp(0.0, 1.0),
    );

    final double iridescentPhase = h * 2.4 + v * 1.9;

    // Smooth, branch-cut-free 2D angle strictly sensitive to both h and v everywhere on [-1, 1]^2.
    final double foilAngleRadians =
        -0.58 +
        0.68 * h +
        0.52 * v +
        0.22 * math.atan2(v + 0.35, h + 1.25);

    final double tiltMagnitude = math.sqrt(h * h + v * v);
    final double clampedMag = tiltMagnitude.clamp(0.0, 1.0);
    final double harmonicShimmer =
        0.5 + 0.5 * math.sin(h * 3.6 - v * 2.8 + 0.4);

    final double sheenIntensity = (0.38 + 0.58 * clampedMag).clamp(0.0, 1.0);
    final double sparkleIntensity =
        (0.24 + 0.54 * clampedMag + 0.22 * harmonicShimmer * clampedMag).clamp(
          0.0,
          1.0,
        );

    return IridescentFoilState(
      horizontalTilt: h,
      verticalTilt: v,
      specularCenter: specularCenter,
      iridescentPhase: iridescentPhase,
      foilAngleRadians: foilAngleRadians,
      sheenIntensity: sheenIntensity,
      sparkleIntensity: sparkleIntensity,
    );
  }

  /// Continuous soft deadzone mapping `[-deadzone, +deadzone]` to `0.0`
  /// and rescaling `[deadzone, 1.0]` smoothly onto `[0.0, 1.0]`.
  static double applySoftDeadzone(
    double value, [
    double deadzone = softDeadzone,
  ]) {
    if (!value.isFinite) return 0.0;
    final double clamped = value.clamp(-1.0, 1.0);
    final double absVal = clamped.abs();
    if (absVal <= deadzone) {
      return 0.0;
    }
    final double normalized = (absVal - deadzone) / (1.0 - deadzone);
    return clamped.sign * normalized.clamp(0.0, 1.0);
  }

  /// Connects to the native 60 Hz landscape accelerometer channels.
  /// Safe in headless widget/unit test environments without native plugins.
  Future<void> startListeningHardware() async {
    if (_isDisposed || _sensorSubscription != null) return;

    try {
      final bool? available = await _deviceChannel.invokeMethod<bool>(
        'hasAccelerometer',
      );
      if (_isDisposed) return;
      if (available != null) {
        _hasHardwareAccelerometer = available;
        _syncSnapshotAndNotify();
      }
      await _deviceChannel.invokeMethod<bool>('lockLandscape');
    } on MissingPluginException {
      // Expected in flutter test / desktop preview without native runner.
      return;
    } on PlatformException {
      // Non-fatal: continue gracefully with touch/manual fallback.
    }

    if (_isDisposed) return;

    try {
      _sensorSubscription = _accelerometerChannel
          .receiveBroadcastStream()
          .listen(
            (dynamic event) {
              if (_isDisposed || event is! Map<Object?, Object?>) return;
              final double? screenH = _asDouble(event['screenHorizontal']);
              final double? screenV = _asDouble(event['screenVertical']);
              if (screenH == null || screenV == null) return;
              updateHardwareAccelerometer(
                screenHorizontal: screenH,
                screenVertical: screenV,
                rawX: _asDouble(event['x']),
                rawY: _asDouble(event['y']),
                rawZ: _asDouble(event['z']),
              );
            },
            onError: (Object _) {
              // Ignore stream errors in headless environments.
            },
            cancelOnError: false,
          );
    } on MissingPluginException {
      _sensorSubscription = null;
    } on PlatformException {
      _sensorSubscription = null;
    }
  }

  /// Cancels active native sensor subscriptions.
  Future<void> stopListeningHardware() async {
    final StreamSubscription<dynamic>? sub = _sensorSubscription;
    _sensorSubscription = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } on MissingPluginException {
        // Safe in widget tests when no native stream handler is registered.
      } on PlatformException {
        // Safe cleanup fallback.
      }
    }
  }

  /// Captures the latest device posture as the `(0, 0)` reference zero point
  /// so `Front.png` displays centered regardless of initial viewing pitch/roll.
  void calibrateZeroPoint() {
    if (_hasReceivedRawSample) {
      _zeroHorizontal = _lastRawScreenHorizontal;
      _zeroVertical = _lastRawScreenVertical;
    } else {
      _zeroHorizontal = 0.0;
      _zeroVertical = 0.0;
    }
    _targetHorizontalTilt = 0.0;
    _targetVerticalTilt = 0.0;
    _horizontalTilt = 0.0;
    _verticalTilt = 0.0;
    _isCalibrated = true;
    _syncSnapshotAndNotify();
  }

  /// Triggered when pressing the floating `"ready"` button:
  /// calibrates the zero point and initiates the `0.85 s` smooth fade-in.
  void pressReady() {
    if (_phase != CardAppPhase.waitingReady) {
      return;
    }
    if (_hasReceivedRawSample) {
      _zeroHorizontal = _lastRawScreenHorizontal;
      _zeroVertical = _lastRawScreenVertical;
    } else {
      _zeroHorizontal = 0.0;
      _zeroVertical = 0.0;
    }
    _targetHorizontalTilt = 0.0;
    _targetVerticalTilt = 0.0;
    _horizontalTilt = 0.0;
    _verticalTilt = 0.0;
    _isCalibrated = true;
    _phase = CardAppPhase.fadingIn;
    _transitionElapsed = 0.0;
    _transitionProgress = 0.0;
    _syncSnapshotAndNotify();
  }

  /// Resets the experience back to the initial pure-black `"ready"` screen.
  void resetToWaitingReady() {
    _phase = CardAppPhase.waitingReady;
    _transitionElapsed = 0.0;
    _transitionProgress = 0.0;
    _targetHorizontalTilt = 0.0;
    _targetVerticalTilt = 0.0;
    _horizontalTilt = 0.0;
    _verticalTilt = 0.0;
    _syncSnapshotAndNotify();
  }

  /// Feeds a 60 Hz landscape-projected accelerometer sample into the engine.
  void updateHardwareAccelerometer({
    required double screenHorizontal,
    required double screenVertical,
    double? rawX,
    double? rawY,
    double? rawZ,
  }) {
    if (!screenHorizontal.isFinite || !screenVertical.isFinite) return;
    // Touch rawX/rawY/rawZ to acknowledge optional diagnostics telemetry cleanly.
    final bool hasFiniteRaw =
        (rawX == null || rawX.isFinite) &&
        (rawY == null || rawY.isFinite) &&
        (rawZ == null || rawZ.isFinite);
    if (!hasFiniteRaw) return;

    _lastRawScreenHorizontal = screenHorizontal;
    _lastRawScreenVertical = screenVertical;
    _hasReceivedRawSample = true;
    _hasHardwareAccelerometer = true;

    final double deltaH = (screenHorizontal - _zeroHorizontal).clamp(-1.0, 1.0);
    final double deltaV = (screenVertical - _zeroVertical).clamp(-1.0, 1.0);

    final double nextTargetH = applySoftDeadzone(deltaH, softDeadzone);
    final double nextTargetV = applySoftDeadzone(deltaV, softDeadzone);
    final bool targetChanged =
        (nextTargetH - _targetHorizontalTilt).abs() > 1e-6 ||
        (nextTargetV - _targetVerticalTilt).abs() > 1e-6;

    _targetHorizontalTilt = nextTargetH;
    _targetVerticalTilt = nextTargetV;
    _syncSnapshotAndNotify(forceNotify: targetChanged);
  }

  /// Sets manual/touch tilt targets (used for touch fallback, emulator & tests).
  ///
  /// If [immediate] is `true`, bypasses low-pass smoothing and updates the
  /// active tilt angles and optical weights instantaneously.
  void setManualTilt({
    required double horizontalTilt,
    required double verticalTilt,
    bool immediate = false,
  }) {
    final double clampedH = horizontalTilt.isFinite
        ? horizontalTilt.clamp(-1.0, 1.0)
        : 0.0;
    final double clampedV = verticalTilt.isFinite
        ? verticalTilt.clamp(-1.0, 1.0)
        : 0.0;

    if (immediate) {
      _targetHorizontalTilt = clampedH;
      _targetVerticalTilt = clampedV;
      _horizontalTilt = clampedH;
      _verticalTilt = clampedV;
      _syncSnapshotAndNotify();
      return;
    }

    final double nextTargetH = clampedH.abs() <= softDeadzone ? 0.0 : clampedH;
    final double nextTargetV = clampedV.abs() <= softDeadzone ? 0.0 : clampedV;
    final bool targetChanged =
        (nextTargetH - _targetHorizontalTilt).abs() > 1e-6 ||
        (nextTargetV - _targetVerticalTilt).abs() > 1e-6;

    _targetHorizontalTilt = nextTargetH;
    _targetVerticalTilt = nextTargetV;
    _syncSnapshotAndNotify(forceNotify: targetChanged);
  }

  /// Advances fade transition (`0.85 s`) and exponential low-pass sensor filter.
  void step(double dt) {
    if (!dt.isFinite || dt <= 0.0 || _isDisposed) return;

    bool changed = false;

    if (_phase == CardAppPhase.fadingIn) {
      _transitionElapsed += dt;
      final double nextProgress = (_transitionElapsed / fadeDurationSeconds)
          .clamp(0.0, 1.0);
      if (nextProgress != _transitionProgress) {
        _transitionProgress = nextProgress;
        changed = true;
      }
      if (_transitionProgress >= 1.0) {
        _transitionProgress = 1.0;
        _phase = CardAppPhase.activeComposition;
        changed = true;
      }
    }

    final double alpha = (1.0 - math.exp(-dt * lowPassRate)).clamp(0.0, 1.0);
    final double nextH = _lerpSnap(
      _horizontalTilt,
      _targetHorizontalTilt,
      alpha,
    );
    final double nextV = _lerpSnap(_verticalTilt, _targetVerticalTilt, alpha);

    if ((nextH - _horizontalTilt).abs() > 1e-7 ||
        (nextV - _verticalTilt).abs() > 1e-7) {
      _horizontalTilt = nextH;
      _verticalTilt = nextV;
      changed = true;
    }

    if (changed) {
      _syncSnapshotAndNotify();
    }
  }

  static double _lerpSnap(double current, double target, double alpha) {
    final double interpolated = current + (target - current) * alpha;
    if ((interpolated - target).abs() < 1e-4) {
      return target;
    }
    if (target == 0.0 && interpolated.abs() < 1e-4) {
      return 0.0;
    }
    return interpolated.clamp(-1.0, 1.0);
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      final double d = value.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }

  void _syncSnapshotAndNotify({bool forceNotify = false}) {
    if (_isDisposed) return;
    final GoldCardSnapshot next = _buildSnapshot(
      phase: _phase,
      transitionProgress: _transitionProgress,
      horizontalTilt: _horizontalTilt,
      verticalTilt: _verticalTilt,
      isCalibrated: _isCalibrated,
      hasHardwareAccelerometer: _hasHardwareAccelerometer,
    );
    if (next != _snapshot || forceNotify) {
      _snapshot = next;
      notifyListeners();
    }
  }

  static GoldCardSnapshot _buildSnapshot({
    required CardAppPhase phase,
    required double transitionProgress,
    required double horizontalTilt,
    required double verticalTilt,
    required bool isCalibrated,
    required bool hasHardwareAccelerometer,
  }) {
    return GoldCardSnapshot(
      phase: phase,
      transitionProgress: transitionProgress,
      horizontalTilt: horizontalTilt,
      verticalTilt: verticalTilt,
      blendWeights: computeLenticularWeights(horizontalTilt),
      foilState: computeIridescentFoilState(
        horizontalTilt: horizontalTilt,
        verticalTilt: verticalTilt,
      ),
      isCalibrated: isCalibrated,
      hasHardwareAccelerometer: hasHardwareAccelerometer,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    final StreamSubscription<dynamic>? sub = _sensorSubscription;
    _sensorSubscription = null;
    if (sub != null) {
      unawaited(
        sub.cancel().catchError((Object _) {
          // Ignore platform teardown exceptions on dispose.
        }),
      );
    }
    super.dispose();
  }
}
