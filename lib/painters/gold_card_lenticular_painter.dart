import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gold_card_models.dart';

/// Decoded `ui.Image` sprite triad for the 3-image lenticular collector card.
class GoldCardSprites {
  const GoldCardSprites({
    this.leftImage,
    this.frontImage,
    this.rightImage,
  });

  static const String leftAssetPath = 'assets/images/Left.png';
  static const String frontAssetPath = 'assets/images/Front.png';
  static const String rightAssetPath = 'assets/images/Right.png';

  final ui.Image? leftImage;
  final ui.Image? frontImage;
  final ui.Image? rightImage;

  bool get isLoaded =>
      leftImage != null && frontImage != null && rightImage != null;

  /// Loads and decodes `Left.png`, `Front.png`, and `Right.png` into GPU-ready `ui.Image`s.
  ///
  /// Returns an empty [GoldCardSprites] fallback instead of throwing if assets
  /// cannot be decoded in a stripped headless test environment.
  static Future<GoldCardSprites> load({AssetBundle? bundle}) async {
    final AssetBundle effectiveBundle = bundle ?? rootBundle;
    try {
      final List<ui.Image?> decoded = await Future.wait<ui.Image?>(
        <Future<ui.Image?>>[
          _decodeAsset(effectiveBundle, leftAssetPath),
          _decodeAsset(effectiveBundle, frontAssetPath),
          _decodeAsset(effectiveBundle, rightAssetPath),
        ],
      );
      return GoldCardSprites(
        leftImage: decoded[0],
        frontImage: decoded[1],
        rightImage: decoded[2],
      );
    } catch (_) {
      return const GoldCardSprites();
    }
  }

  static Future<ui.Image?> _decodeAsset(
    AssetBundle bundle,
    String assetPath,
  ) async {
    try {
      final ByteData data = await bundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}

class _HolographicFacet {
  const _HolographicFacet({
    required this.nx,
    required this.ny,
    required this.prefH,
    required this.prefV,
    required this.radius,
    required this.colorIndex,
    required this.rotationOffset,
  });

  final double nx;
  final double ny;
  final double prefH;
  final double prefV;
  final double radius;
  final int colorIndex;
  final double rotationOffset;
}

/// Impeller-optimized 60-120 FPS CustomPainter rendering:
/// 1. Pure `#000000` obsidian backdrop.
/// 2. 3-image horizontal-only lenticular cross-blend (`Left.png` / `Front.png` / `Right.png`).
/// 3. Subtle optical vertical lenticular micro-prism array.
/// 4. 2D holographic metallic iridescent diffraction, anisotropic brushed-gold beam,
///    2D specular sheen hotspot, and pre-allocated collector micro-sparkles
///    (driven simultaneously by `horizontalTilt` AND `verticalTilt`).
/// 5. Zero-`saveLayer` black veil entrance fade (`transitionProgress`: `0.0 -> 1.0`).
class GoldCardLenticularPainter extends CustomPainter {
  GoldCardLenticularPainter({
    required this.snapshot,
    this.sprites,
    super.repaint,
  });

  final GoldCardSnapshot snapshot;
  final GoldCardSprites? sprites;

  static const List<Color> _foilSpectrumPalette = <Color>[
    Color(0xFFFFD700), // 24K Gold
    Color(0xFFFFF3B0), // Champagne Foil
    Color(0xFFFF4D94), // Holographic Rose
    Color(0xFF00F0FF), // Electric Cyan
    Color(0xFF9D4EDD), // Prism Violet
    Color(0xFF00F5D4), // Collector Emerald
  ];

  // Pre-allocated pool of 72 collector micro-sparkles (zero allocation inside paint()).
  static final List<_HolographicFacet> _facetPool = _generateFacetPool();

  static List<_HolographicFacet> _generateFacetPool() {
    final math.Random rng = math.Random(0x474F4C44); // 'GOLD'
    return List<_HolographicFacet>.generate(72, (int index) {
      // Stratified Halton-like distribution across [0.04, 0.96]^2.
      final double u = _halton(index + 1, 2);
      final double v = _halton(index + 1, 3);
      final double nx = 0.04 + 0.92 * u;
      final double ny = 0.05 + 0.90 * v;
      final double prefH = -0.92 + 1.84 * rng.nextDouble();
      final double prefV = -0.92 + 1.84 * rng.nextDouble();
      final double radius = 2.2 + 4.4 * rng.nextDouble();
      return _HolographicFacet(
        nx: nx,
        ny: ny,
        prefH: prefH,
        prefV: prefV,
        radius: radius,
        colorIndex: index % _foilSpectrumPalette.length,
        rotationOffset: rng.nextDouble() * math.pi,
      );
    }, growable: false);
  }

  static double _halton(int index, int base) {
    double result = 0.0;
    double f = 1.0 / base;
    int i = index;
    while (i > 0) {
      result += f * (i % base);
      i = i ~/ base;
      f /= base;
    }
    return result;
  }

  final Paint _blackPaint = Paint()..color = const Color(0xFF000000);
  final Paint _baseSpritePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;
  final Paint _overlaySpritePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;
  final Paint _lenticularPaint = Paint()..blendMode = BlendMode.softLight;
  final Paint _diffractionScreenPaint = Paint()..blendMode = BlendMode.screen;
  final Paint _diffractionOverlayPaint = Paint()..blendMode = BlendMode.overlay;
  final Paint _anisotropicStreakPaint = Paint()..blendMode = BlendMode.screen;
  final Paint _specularHotspotPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _sparkleFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.plus
    ..isAntiAlias = true;
  final Paint _sparkleRayPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.25
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus
    ..isAntiAlias = true;
  final Paint _outerRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..isAntiAlias = true;
  final Paint _innerRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..isAntiAlias = true;
  final Paint _fadeVeilPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect viewportRect = Offset.zero & size;

    // Layer 0: Pure #000000 black background.
    canvas.drawRect(viewportRect, _blackPaint);

    if (snapshot.phase == CardAppPhase.waitingReady ||
        snapshot.transitionProgress <= 0.0005) {
      return;
    }

    canvas.save();
    canvas.clipRect(viewportRect);

    // Subtle 3D collector card depth shift within full-bleed overscan (zero black edge bars).
    const double overscanPx = 10.0;
    final Offset microParallax = Offset(
      -snapshot.horizontalTilt * 6.0,
      -snapshot.verticalTilt * 4.5,
    );
    final Rect targetCardRect = viewportRect
        .inflate(overscanPx)
        .shift(microParallax);

    // Layer 1: 3-Image Lenticular Cross-Blend (governed ONLY by horizontalTilt).
    _paintLenticularTriad(canvas, targetCardRect, snapshot.blendWeights);

    // Layer 2: Optical vertical lenticular micro-prism array.
    _paintLenticularMicroPrisms(
      canvas,
      viewportRect,
      snapshot.blendWeights,
      snapshot.horizontalTilt,
    );

    // Layer 3: 2D Holographic Metallic Iridescent Foil (governed by BOTH horizontalTilt & verticalTilt).
    _paintIridescentFoilSurface(canvas, viewportRect, snapshot.foilState);
    _paintAnisotropicSpecularBeam(canvas, viewportRect, snapshot.foilState);
    _paintCollectorSparkles(canvas, viewportRect, snapshot.foilState);
    _paintCollectorMetallicFrame(canvas, viewportRect, snapshot.foilState);

    canvas.restore();

    // Layer 4: Smooth zero-saveLayer entrance fade from pure black (#000000).
    final double rawProgress = snapshot.transitionProgress.clamp(0.0, 1.0);
    if (rawProgress < 0.9999) {
      final double easedOpacity = Curves.easeInOutCubic.transform(rawProgress);
      final double blackVeilAlpha = (1.0 - easedOpacity).clamp(0.0, 1.0);
      if (blackVeilAlpha > 0.0005) {
        _fadeVeilPaint.color = Color.fromRGBO(0, 0, 0, blackVeilAlpha);
        canvas.drawRect(viewportRect, _fadeVeilPaint);
      }
    }
  }

  void _paintLenticularTriad(
    Canvas canvas,
    Rect targetRect,
    LenticularBlendWeights weights,
  ) {
    final GoldCardSprites? loadedSprites = sprites;
    if (loadedSprites != null && loadedSprites.isLoaded) {
      final ui.Image front = loadedSprites.frontImage!;
      final ui.Image left = loadedSprites.leftImage!;
      final ui.Image right = loadedSprites.rightImage!;

      // Always draw Front.png at opaque base so Porter-Duff srcOver yields exact
      // energy-preserving linear interpolation: s * Side + (1 - s) * Front.
      _drawCoverImage(canvas, front, targetRect, _baseSpritePaint);

      if (weights.leftWeight > 0.001) {
        _overlaySpritePaint.color = Color.fromRGBO(
          255,
          255,
          255,
          weights.leftWeight.clamp(0.0, 1.0),
        );
        _drawCoverImage(canvas, left, targetRect, _overlaySpritePaint);
      }

      if (weights.rightWeight > 0.001) {
        _overlaySpritePaint.color = Color.fromRGBO(
          255,
          255,
          255,
          weights.rightWeight.clamp(0.0, 1.0),
        );
        _drawCoverImage(canvas, right, targetRect, _overlaySpritePaint);
      }
      return;
    }

    // Clean procedural collector fallback when executed in synchronous unit tests
    // prior to async asset codec completion.
    _paintProceduralFallbackTriad(canvas, targetRect, weights);
  }

  void _drawCoverImage(
    Canvas canvas,
    ui.Image image,
    Rect dstRect,
    Paint paint,
  ) {
    // Inset by 1.5 source pixels to trim any 1px border artifact on source scans
    // while keeping Left/Front/Right 100% pixel-registered.
    const double trim = 1.5;
    final double fullW = image.width.toDouble();
    final double fullH = image.height.toDouble();
    final Size trimmedSize = Size(
      math.max(1.0, fullW - trim * 2.0),
      math.max(1.0, fullH - trim * 2.0),
    );

    final FittedSizes fitted = applyBoxFit(
      BoxFit.cover,
      trimmedSize,
      dstRect.size,
    );
    final Rect alignedSrcSubrect = Alignment.center.inscribe(
      fitted.source,
      Rect.fromLTWH(trim, trim, trimmedSize.width, trimmedSize.height),
    );
    final Rect alignedDstRect = Alignment.center.inscribe(
      fitted.destination,
      dstRect,
    );

    canvas.drawImageRect(image, alignedSrcSubrect, alignedDstRect, paint);
  }

  void _paintProceduralFallbackTriad(
    Canvas canvas,
    Rect rect,
    LenticularBlendWeights weights,
  ) {
    // Base Front (clean office portrait tones).
    _paintFallbackPortraitCard(
      canvas,
      rect,
      opacity: 1.0,
      bgTop: const Color(0xFF42526B),
      bgBottom: const Color(0xFF1E293B),
      skinColor: const Color(0xFFE0B194),
      shirtColor: const Color(0xFFB8CEEA),
      hasMustache: false,
      isCartoon: false,
    );

    if (weights.leftWeight > 0.001) {
      _paintFallbackPortraitCard(
        canvas,
        rect,
        opacity: weights.leftWeight.clamp(0.0, 1.0),
        bgTop: const Color(0xFF475569),
        bgBottom: const Color(0xFF1E293B),
        skinColor: const Color(0xFFDDA98C),
        shirtColor: const Color(0xFFBDD2EE),
        hasMustache: true,
        isCartoon: false,
      );
    }

    if (weights.rightWeight > 0.001) {
      _paintFallbackPortraitCard(
        canvas,
        rect,
        opacity: weights.rightWeight.clamp(0.0, 1.0),
        bgTop: const Color(0xFF6B705C),
        bgBottom: const Color(0xFF334155),
        skinColor: const Color(0xFFFACC15),
        shirtColor: const Color(0xFF93C5FD),
        hasMustache: true,
        isCartoon: true,
      );
    }
  }

  void _paintFallbackPortraitCard(
    Canvas canvas,
    Rect rect, {
    required double opacity,
    required Color bgTop,
    required Color bgBottom,
    required Color skinColor,
    required Color shirtColor,
    required bool hasMustache,
    required bool isCartoon,
  }) {
    final Paint fill = Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        <Color>[
          bgTop.withValues(alpha: opacity),
          bgBottom.withValues(alpha: opacity),
        ],
      );
    canvas.drawRect(rect, fill);

    final Offset portraitCenter = Offset(
      rect.left + rect.width * 0.64,
      rect.top + rect.height * 0.46,
    );
    final double headRadius = rect.height * 0.22;

    // Shoulders
    final Paint shirtPaint = Paint()
      ..color = shirtColor.withValues(alpha: opacity);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(portraitCenter.dx, rect.bottom - rect.height * 0.06),
        width: headRadius * 3.4,
        height: headRadius * 2.1,
      ),
      shirtPaint,
    );

    // Head
    final Paint skinPaint = Paint()
      ..color = skinColor.withValues(alpha: opacity);
    canvas.drawOval(
      Rect.fromCenter(
        center: portraitCenter,
        width: headRadius * 1.55,
        height: headRadius * 1.95,
      ),
      skinPaint,
    );

    if (isCartoon) {
      final Paint eyeWhite = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity);
      canvas.drawCircle(
        portraitCenter.translate(-headRadius * 0.26, -headRadius * 0.1),
        headRadius * 0.24,
        eyeWhite,
      );
      canvas.drawCircle(
        portraitCenter.translate(headRadius * 0.26, -headRadius * 0.1),
        headRadius * 0.24,
        eyeWhite,
      );
    }

    if (hasMustache) {
      final Paint mustachePaint = Paint()
        ..color = const Color(0xFF3E2723).withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: portraitCenter.translate(0.0, headRadius * 0.34),
            width: headRadius * 0.92,
            height: headRadius * 0.28,
          ),
          Radius.circular(headRadius * 0.14),
        ),
        mustachePaint,
      );
    }
  }

  void _paintLenticularMicroPrisms(
    Canvas canvas,
    Rect viewport,
    LenticularBlendWeights weights,
    double horizontalTilt,
  ) {
    const double pitchPx = 4.5;
    final double phaseShift = horizontalTilt * pitchPx * 0.5;
    final double ridgeAlpha =
        (0.032 + 0.045 * weights.transitionActivity).clamp(0.0, 0.10);

    _lenticularPaint.shader = ui.Gradient.linear(
      Offset(phaseShift, 0.0),
      Offset(phaseShift + pitchPx, 0.0),
      <Color>[
        Color.fromRGBO(255, 255, 255, ridgeAlpha),
        const Color.fromRGBO(255, 248, 220, 0.0),
        Color.fromRGBO(0, 0, 0, ridgeAlpha * 0.85),
        Color.fromRGBO(255, 215, 0, ridgeAlpha * 0.55),
      ],
      const <double>[0.0, 0.32, 0.68, 1.0],
      TileMode.repeated,
    );
    canvas.drawRect(viewport, _lenticularPaint);
  }

  void _paintIridescentFoilSurface(
    Canvas canvas,
    Rect viewport,
    IridescentFoilState foil,
  ) {
    final Offset center = viewport.center;
    final double halfSpan = viewport.longestSide * 0.72;
    final double cosA = math.cos(foil.foilAngleRadians);
    final double sinA = math.sin(foil.foilAngleRadians);

    final Offset start = Offset(
      center.dx - cosA * halfSpan,
      center.dy - sinA * halfSpan,
    );
    final Offset end = Offset(
      center.dx + cosA * halfSpan,
      center.dy + sinA * halfSpan,
    );

    final double screenAlpha = (0.11 + 0.15 * foil.sheenIntensity).clamp(
      0.0,
      0.30,
    );
    final double overlayAlpha = (0.09 + 0.13 * foil.sheenIntensity).clamp(
      0.0,
      0.26,
    );

    const int bandCount = 7;
    final List<Color> screenColors = List<Color>.generate(bandCount, (int i) {
      final double wave = foil.iridescentPhase + i * 0.92;
      return _sampleIridescentSpectrum(wave, screenAlpha);
    }, growable: false);

    final List<Color> overlayColors = List<Color>.generate(bandCount, (int i) {
      final double wave = foil.iridescentPhase * 1.15 + i * 1.05 + 0.6;
      return _sampleIridescentSpectrum(wave, overlayAlpha);
    }, growable: false);

    const List<double> stops = <double>[
      0.0,
      0.17,
      0.33,
      0.50,
      0.67,
      0.83,
      1.0,
    ];

    _diffractionScreenPaint.shader = ui.Gradient.linear(
      start,
      end,
      screenColors,
      stops,
    );
    canvas.drawRect(viewport, _diffractionScreenPaint);

    _diffractionOverlayPaint.shader = ui.Gradient.linear(
      end,
      start,
      overlayColors,
      stops,
    );
    canvas.drawRect(viewport, _diffractionOverlayPaint);
  }

  void _paintAnisotropicSpecularBeam(
    Canvas canvas,
    Rect viewport,
    IridescentFoilState foil,
  ) {
    final Offset hotspot = Offset(
      foil.specularCenter.dx * viewport.width,
      foil.specularCenter.dy * viewport.height,
    );

    // Brushed metallic anisotropic band orthogonal to the foil angle, anchored at specularCenter.
    final double normalAngle = foil.foilAngleRadians + math.pi * 0.5;
    final double bandHalfWidth = viewport.shortestSide * 0.34;
    final Offset bandFrom = Offset(
      hotspot.dx - math.cos(normalAngle) * bandHalfWidth,
      hotspot.dy - math.sin(normalAngle) * bandHalfWidth,
    );
    final Offset bandTo = Offset(
      hotspot.dx + math.cos(normalAngle) * bandHalfWidth,
      hotspot.dy + math.sin(normalAngle) * bandHalfWidth,
    );

    final double streakPeakAlpha = (0.08 + 0.16 * foil.sheenIntensity).clamp(
      0.0,
      0.26,
    );
    final Color prismTint = _sampleIridescentSpectrum(
      foil.iridescentPhase + 0.8,
      streakPeakAlpha * 0.72,
    );

    _anisotropicStreakPaint.shader = ui.Gradient.linear(
      bandFrom,
      bandTo,
      <Color>[
        const Color(0x00FFD700),
        Color.fromRGBO(255, 215, 0, streakPeakAlpha * 0.45),
        Color.fromRGBO(255, 249, 214, streakPeakAlpha),
        prismTint,
        const Color(0x0000F0FF),
      ],
      const <double>[0.0, 0.34, 0.50, 0.66, 1.0],
    );
    canvas.drawRect(viewport, _anisotropicStreakPaint);

    // 2D Radial Metallic Collector Hotspot tracking both horizontalTilt & verticalTilt.
    final double radialRadius = viewport.longestSide * 0.48;
    final double hotspotAlpha = (0.10 + 0.17 * foil.sheenIntensity).clamp(
      0.0,
      0.28,
    );
    final Color outerIridescent = _sampleIridescentSpectrum(
      foil.iridescentPhase - 0.5,
      hotspotAlpha * 0.38,
    );

    _specularHotspotPaint.shader = ui.Gradient.radial(
      hotspot,
      radialRadius,
      <Color>[
        Color.fromRGBO(255, 250, 224, hotspotAlpha),
        Color.fromRGBO(255, 215, 0, hotspotAlpha * 0.58),
        outerIridescent,
        const Color(0x00000000),
      ],
      const <double>[0.0, 0.24, 0.58, 1.0],
    );
    canvas.drawRect(viewport, _specularHotspotPaint);
  }

  void _paintCollectorSparkles(
    Canvas canvas,
    Rect viewport,
    IridescentFoilState foil,
  ) {
    final double globalSparkle = foil.sparkleIntensity;
    if (globalSparkle <= 0.02) return;

    final double h = foil.horizontalTilt;
    final double v = foil.verticalTilt;

    for (int i = 0; i < _facetPool.length; i++) {
      final _HolographicFacet facet = _facetPool[i];
      final double dh = h - facet.prefH;
      final double dv = v - facet.prefV;
      final double distSq = dh * dh + dv * dv;

      // Sharp angular resonance when device orientation aligns with this micro-facet's normal.
      final double resonance = math.exp(-distSq * 8.5);
      if (resonance < 0.18) continue;

      final double alpha = (resonance * globalSparkle * 0.78).clamp(0.0, 0.85);
      if (alpha < 0.05) continue;

      final Offset center = Offset(
        facet.nx * viewport.width,
        facet.ny * viewport.height,
      );
      final Color baseColor =
          _foilSpectrumPalette[(facet.colorIndex +
                  (foil.iridescentPhase.abs() * 2.0).floor()) %
              _foilSpectrumPalette.length];

      final double coreRadius = facet.radius * (0.45 + 0.55 * resonance);
      _sparkleFillPaint.color = baseColor.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(center, coreRadius, _sparkleFillPaint);

      _sparkleFillPaint.color = const Color(
        0xFFFFFBEB,
      ).withValues(alpha: alpha * 0.90);
      canvas.drawCircle(center, coreRadius * 0.42, _sparkleFillPaint);

      if (resonance > 0.46) {
        final double rayLen = facet.radius * (1.5 + 1.4 * resonance);
        final double angle =
            facet.rotationOffset + foil.foilAngleRadians * 0.5;
        final double cosR = math.cos(angle);
        final double sinR = math.sin(angle);

        _sparkleRayPaint.color = baseColor.withValues(alpha: alpha * 0.72);
        canvas.drawLine(
          Offset(center.dx - cosR * rayLen, center.dy - sinR * rayLen),
          Offset(center.dx + cosR * rayLen, center.dy + sinR * rayLen),
          _sparkleRayPaint,
        );
        canvas.drawLine(
          Offset(center.dx + sinR * rayLen, center.dy - cosR * rayLen),
          Offset(center.dx - sinR * rayLen, center.dy + cosR * rayLen),
          _sparkleRayPaint,
        );
      }
    }
  }

  void _paintCollectorMetallicFrame(
    Canvas canvas,
    Rect viewport,
    IridescentFoilState foil,
  ) {
    final Rect outerFrame = viewport.deflate(6.0);
    if (outerFrame.width <= 16.0 || outerFrame.height <= 16.0) return;

    final Offset hotspot = Offset(
      foil.specularCenter.dx * viewport.width,
      foil.specularCenter.dy * viewport.height,
    );
    final Offset opposite = Offset(
      viewport.width - hotspot.dx,
      viewport.height - hotspot.dy,
    );

    final double rimAlpha = (0.45 + 0.45 * foil.sheenIntensity).clamp(
      0.0,
      0.92,
    );

    _outerRimPaint.shader = ui.Gradient.linear(
      hotspot,
      opposite,
      <Color>[
        const Color(0xFFFFF7CC).withValues(alpha: rimAlpha),
        const Color(0xFFFFD700).withValues(alpha: rimAlpha * 0.90),
        _sampleIridescentSpectrum(foil.iridescentPhase + 0.7, rimAlpha * 0.80),
        _sampleIridescentSpectrum(foil.iridescentPhase + 2.3, rimAlpha * 0.75),
        const Color(0xFFFFD700).withValues(alpha: rimAlpha * 0.88),
      ],
      const <double>[0.0, 0.25, 0.52, 0.78, 1.0],
    );

    final RRect outerRRect = RRect.fromRectAndRadius(
      outerFrame,
      const Radius.circular(14.0),
    );
    canvas.drawRRect(outerRRect, _outerRimPaint);

    final Rect innerFrame = outerFrame.deflate(3.5);
    _innerRimPaint.color = const Color(
      0xFFFFF3B0,
    ).withValues(alpha: rimAlpha * 0.32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerFrame, const Radius.circular(11.0)),
      _innerRimPaint,
    );
  }

  static Color _sampleIridescentSpectrum(double phase, double alpha) {
    final double clampedAlpha = alpha.clamp(0.0, 1.0);
    final int len = _foilSpectrumPalette.length;
    final double wrapped = ((phase % len) + len) % len;
    final int idx0 = wrapped.floor() % len;
    final int idx1 = (idx0 + 1) % len;
    final double frac = wrapped - wrapped.floorToDouble();
    final Color blended =
        Color.lerp(_foilSpectrumPalette[idx0], _foilSpectrumPalette[idx1], frac) ??
        _foilSpectrumPalette[0];
    return blended.withValues(alpha: clampedAlpha);
  }

  @override
  bool shouldRepaint(covariant GoldCardLenticularPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot || oldDelegate.sprites != sprites;
  }
}
