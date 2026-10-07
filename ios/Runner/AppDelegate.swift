import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Mirror the Android platform channel so the shared Dart code works unchanged.
    //
    // Android implements a real device-owner kiosk here (lock task, persistent
    // HOME, keyguard off) plus QR/NFC provisioning extras. iOS deliberately does
    // NOT: Guided Access already covers single-app lock, so per the product
    // decision (2026-09-29) the handler stays a well-defined no-op rather than a
    // half-built lock that could trap a child in the app.
    //
    // Contract (must match MainActivity.kt so the two OSes behave identically):
    //   getProvisioningExtras -> empty map  (no device-owner flow on iOS)
    //   stopLockTask          -> false      (nothing was locked; exit is manual)
    //   goHome                -> false      (Guided Access is ended by the adult)
    //   startLockTask         -> false      (use Guided Access instead)
    //   getAppVersion         -> build number + short version (same shape as Android)
    //   installApk            -> false      (iOS updates come from the App Store,
    //                                        not a sideloaded APK)
    //   openUrl               -> open a URL (e.g. the App Store listing) via the OS
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TapToSayKiosk") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.taptosay/kiosk",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getProvisioningExtras":
        // No QR/NFC provisioning on iOS — hand back an empty map so the caller
        // simply stays on the first-run provisioning screen.
        result([String: String]())
      case "stopLockTask", "goHome", "startLockTask", "installApk":
        result(false)
      case "getAppVersion":
        // Mirror Android's getAppVersion so the shared Dart self-updater reads
        // the same shape on both platforms (it no-ops on iOS regardless).
        let info = Bundle.main.infoDictionary
        let code = Int(info?["CFBundleVersion"] as? String ?? "0") ?? 0
        let name = info?["CFBundleShortVersionString"] as? String ?? ""
        result(["versionCode": code, "versionName": name])
      case "openUrl":
        // Open a URL with the OS — used to send the user to the App Store
        // listing for a newer version. Returns whether it opened.
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { ok in
            result(ok)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
