import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Lifecycle phase of the GoldCard collector experience.
enum CardAppPhase {
  /// Pure black screen (`#000000`) displaying the floating `"ready"` button.
  waitingReady,

  /// Smooth cross-fade (`0.0 -> 1.0` over `0.85 s`) from black into the card.
  fadingIn,

  /// Full-screen landscape lenticular + 2D metallic iridescent composition.
  activeComposition;

  bool get isWaitingReady => this == CardAppPhase.waitingReady;
  bool get isCompositionVisible => this != CardAppPhase.waitingReady;
  bool get isActiveComposition => this == CardAppPhase.activeComposition;
}

/// Immutable cross-blend weights for the 3 lenticular portraits.
///
/// Strictly governed by `horizontalTilt` alone (`verticalTilt` has zero effect).
@immutable
class LenticularBlendWeights {
  const LenticularBlendWeights({
    required this.leftWeight,
    required this.frontWeight,
    required this.rightWeight,
    required this.normalizedHorizontalTilt,
  });

  const LenticularBlendWeights.center()
    : leftWeight = 0.0,
      frontWeight = 1.0,
      rightWeight = 0.0,
      normalizedHorizontalTilt = 0.0;

  /// Opacity weight (`0.0 .. 1.0`) for `assets/images/Left.png` (office portrait with mustache).
  final double leftWeight;

  /// Opacity weight (`0.0 .. 1.0`) for `assets/images/Front.png` (office portrait without mustache).
  final double frontWeight;

  /// Opacity weight (`0.0 .. 1.0`) for `assets/images/Right.png` (Simpsons cartoon with mustache).
  final double rightWeight;

  /// Clamped horizontal tilt (`-1.0 .. +1.0`) that produced these weights.
  final double normalizedHorizontalTilt;

  /// Dominant image identifier (`'LEFT'`, `'FRONT'`, or `'RIGHT'`).
  String get dominantLayer {
    if (leftWeight > frontWeight && leftWeight >= rightWeight) {
      return 'LEFT';
    }
    if (rightWeight > frontWeight && rightWeight > leftWeight) {
      return 'RIGHT';
    }
    return 'FRONT';
  }

  /// Sum of weights (`1.0` across the entire horizontal range).
  double get totalWeight => leftWeight + frontWeight + rightWeight;

  /// Optical transition activity (`0.0` on pure single layer, `1.0` at 50/50 blend midpoint).
  double get transitionActivity =>
      (4.0 * frontWeight * (leftWeight + rightWeight)).clamp(0.0, 1.0);

  LenticularBlendWeights copyWith({
    double? leftWeight,
    double? frontWeight,
    double? rightWeight,
    double? normalizedHorizontalTilt,
  }) {
    return LenticularBlendWeights(
      leftWeight: leftWeight ?? this.leftWeight,
      frontWeight: frontWeight ?? this.frontWeight,
      rightWeight: rightWeight ?? this.rightWeight,
      normalizedHorizontalTilt:
          normalizedHorizontalTilt ?? this.normalizedHorizontalTilt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LenticularBlendWeights &&
        other.leftWeight == leftWeight &&
        other.frontWeight == frontWeight &&
        other.rightWeight == rightWeight &&
        other.normalizedHorizontalTilt == normalizedHorizontalTilt;
  }

  @override
  int get hashCode => Object.hash(
    leftWeight,
    frontWeight,
    rightWeight,
    normalizedHorizontalTilt,
  );

  @override
  String toString() {
    return 'LenticularBlendWeights('
        'left: ${leftWeight.toStringAsFixed(3)}, '
        'front: ${frontWeight.toStringAsFixed(3)}, '
        'right: ${rightWeight.toStringAsFixed(3)}, '
        'hTilt: ${normalizedHorizontalTilt.toStringAsFixed(3)}, '
        'dominant: $dominantLayer)';
  }
}

/// Immutable 2D optical state for the metallic holographic collector foil.
///
/// Driven simultaneously by BOTH [horizontalTilt] and [verticalTilt].
@immutable
class IridescentFoilState {
  const IridescentFoilState({
    required this.horizontalTilt,
    required this.verticalTilt,
    required this.specularCenter,
    required this.iridescentPhase,
    required this.foilAngleRadians,
    required this.sheenIntensity,
    required this.sparkleIntensity,
  });

  /// Normalized horizontal tilt (`-1.0 .. +1.0`).
  final double horizontalTilt;

  /// Normalized vertical tilt (`-1.0 .. +1.0`).
  final double verticalTilt;

  /// Normalized 2D specular hotspot coordinates in `[0.0, 1.0]²`.
  final Offset specularCenter;

  /// Spectral rainbow diffraction phase (coupled linearly to horizontal & vertical tilt).
  final double iridescentPhase;

  /// Orientation angle (in radians) of the anisotropic metallic diffraction bands.
  final double foilAngleRadians;

  /// Overall metallic sheen intensity (`0.0 .. 1.0`).
  final double sheenIntensity;

  /// Collector micro-glitter & facet sparkle intensity (`0.0 .. 1.0`).
  final double sparkleIntensity;

  IridescentFoilState copyWith({
    double? horizontalTilt,
    double? verticalTilt,
    Offset? specularCenter,
    double? iridescentPhase,
    double? foilAngleRadians,
    double? sheenIntensity,
    double? sparkleIntensity,
  }) {
    return IridescentFoilState(
      horizontalTilt: horizontalTilt ?? this.horizontalTilt,
      verticalTilt: verticalTilt ?? this.verticalTilt,
      specularCenter: specularCenter ?? this.specularCenter,
      iridescentPhase: iridescentPhase ?? this.iridescentPhase,
      foilAngleRadians: foilAngleRadians ?? this.foilAngleRadians,
      sheenIntensity: sheenIntensity ?? this.sheenIntensity,
      sparkleIntensity: sparkleIntensity ?? this.sparkleIntensity,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IridescentFoilState &&
        other.horizontalTilt == horizontalTilt &&
        other.verticalTilt == verticalTilt &&
        other.specularCenter == specularCenter &&
        other.iridescentPhase == iridescentPhase &&
        other.foilAngleRadians == foilAngleRadians &&
        other.sheenIntensity == sheenIntensity &&
        other.sparkleIntensity == sparkleIntensity;
  }

  @override
  int get hashCode => Object.hash(
    horizontalTilt,
    verticalTilt,
    specularCenter,
    iridescentPhase,
    foilAngleRadians,
    sheenIntensity,
    sparkleIntensity,
  );

  @override
  String toString() {
    return 'IridescentFoilState('
        'h: ${horizontalTilt.toStringAsFixed(3)}, '
        'v: ${verticalTilt.toStringAsFixed(3)}, '
        'center: (${specularCenter.dx.toStringAsFixed(3)}, ${specularCenter.dy.toStringAsFixed(3)}), '
        'phase: ${iridescentPhase.toStringAsFixed(3)}, '
        'angle: ${foilAngleRadians.toStringAsFixed(3)}, '
        'sheen: ${sheenIntensity.toStringAsFixed(3)}, '
        'sparkle: ${sparkleIntensity.toStringAsFixed(3)})';
  }
}

/// Complete immutable frame snapshot consumed by UI & CustomPainter layers.
@immutable
class GoldCardSnapshot {
  const GoldCardSnapshot({
    required this.phase,
    required this.transitionProgress,
    required this.horizontalTilt,
    required this.verticalTilt,
    required this.blendWeights,
    required this.foilState,
    required this.isCalibrated,
    required this.hasHardwareAccelerometer,
  });

  final CardAppPhase phase;
  final double transitionProgress;
  final double horizontalTilt;
  final double verticalTilt;
  final LenticularBlendWeights blendWeights;
  final IridescentFoilState foilState;
  final bool isCalibrated;
  final bool hasHardwareAccelerometer;

  GoldCardSnapshot copyWith({
    CardAppPhase? phase,
    double? transitionProgress,
    double? horizontalTilt,
    double? verticalTilt,
    LenticularBlendWeights? blendWeights,
    IridescentFoilState? foilState,
    bool? isCalibrated,
    bool? hasHardwareAccelerometer,
  }) {
    return GoldCardSnapshot(
      phase: phase ?? this.phase,
      transitionProgress: transitionProgress ?? this.transitionProgress,
      horizontalTilt: horizontalTilt ?? this.horizontalTilt,
      verticalTilt: verticalTilt ?? this.verticalTilt,
      blendWeights: blendWeights ?? this.blendWeights,
      foilState: foilState ?? this.foilState,
      isCalibrated: isCalibrated ?? this.isCalibrated,
      hasHardwareAccelerometer:
          hasHardwareAccelerometer ?? this.hasHardwareAccelerometer,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GoldCardSnapshot &&
        other.phase == phase &&
        other.transitionProgress == transitionProgress &&
        other.horizontalTilt == horizontalTilt &&
        other.verticalTilt == verticalTilt &&
        other.blendWeights == blendWeights &&
        other.foilState == foilState &&
        other.isCalibrated == isCalibrated &&
        other.hasHardwareAccelerometer == hasHardwareAccelerometer;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    transitionProgress,
    horizontalTilt,
    verticalTilt,
    blendWeights,
    foilState,
    isCalibrated,
    hasHardwareAccelerometer,
  );

  @override
  String toString() {
    return 'GoldCardSnapshot('
        'phase: $phase, '
        'progress: ${transitionProgress.toStringAsFixed(3)}, '
        'hTilt: ${horizontalTilt.toStringAsFixed(3)}, '
        'vTilt: ${verticalTilt.toStringAsFixed(3)}, '
        'calibrated: $isCalibrated, '
        'hwSensor: $hasHardwareAccelerometer)';
  }
}
