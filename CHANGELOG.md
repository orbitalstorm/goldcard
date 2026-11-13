# Changelog — GoldCard (`cloud.orbital8.gold_card`)

Toutes les modifications notables de **GoldCard** sont documentées dans ce fichier selon la convention stricte `v1.x.y`.

## `v1.0.0` (`1.0.0+1`) — 2026-11-13

### Fonctionnalités Principales ([ORB-78](/ORB/issues/ORB-78))

- **Mode Plein Écran Immersif & Verrouillage Format Paysage (`Landscape`)** ([ORB-79](/ORB/issues/ORB-79)) :
  - Masquage intégral des barres système (`SystemUiMode.immersiveSticky`, `WindowInsetsController` Android 11+ et `UIStatusBarHidden` iOS).
  - Verrouillage matériel et logiciel en orientation Paysage (`DeviceOrientation.landscapeLeft` / `landscapeRight`, `android:screenOrientation="sensorLandscape"`, `ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE` dans `MainActivity.kt`, et `UIInterfaceOrientationLandscapeLeft` / `Right` dans `AppDelegate.swift` & `Info.plist`).
- **Acquisition Accéléromètre Matériel 60 Hz en Repère Paysage** ([ORB-79](/ORB/issues/ORB-79)) :
  - Canal natif `cloud.orbital8.gold_card/accelerometer` (`EventChannel`) et `cloud.orbital8.gold_card/device` (`MethodChannel`).
  - Projection géométrique temps réel du vecteur d'accélération dans le repère de l'écran Paysage (`screenHorizontal`, `screenVertical`) tenant compte de l'orientation physique (`ROTATION_90` / `ROTATION_270` sur Android, `.landscapeLeft` / `.landscapeRight` sur iOS).
  - Filtre passe-bas exponentiel (`1 - exp(-dt * 14.0)`) et zone morte douce (`softDeadzone = 0.025`) éliminant les micro-tremblements de la main.
- **Écran d'Accueil Noir Pur (`#000000`) & Bouton Flottant `"ready"` à *Game Juice*** ([ORB-80](/ORB/issues/ORB-80)) :
  - Écran initial noir absolu (`#000000`, `Key('ready_black_screen')`) centré sur le bouton flottant `"ready"` (`Key('ready_floating_button')`).
  - Lévitation verticale sinusoïdale (`±4.5 dp`), liseré holographique irisé animé, biseau physique 3D (`lipDepth: 6.0`), *Squash & Stretch* tactile immédiat (`AnimatedScale` à `0.92` en `75 ms`) et retour haptique natif (`HapticFeedback.lightImpact()` / `mediumImpact()`).
- **Calibration Point Zéro & Fondu Fluide vers la Composition** ([ORB-79](/ORB/issues/ORB-79), [ORB-80](/ORB/issues/ORB-80)) :
  - Capture instantanée de la posture courante du téléphone comme point de référence `(0, 0)` (`calibrateZeroPoint()`) lors de l'appui sur `"ready"`.
  - Transition en fondu progressif (`0.85 s`, courbe `Curves.easeInOutCubic`, sans `saveLayer` coûteux) vers la composition lenticulaire plein écran (`Key('lenticular_composition_view')`).
  - Fallback tactile glissé (`onPanUpdate`) et recalibration rapide du point zéro par double-tap ou appui long.
- **Composition Lenticulaire 3 Images (`Left.png`, `Front.png`, `Right.png`) — Axe Horizontal Exclusif** ([ORB-79](/ORB/issues/ORB-79)) :
  - Interpolation *smoothstep* ($3t^2 - 2t^3$) à conservation d'énergie ($w_{\text{left}} + w_{\text{front}} + w_{\text{right}} = 1.0$) gouvernée **exclusivement par l'inclinaison horizontale (`horizontalTilt`)** :
    - `horizontalTilt < 0` : fondu de `Front.png` vers `Left.png` (portrait photo bureau avec moustache).
    - `horizontalTilt == 0` : `100 %` `Front.png` (portrait photo bureau sans moustache).
    - `horizontalTilt > 0` : fondu de `Front.png` vers `Right.png` (portrait cartoon style Simpsons avec moustache).
  - Invariance mathématique stricte (`0.0` impact) sous inclinaison verticale (`verticalTilt`).
- **Effet Brillant Métallique Irisé de Carte Collector — Axes Horizontal ET Vertical** ([ORB-79](/ORB/issues/ORB-79)) :
  - Revêtement holographique multi-bandes (Or 24K `#FFD700`, Champagne `#FFF3B0`, Rose Holographique `#FF4D94`, Cyan Électrique `#00F0FF`, Violet Prisme `#9D4EDD`, Émeraude `#00F5D4`) piloté simultanément par `horizontalTilt` et `verticalTilt`.
  - Faisceau spéculaire anisotrope d'or brossé, point chaud spéculaire 2D (`specularCenter`), réseau de micro-prismes lenticulaires verticaux et 72 micro-paillettes collector pré-allouées à résonance angulaire 2D.
