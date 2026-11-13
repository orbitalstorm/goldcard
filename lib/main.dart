import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'engine/gold_card_engine.dart';
import 'models/gold_card_models.dart';
import 'painters/gold_card_lenticular_painter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const GoldCardApp());
}

/// Root GoldCard v1.0.0 application locked to immersive full-screen Landscape.
class GoldCardApp extends StatelessWidget {
  const GoldCardApp({
    super.key,
    this.engine,
    this.sprites,
  });

  final GoldCardEngine? engine;
  final GoldCardSprites? sprites;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoldCard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
      ),
      home: GoldCardExperiencePage(
        engine: engine,
        sprites: sprites,
      ),
    );
  }
}

/// Full-screen landscape collector card experience (`v1.0.0`).
class GoldCardExperiencePage extends StatefulWidget {
  const GoldCardExperiencePage({
    super.key,
    this.engine,
    this.sprites,
  });

  final GoldCardEngine? engine;
  final GoldCardSprites? sprites;

  @override
  State<GoldCardExperiencePage> createState() => _GoldCardExperiencePageState();
}

class _GoldCardExperiencePageState extends State<GoldCardExperiencePage>
    with SingleTickerProviderStateMixin {
  late GoldCardEngine _engine;
  bool _ownsEngine = false;
  GoldCardSprites? _sprites;
  late final Ticker _ticker;
  Duration? _lastTickElapsed;

  @override
  void initState() {
    super.initState();
    if (widget.engine != null) {
      _engine = widget.engine!;
      _ownsEngine = false;
    } else {
      _engine = GoldCardEngine();
      _ownsEngine = true;
    }
    _sprites = widget.sprites;

    _ticker = createTicker(_onTick);
    _engine.addListener(_onEngineChanged);
    _syncTickerState();

    if (_sprites == null) {
      unawaited(_loadSprites());
    }
  }

  @override
  void didUpdateWidget(covariant GoldCardExperiencePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engine != oldWidget.engine) {
      _engine.removeListener(_onEngineChanged);
      if (_ownsEngine) {
        _engine.dispose();
      }
      if (widget.engine != null) {
        _engine = widget.engine!;
        _ownsEngine = false;
      } else {
        _engine = GoldCardEngine();
        _ownsEngine = true;
      }
      _engine.addListener(_onEngineChanged);
      _syncTickerState();
    }
    if (widget.sprites != oldWidget.sprites && widget.sprites != null) {
      setState(() {
        _sprites = widget.sprites;
      });
    }
  }

  Future<void> _loadSprites() async {
    final GoldCardSprites loaded = await GoldCardSprites.load();
    if (!mounted) return;
    setState(() {
      _sprites = loaded;
    });
  }

  void _onEngineChanged() {
    _syncTickerState();
  }

  void _syncTickerState() {
    if (!mounted) return;
    if (_engine.hasPendingMotion) {
      if (!_ticker.isActive) {
        _lastTickElapsed = Duration.zero;
        unawaited(_ticker.start());
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
    }
  }

  void _onTick(Duration elapsed) {
    final Duration previous = _lastTickElapsed ?? Duration.zero;
    _lastTickElapsed = elapsed;
    final double dt =
        (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt > 0.0) {
      _engine.step(dt);
    }
    if (!_engine.hasPendingMotion && _ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
    }
  }

  void _handlePressReady() {
    unawaited(HapticFeedback.mediumImpact());
    _engine.pressReady();
    _syncTickerState();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size viewportSize) {
    if (_engine.phase == CardAppPhase.waitingReady) return;
    if (viewportSize.width <= 0.0 || viewportSize.height <= 0.0) return;

    final double nextH =
        (_engine.horizontalTilt +
                (details.delta.dx / (viewportSize.width * 0.36)))
            .clamp(-1.0, 1.0);
    final double nextV =
        (_engine.verticalTilt +
                (details.delta.dy / (viewportSize.height * 0.36)))
            .clamp(-1.0, 1.0);

    _engine.setManualTilt(
      horizontalTilt: nextH,
      verticalTilt: nextV,
    );
    _syncTickerState();
  }

  void _handleRecalibrate() {
    if (_engine.phase == CardAppPhase.waitingReady) return;
    unawaited(HapticFeedback.lightImpact());
    _engine.calibrateZeroPoint();
    _syncTickerState();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _ticker.dispose();
    if (_ownsEngine) {
      _engine.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('gold_card_capture_boundary'),
      child: Scaffold(
        key: const Key('gold_card_root_scaffold'),
        backgroundColor: const Color(0xFF000000),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size viewportSize = constraints.biggest;
            return ListenableBuilder(
              listenable: _engine,
              builder: (BuildContext context, Widget? _) {
                final GoldCardSnapshot snapshot = _engine.snapshot;
                final double rawProgress = snapshot.transitionProgress.clamp(
                  0.0,
                  1.0,
                );
                final double easedFadeIn = Curves.easeInOutCubic.transform(
                  rawProgress,
                );
                final double fadeOutReady = (1.0 - easedFadeIn).clamp(0.0, 1.0);

                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (snapshot.phase != CardAppPhase.waitingReady)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (DragUpdateDetails details) =>
                            _handlePanUpdate(details, viewportSize),
                        onDoubleTap: _handleRecalibrate,
                        onLongPress: _handleRecalibrate,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const Key('lenticular_composition_view'),
                            size: viewportSize,
                            painter: GoldCardLenticularPainter(
                              snapshot: snapshot,
                              sprites: _sprites,
                            ),
                          ),
                        ),
                      ),
                    if (snapshot.phase != CardAppPhase.activeComposition)
                      IgnorePointer(
                        ignoring: snapshot.phase != CardAppPhase.waitingReady,
                        child: FadeTransition(
                          opacity: AlwaysStoppedAnimation<double>(fadeOutReady),
                          child: ColoredBox(
                            key: const Key('ready_black_screen'),
                            color: const Color(0xFF000000),
                            child: SafeArea(
                              child: Center(
                                child: RepaintBoundary(
                                  child: _ReadyFloatingCollectorButton(
                                    isInteractive:
                                        snapshot.phase ==
                                        CardAppPhase.waitingReady,
                                    onActivated: _handlePressReady,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Floating `"ready"` button with collector Game Juice:
/// - Sinusoidal vertical levitation (`+-4.5 dp`),
/// - Gliding metallic iridescent holographic rim & diagonal sheen sweep,
/// - 3D physical lower lip (`lipDepth: 6.0`) that compresses on contact,
/// - Immediate tactile Squash & Stretch (`AnimatedScale` `0.92` in `75 ms`, `Curves.easeOutCubic`),
/// - Native haptic feedback (`HapticFeedback.lightImpact` on press, `mediumImpact` on trigger).
class _ReadyFloatingCollectorButton extends StatefulWidget {
  const _ReadyFloatingCollectorButton({
    required this.isInteractive,
    required this.onActivated,
  });

  final bool isInteractive;
  final VoidCallback onActivated;

  @override
  State<_ReadyFloatingCollectorButton> createState() =>
      _ReadyFloatingCollectorButtonState();
}

class _ReadyFloatingCollectorButtonState
    extends State<_ReadyFloatingCollectorButton>
    with SingleTickerProviderStateMixin {
  static const double _lipDepth = 6.0;
  static const double _levitationAmplitude = 4.5;

  late final AnimationController _ambientController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.isInteractive) {
      unawaited(_ambientController.repeat());
    }
  }

  @override
  void didUpdateWidget(covariant _ReadyFloatingCollectorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isInteractive != oldWidget.isInteractive) {
      if (widget.isInteractive) {
        unawaited(_ambientController.repeat());
      } else {
        _ambientController.stop();
      }
    }
  }

  void _handleTapDown(TapDownDetails _) {
    if (!widget.isInteractive) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _isPressed = true;
    });
  }

  void _handleTapCancel() {
    if (!_isPressed) return;
    setState(() {
      _isPressed = false;
    });
  }

  void _handleTapUp(TapUpDetails _) {
    if (!widget.isInteractive) return;
    setState(() {
      _isPressed = false;
    });
    _ambientController.stop();
    widget.onActivated();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('ready_floating_button'),
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapCancel: _handleTapCancel,
      onTapUp: _handleTapUp,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 184.0, minHeight: 58.0),
        child: AnimatedBuilder(
          animation: _ambientController,
          builder: (BuildContext context, Widget? child) {
            final double phase = _ambientController.value;
            final double floatOffsetY = _isPressed
                ? 0.0
                : math.sin(phase * 2.0 * math.pi) * _levitationAmplitude;
            final double haloPulse =
                0.5 + 0.5 * math.cos(phase * 2.0 * math.pi);

            return Transform.translate(
              offset: Offset(0.0, floatOffsetY),
              child: AnimatedScale(
                key: const Key('ready_button_scale'),
                scale: _isPressed ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 75),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 75),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    0.0,
                    _isPressed ? _lipDepth : 0.0,
                    0.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999.0),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFFFFF6C2),
                        Color(0xFFFFD700),
                        Color(0xFFE6A817),
                        Color(0xFFC8860A),
                      ],
                      stops: <double>[0.0, 0.38, 0.76, 1.0],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFF784B04),
                        blurRadius: 0.0,
                        offset: Offset(0.0, _isPressed ? 0.0 : _lipDepth),
                      ),
                      BoxShadow(
                        color: Color.fromRGBO(
                          255,
                          215,
                          0,
                          _isPressed ? 0.24 : (0.30 + 0.14 * haloPulse),
                        ),
                        blurRadius: _isPressed ? 14.0 : 28.0,
                        spreadRadius: _isPressed ? 0.0 : 1.5,
                      ),
                      BoxShadow(
                        color: Color.fromRGBO(
                          0,
                          240,
                          255,
                          _isPressed ? 0.10 : (0.12 + 0.08 * (1.0 - haloPulse)),
                        ),
                        blurRadius: 34.0,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    foregroundPainter: _ReadyButtonIridescentPainter(
                      shimmerPhase: phase,
                      isPressed: _isPressed,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 42.0,
                        vertical: 16.0,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
          child: const Text(
            'ready',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              color: Color(0xFF1A1100),
              fontSize: 19.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.6,
              shadows: <Shadow>[
                Shadow(
                  color: Color(0x99FFFBE6),
                  offset: Offset(0.0, 1.0),
                  blurRadius: 0.0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the gliding holographic metallic iridescent rim and specular sheen
/// across the `"ready"` collector capsule button.
class _ReadyButtonIridescentPainter extends CustomPainter {
  const _ReadyButtonIridescentPainter({
    required this.shimmerPhase,
    required this.isPressed,
  });

  final double shimmerPhase;
  final bool isPressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect rect = Offset.zero & size;
    final RRect capsuleRRect = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      Radius.circular(size.height * 0.5),
    );

    // 1. Soft diagonal metallic sheen sweeping across the capsule face.
    canvas.save();
    canvas.clipRRect(capsuleRRect);
    final double sweepNormalized = ((shimmerPhase + 0.28) % 1.0) * 2.2 - 0.6;
    final Offset sheenCenter = Offset(
      size.width * sweepNormalized,
      size.height * 0.5,
    );
    final Paint sheenPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.linear(
        sheenCenter.translate(-size.width * 0.28, -size.height * 0.6),
        sheenCenter.translate(size.width * 0.28, size.height * 0.6),
        const <Color>[
          Color(0x00FFFFFF),
          Color(0x38FFF8D6),
          Color(0x70FFFFFF),
          Color(0x3800F0FF),
          Color(0x00FFFFFF),
        ],
        const <double>[0.0, 0.35, 0.50, 0.65, 1.0],
      );
    canvas.drawRect(rect, sheenPaint);
    canvas.restore();

    // 2. Outer holographic iridescent collector border gliding around the rim.
    final double angle = shimmerPhase * 2.0 * math.pi + 0.45;
    final Offset center = rect.center;
    final double radius = size.longestSide * 0.65;
    final Offset from = Offset(
      center.dx - math.cos(angle) * radius,
      center.dy - math.sin(angle) * radius,
    );
    final Offset to = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );

    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        from,
        to,
        const <Color>[
          Color(0xFFFFFBEB),
          Color(0xFFFFD700),
          Color(0xFFFF4D94),
          Color(0xFF00F0FF),
          Color(0xFF00F5D4),
          Color(0xFFFFF3B0),
        ],
        const <double>[0.0, 0.22, 0.44, 0.66, 0.84, 1.0],
      );
    canvas.drawRRect(capsuleRRect, borderPaint);

    // 3. Inner champagne bevel highlight.
    final RRect innerBevel = capsuleRRect.deflate(2.2);
    final Paint innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..isAntiAlias = true
      ..color = const Color(0x78FFFDF2);
    canvas.drawRRect(innerBevel, innerPaint);

    // 4. Collector star sparkles on top-left and bottom-right rim arcs.
    final Offset topSparkle = Offset(size.width * 0.22, 2.2);
    final Offset bottomSparkle = Offset(size.width * 0.78, size.height - 2.2);
    _drawRimSparkle(canvas, topSparkle, 3.8);
    _drawRimSparkle(canvas, bottomSparkle, 3.2);
  }

  void _drawRimSparkle(Canvas canvas, Offset center, double rayRadius) {
    final Paint rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = const Color(0xDDFFFBEB);
    canvas.drawLine(
      center.translate(-rayRadius, 0.0),
      center.translate(rayRadius, 0.0),
      rayPaint,
    );
    canvas.drawLine(
      center.translate(0.0, -rayRadius),
      center.translate(0.0, rayRadius),
      rayPaint,
    );
    final Paint corePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(center, 1.3, corePaint);
  }

  @override
  bool shouldRepaint(covariant _ReadyButtonIridescentPainter oldDelegate) {
    return oldDelegate.shimmerPhase != shimmerPhase ||
        oldDelegate.isPressed != isPressed;
  }
}
