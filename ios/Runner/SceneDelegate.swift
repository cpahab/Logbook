import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  private let channelName = "com.ziegler.logbook/gpx_share"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Handle any GPX URL in the cold-start connection options.
    for context in connectionOptions.urlContexts {
      if handleGpxUrl(context.url) { break }
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
    }
  }

  // Warm start: GPX URL arrives while the scene is already running.
  override func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    var unhandled = urlContexts
    for context in urlContexts where context.url.pathExtension.lowercased() == "gpx" {
      handleGpxUrl(context.url)
      unhandled.remove(context)
    }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
  }

  @discardableResult
  private func handleGpxUrl(_ url: URL) -> Bool {
    guard url.pathExtension.lowercased() == "gpx",
          let stablePath = copyToInbox(url: url) else { return false }
    AppDelegate.pendingGpxPath = stablePath
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
