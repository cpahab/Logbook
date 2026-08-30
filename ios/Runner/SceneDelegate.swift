import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  private let channelName = "com.ziegler.logbook/gpx_share"
  private var methodChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Handle any GPX URL in the cold-start connection options. The Dart
    // handler isn't registered yet, so buffer it for a later pull rather
    // than pushing (see handleGpxUrl).
    for context in connectionOptions.urlContexts {
      if handleGpxUrl(context.url, push: false) { break }
    }

    // super creates the FlutterViewController and sets self.window.
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Set up the method channel now that FlutterViewController exists.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "getPendingGpxPath" {
          result(AppDelegate.pendingGpxPath)
          AppDelegate.pendingGpxPath = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      methodChannel = channel
    }
  }

  // Warm start: GPX URL arrives while the scene (and Dart's handler) is
  // already running — push it straight to Dart instead of relying on a
  // lifecycle-transition poll that won't fire if the app is already in the
  // foreground.
  override func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    var unhandled = urlContexts
    for context in urlContexts where context.url.pathExtension.lowercased() == "gpx" {
      handleGpxUrl(context.url, push: true)
      unhandled.remove(context)
    }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
  }

  @discardableResult
  private func handleGpxUrl(_ url: URL, push: Bool) -> Bool {
    guard url.pathExtension.lowercased() == "gpx",
          let stablePath = copyToInbox(url: url) else { return false }
    if push, let channel = methodChannel {
      channel.invokeMethod("onGpxFile", arguments: ["path": stablePath])
    } else {
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
