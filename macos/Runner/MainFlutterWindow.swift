import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let gpxChannel = FlutterMethodChannel(
      name: "com.ziegler.logbook/gpx_share",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    gpxChannel.setMethodCallHandler { call, result in
      if call.method == "getPendingGpxPath" {
        result(AppDelegate.pendingGpxPath)
        AppDelegate.pendingGpxPath = nil
        AppDelegate.dartReady = true
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    AppDelegate.gpxMethodChannel = gpxChannel

    self.minSize = NSSize(width: 400, height: 600)

    super.awakeFromNib()
  }
}
