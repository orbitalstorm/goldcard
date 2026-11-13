import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private let accelerometerChannelName = "cloud.orbital8.gold_card/accelerometer"
  private let deviceChannelName = "cloud.orbital8.gold_card/device"
  private let fullTiltGravityFraction: Double = 0.55

  private let motionManager = CMMotionManager()
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return [.landscapeLeft, .landscapeRight]
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let eventChannel = FlutterEventChannel(
      name: accelerometerChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)

    let deviceChannel = FlutterMethodChannel(
      name: deviceChannelName,
      binaryMessenger: messenger
    )
    deviceChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "hasAccelerometer":
        result(self.motionManager.isAccelerometerAvailable)
      case "lockLandscape":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    guard motionManager.isAccelerometerAvailable else {
      return nil
    }
    motionManager.accelerometerUpdateInterval = 1.0 / 60.0
    motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
      guard let self = self, let accel = data?.acceleration, let sink = self.eventSink else {
        return
      }
      let ax = accel.x
      let ay = accel.y
      let az = accel.z

      let interfaceOrientation = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?
        .interfaceOrientation ?? .landscapeRight

      // Project CoreMotion gravity vector (in G) onto Landscape Screen coordinates:
      // screenHorizontal < 0 when tilted left, > 0 when tilted right.
      let projectedHorizontal: Double
      let projectedVertical: Double
      switch interfaceOrientation {
      case .landscapeLeft:
        projectedHorizontal = ay
        projectedVertical = ax
      case .landscapeRight:
        projectedHorizontal = -ay
        projectedVertical = -ax
      default:
        projectedHorizontal = -ay
        projectedVertical = -ax
      }

      let screenHorizontal = min(max(projectedHorizontal / self.fullTiltGravityFraction, -2.5), 2.5)
      let screenVertical = min(max(projectedVertical / self.fullTiltGravityFraction, -2.5), 2.5)

      sink([
        "x": ax,
        "y": ay,
        "z": az,
        "screenHorizontal": screenHorizontal,
        "screenVertical": screenVertical,
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motionManager.stopAccelerometerUpdates()
    eventSink = nil
    return nil
  }
}
