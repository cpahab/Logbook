import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Stable path of a GPX file received before the Flutter engine was ready.
  /// Read and cleared by the method channel handler in SceneDelegate.
  static var pendingGpxPath: String? = nil

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Strip GPX file URLs so GoRouter doesn't treat the file:// URI as a route.
    // With scene lifecycle, the URL also arrives in SceneDelegate.scene(_:willConnectTo:).
    var filteredOptions = launchOptions
    if let url = launchOptions?[.url] as? URL,
       url.pathExtension.lowercased() == "gpx" {
      var opts = launchOptions ?? [:]
      opts.removeValue(forKey: .url)
      filteredOptions = opts
    }

    return super.application(application, didFinishLaunchingWithOptions: filteredOptions)
    // Note: with UIApplicationSceneManifest present the window belongs to the
    // scene, not the app delegate. Channel setup and file handling both live in
    // SceneDelegate.swift.
  }
}
