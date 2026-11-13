import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_card/engine/gold_card_engine.dart';
import 'package:gold_card/main.dart';
import 'package:gold_card/models/gold_card_models.dart';
import 'package:gold_card/painters/gold_card_lenticular_painter.dart';

Future<void> _loadRobotoFontIfAvailable() async {
  const List<String> fontPaths = <String>[
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf',
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf',
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf',
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  ];
  final FontLoader loader = FontLoader('Roboto');
  bool anyLoaded = false;
  for (final String path in fontPaths) {
    final File file = File(path);
    if (file.existsSync()) {
      final Uint8List bytes = await file.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      anyLoaded = true;
    }
  }
  if (anyLoaded) {
    await loader.load();
  }
}

Future<void> _captureLandscapeScreenshot(
  WidgetTester tester,
  String relativePath,
) async {
  await tester.pump();
  final Finder boundaryFinder = find.byKey(
    const Key('gold_card_capture_boundary'),
  );
  expect(boundaryFinder, findsOneWidget);
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(boundaryFinder);

  final Uint8List? pngBytes = await tester.runAsync<Uint8List?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    expect(image.width, 1017);
    expect(image.height, 517);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return byteData?.buffer.asUint8List();
  });

  expect(pngBytes, isNotNull);
  expect(pngBytes!.length, greaterThan(1024));

  final File outputFile = File(relativePath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(pngBytes, flush: true);
  expect(outputFile.existsSync(), isTrue);
}

void main() {
  group('GoldCardEngine — Optical & Sensor Invariants', () {
    test(
      'computeLenticularWeights blends Left / Front / Right exclusively on horizontal axis',
      () {
        final LenticularBlendWeights fullLeft =
            GoldCardEngine.computeLenticularWeights(-1.0);
        expect(fullLeft.leftWeight, closeTo(1.0, 1e-9));
        expect(fullLeft.frontWeight, closeTo(0.0, 1e-9));
        expect(fullLeft.rightWeight, closeTo(0.0, 1e-9));
        expect(fullLeft.dominantLayer, 'LEFT');

        final LenticularBlendWeights midLeft =
            GoldCardEngine.computeLenticularWeights(-0.5);
        expect(midLeft.leftWeight, closeTo(0.5, 1e-9));
        expect(midLeft.frontWeight, closeTo(0.5, 1e-9));
        expect(midLeft.rightWeight, closeTo(0.0, 1e-9));
        expect(midLeft.totalWeight, closeTo(1.0, 1e-9));

        final LenticularBlendWeights center =
            GoldCardEngine.computeLenticularWeights(0.0);
        expect(center.leftWeight, closeTo(0.0, 1e-9));
        expect(center.frontWeight, closeTo(1.0, 1e-9));
        expect(center.rightWeight, closeTo(0.0, 1e-9));
        expect(center.dominantLayer, 'FRONT');

        final LenticularBlendWeights midRight =
            GoldCardEngine.computeLenticularWeights(0.5);
        expect(midRight.leftWeight, closeTo(0.0, 1e-9));
        expect(midRight.frontWeight, closeTo(0.5, 1e-9));
        expect(midRight.rightWeight, closeTo(0.5, 1e-9));
        expect(midRight.totalWeight, closeTo(1.0, 1e-9));

        final LenticularBlendWeights fullRight =
            GoldCardEngine.computeLenticularWeights(1.0);
        expect(fullRight.leftWeight, closeTo(0.0, 1e-9));
        expect(fullRight.frontWeight, closeTo(0.0, 1e-9));
        expect(fullRight.rightWeight, closeTo(1.0, 1e-9));
        expect(fullRight.dominantLayer, 'RIGHT');
      },
    );

    test(
      'verticalTilt has strictly ZERO impact on 3-image lenticular blendWeights',
      () {
        final GoldCardEngine engine = GoldCardEngine(
          attachPlatformChannels: false,
        );
        addTearDown(engine.dispose);

        engine.pressReady();
        engine.step(1.0);

        for (final double fixedH in <double>[
          -1.0,
          -0.65,
          -0.5,
          -0.25,
          0.0,
          0.4,
          0.5,
          1.0,
        ]) {
          engine.setManualTilt(
            horizontalTilt: fixedH,
            verticalTilt: -1.0,
            immediate: true,
          );
          final LenticularBlendWeights baseline = engine.blendWeights;

          for (final double v in <double>[
            -1.0,
            -0.75,
            -0.3,
            0.0,
            0.35,
            0.8,
            1.0,
          ]) {
            engine.setManualTilt(
              horizontalTilt: fixedH,
              verticalTilt: v,
              immediate: true,
            );
            expect(engine.blendWeights.leftWeight, equals(baseline.leftWeight));
            expect(
              engine.blendWeights.frontWeight,
              equals(baseline.frontWeight),
            );
            expect(
              engine.blendWeights.rightWeight,
              equals(baseline.rightWeight),
            );
          }
        }
      },
    );

    test(
      'IridescentFoilState responds to BOTH horizontalTilt and verticalTilt',
      () {
        final IridescentFoilState hNeg =
            GoldCardEngine.computeIridescentFoilState(
              horizontalTilt: -0.6,
              verticalTilt: 0.0,
            );
        final IridescentFoilState hPos =
            GoldCardEngine.computeIridescentFoilState(
              horizontalTilt: 0.6,
              verticalTilt: 0.0,
            );
        expect(hPos.specularCenter.dx, greaterThan(hNeg.specularCenter.dx));
        expect(hPos.iridescentPhase, isNot(equals(hNeg.iridescentPhase)));
        expect(hPos.foilAngleRadians, isNot(equals(hNeg.foilAngleRadians)));

        final IridescentFoilState vNeg =
            GoldCardEngine.computeIridescentFoilState(
              horizontalTilt: 0.0,
              verticalTilt: -0.6,
            );
        final IridescentFoilState vPos =
            GoldCardEngine.computeIridescentFoilState(
              horizontalTilt: 0.0,
              verticalTilt: 0.6,
            );
        expect(vPos.specularCenter.dy, greaterThan(vNeg.specularCenter.dy));
        expect(vPos.iridescentPhase, isNot(equals(vNeg.iridescentPhase)));
        expect(vPos.foilAngleRadians, isNot(equals(vNeg.foilAngleRadians)));
      },
    );

    test(
      'pressReady calibrates accelerometer zero point and advances 0.85 s fade',
      () {
        final GoldCardEngine engine = GoldCardEngine(
          attachPlatformChannels: false,
        );
        addTearDown(engine.dispose);

        engine.updateHardwareAccelerometer(
          screenHorizontal: 0.22,
          screenVertical: 0.48,
        );
        expect(engine.phase, CardAppPhase.waitingReady);
        expect(engine.hasHardwareAccelerometer, isTrue);

        engine.pressReady();
        expect(engine.phase, CardAppPhase.fadingIn);
        expect(engine.isCalibrated, isTrue);
        expect(engine.transitionProgress, equals(0.0));
        expect(engine.horizontalTilt, equals(0.0));
        expect(engine.verticalTilt, equals(0.0));
        expect(engine.blendWeights.frontWeight, equals(1.0));

        // Micro-tremor inside softDeadzone (0.025) around calibrated zero stays at 0.0.
        engine.updateHardwareAccelerometer(
          screenHorizontal: 0.22 + 0.015,
          screenVertical: 0.48 - 0.012,
        );
        engine.step(0.425);
        expect(engine.phase, CardAppPhase.fadingIn);
        expect(engine.transitionProgress, closeTo(0.5, 1e-6));
        expect(engine.horizontalTilt, equals(0.0));
        expect(engine.verticalTilt, equals(0.0));

        // Complete the 0.85 s fade-in.
        engine.step(0.45);
        expect(engine.phase, CardAppPhase.activeComposition);
        expect(engine.transitionProgress, equals(1.0));
      },
    );
  });

  group('GoldCardApp — Full-Screen Landscape UI, Game Juice & Screenshots', () {
    testWidgets(
      'verifies black ready screen, tactile Squash & Stretch, smooth fade-in, 3-image horizontal blend, 2D foil & generates 5 landscape screenshots',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1017, 517));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.runAsync(() async {
          await _loadRobotoFontIfAvailable();
        });

        final GoldCardSprites? decodedSprites = await tester.runAsync(
          () => GoldCardSprites.load(),
        );
        expect(decodedSprites, isNotNull);
        expect(decodedSprites!.isLoaded, isTrue);
        expect(decodedSprites.leftImage!.width, 1017);
        expect(decodedSprites.leftImage!.height, 517);
        expect(decodedSprites.frontImage!.width, 1017);
        expect(decodedSprites.frontImage!.height, 517);
        expect(decodedSprites.rightImage!.width, 1017);
        expect(decodedSprites.rightImage!.height, 517);

        final GoldCardEngine engine = GoldCardEngine(
          attachPlatformChannels: false,
        );
        addTearDown(engine.dispose);

        await tester.pumpWidget(
          GoldCardApp(
            engine: engine,
            sprites: decodedSprites,
          ),
        );

        // 1. Verify initial pure black screen (#000000) & floating "ready" button.
        final Scaffold scaffold = tester.widget<Scaffold>(
          find.byKey(const Key('gold_card_root_scaffold')),
        );
        expect(scaffold.backgroundColor, equals(const Color(0xFF000000)));
        expect(find.byKey(const Key('ready_black_screen')), findsOneWidget);

        final Finder readyBtnFinder = find.byKey(
          const Key('ready_floating_button'),
        );
        expect(readyBtnFinder, findsOneWidget);
        expect(find.text('ready'), findsOneWidget);
        expect(
          find.byKey(const Key('lenticular_composition_view')),
          findsNothing,
        );
        expect(engine.phase, CardAppPhase.waitingReady);
        expect(engine.transitionProgress, equals(0.0));

        // Verify ergonomic touch target (>= 48x48dp).
        final Size buttonSize = tester.getSize(readyBtnFinder);
        expect(buttonSize.width, greaterThanOrEqualTo(48.0));
        expect(buttonSize.height, greaterThanOrEqualTo(48.0));

        // Advance sinusoidal levitation & iridescent shimmer slightly and capture Screenshot 01.
        await tester.pump(const Duration(milliseconds: 325));
        await _captureLandscapeScreenshot(
          tester,
          'screenshots/01_ready_black_screen.png',
        );

        // Verify Tactile Squash & Stretch (scale -> 0.92 on tapDown).
        final TestGesture pressGesture = await tester.startGesture(
          tester.getCenter(readyBtnFinder),
        );
        await tester.pump(const Duration(milliseconds: 40));
        final AnimatedScale scaleDownWidget = tester.widget<AnimatedScale>(
          find.byKey(const Key('ready_button_scale')),
        );
        expect(scaleDownWidget.scale, closeTo(0.92, 1e-6));

        // Release tap -> triggers pressReady() and starts 0.85 s fade-in.
        await pressGesture.up();
        await tester.pump();
        expect(engine.phase, CardAppPhase.fadingIn);
        expect(
          find.byKey(const Key('lenticular_composition_view')),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 425));
        expect(engine.transitionProgress, greaterThan(0.2));
        expect(engine.transitionProgress, lessThan(1.0));

        await tester.pumpAndSettle();
        expect(engine.phase, CardAppPhase.activeComposition);
        expect(engine.transitionProgress, equals(1.0));
        expect(find.byKey(const Key('ready_black_screen')), findsNothing);
        expect(
          find.byKey(const Key('lenticular_composition_view')),
          findsOneWidget,
        );

        // 2. Center posture (horizontalTilt = 0.0, verticalTilt = 0.0) -> Front.png + centered foil.
        engine.setManualTilt(
          horizontalTilt: 0.0,
          verticalTilt: 0.0,
          immediate: true,
        );
        expect(engine.blendWeights.leftWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.frontWeight, closeTo(1.0, 1e-9));
        expect(engine.blendWeights.rightWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.dominantLayer, 'FRONT');
        await _captureLandscapeScreenshot(
          tester,
          'screenshots/02_composition_front_center.png',
        );

        // 3. Left horizontal tilt (horizontalTilt = -1.0) -> Left.png (mustache) + left iridescent sheen.
        engine.setManualTilt(
          horizontalTilt: -1.0,
          verticalTilt: -0.25,
          immediate: true,
        );
        expect(engine.blendWeights.leftWeight, closeTo(1.0, 1e-9));
        expect(engine.blendWeights.frontWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.rightWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.dominantLayer, 'LEFT');
        await _captureLandscapeScreenshot(
          tester,
          'screenshots/03_composition_left_tilt.png',
        );

        // 4. Right horizontal tilt (horizontalTilt = +1.0) -> Right.png (Simpsons cartoon) + right iridescent sheen.
        engine.setManualTilt(
          horizontalTilt: 1.0,
          verticalTilt: 0.30,
          immediate: true,
        );
        expect(engine.blendWeights.leftWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.frontWeight, closeTo(0.0, 1e-9));
        expect(engine.blendWeights.rightWeight, closeTo(1.0, 1e-9));
        expect(engine.blendWeights.dominantLayer, 'RIGHT');
        await _captureLandscapeScreenshot(
          tester,
          'screenshots/04_composition_right_tilt.png',
        );

        // 5. Intermediate horizontal blend + strong vertical tilt accentuating 2D metallic iridescence.
        engine.setManualTilt(
          horizontalTilt: 0.48,
          verticalTilt: -0.82,
          immediate: true,
        );
        expect(engine.blendWeights.frontWeight, greaterThan(0.45));
        expect(engine.blendWeights.rightWeight, greaterThan(0.40));
        expect(engine.blendWeights.leftWeight, equals(0.0));
        await _captureLandscapeScreenshot(
          tester,
          'screenshots/05_composition_blend_and_vertical_iridescence.png',
        );

        // Verify touch drag fallback (onPanUpdate) & double-tap recalibration.
        await tester.drag(
          find.byKey(const Key('lenticular_composition_view')),
          const Offset(-160.0, 80.0),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(engine.horizontalTilt, isNot(equals(0.0)));

        // Double-tap recalibrates zero point back to (0, 0).
        await tester.tap(find.byKey(const Key('lenticular_composition_view')));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('lenticular_composition_view')));
        await tester.pumpAndSettle();
        expect(engine.horizontalTilt, equals(0.0));
        expect(engine.verticalTilt, equals(0.0));
        expect(engine.blendWeights.frontWeight, equals(1.0));
      },
    );
  });
}
