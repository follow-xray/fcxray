import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var trayEnabled = false

  override func performClose(_ sender: Any?) {
    if trayEnabled {
      orderOut(sender)
    } else {
      super.performClose(sender)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(origin: windowFrame.origin, size: NSSize(width: 1120, height: 800)), display: true)
    self.minSize = NSSize(width: 480, height: 600)

    let tray = FlutterMethodChannel(name: "com.fcxray.client/window",
                                   binaryMessenger: flutterViewController.engine.binaryMessenger)
    tray.setMethodCallHandler { [weak self] call, result in
      guard call.method == "enableCloseToTray" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.trayEnabled = true
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
