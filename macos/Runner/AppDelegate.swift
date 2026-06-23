import Cocoa
import FlutterMacOS
import GoogleSignIn
import FirebaseAuth

@main
class AppDelegate: FlutterAppDelegate {
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
      GIDSignIn.sharedInstance.handle(url)
    }
  }
}
