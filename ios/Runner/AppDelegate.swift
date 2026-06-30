import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Stable path of a GPX file received before the Flutter engine was ready.
  /// The Dart side pulls this via "getPendingGpxPath" on engine startup.
  static var pendingGpxPath: String? = nil

  private let channelName = "com.ziegler.logbook/gpx_share"
  private var gpxChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: engineBridge.binaryMessenger
    )
    gpxChannel = channel

    // Flutter asks for any file that arrived during cold start.
    channel.setMethodCallHandler { call, result in
      if call.method == "getPendingGpxPath" {
        result(AppDelegate.pendingGpxPath)
        AppDelegate.pendingGpxPath = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Called when another app hands us a file via the share sheet / Files app.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.pathExtension.lowercased() == "gpx" else { return false }
    guard let stablePath = copyToInbox(url: url) else { return true }

    if let channel = gpxChannel {
      // Engine is running — emit directly.
      channel.invokeMethod("onGpxFile", arguments: ["path": stablePath])
    } else {
      // Cold start — engine not ready yet; Dart will pull via getPendingGpxPath.
      AppDelegate.pendingGpxPath = stablePath
    }
    return true
  }

  private func copyToInbox(url: URL) -> String? {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let inbox = docs.appendingPathComponent("GPXInbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let dest = inbox.appendingPathComponent(url.lastPathComponent)
    try? FileManager.default.removeItem(at: dest)
    do {
      _ = url.startAccessingSecurityScopedResource()
      defer { url.stopAccessingSecurityScopedResource() }
      try FileManager.default.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      return nil
    }
  }
}
