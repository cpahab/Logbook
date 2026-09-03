import Cocoa
import FlutterMacOS
import GoogleSignIn
import FirebaseAuth

@main
class AppDelegate: FlutterAppDelegate {
  static var pendingGpxPath: String?
  static var gpxMethodChannel: FlutterMethodChannel?
  // True once Dart has pulled getPendingGpxPath at least once, i.e. its
  // 'onGpxFile' handler is actually registered and listening — the native
  // FlutterMethodChannel object existing (awakeFromNib having run) is NOT
  // enough evidence of that, since on a cold launch-by-document the OS can
  // deliver application(_:open:) before Dart's main() has run at all. Until
  // this is true, always buffer into pendingGpxPath rather than pushing, the
  // same way iOS/Android's separate cold-start entry points do.
  static var dartReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Firebase Auth defaults to a team-scoped keychain access group which
    // requires a provisioned certificate. Resetting to nil uses the app's
    // default keychain and works with any signing identity.
    try? Auth.auth().useUserAccessGroup(nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.pathExtension.lowercased() == "gpx" {
        handleGpxUrl(url)
      } else {
        GIDSignIn.sharedInstance.handle(url)
      }
    }
  }

  private func handleGpxUrl(_ url: URL) {
    guard let stablePath = copyToInbox(url: url) else { return }
    if AppDelegate.dartReady, let channel = AppDelegate.gpxMethodChannel {
      channel.invokeMethod("onGpxFile", arguments: ["path": stablePath])
    } else {
      AppDelegate.pendingGpxPath = stablePath
    }
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
