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
    self.backgroundColor = .windowBackgroundColor
    flutterViewController.backgroundColor = .windowBackgroundColor
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(origin: windowFrame.origin, size: NSSize(width: 1120, height: 800)), display: true)
    self.minSize = NSSize(width: 480, height: 600)
    setFrameAutosaveName("com.fcxray.client.MainWindow")

    let launchIcon = NSImageView()
    launchIcon.image = NSApp.applicationIconImage
    launchIcon.translatesAutoresizingMaskIntoConstraints = false
    let surface = flutterViewController.view
    surface.addSubview(launchIcon)
    NSLayoutConstraint.activate([
      launchIcon.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
      launchIcon.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
      launchIcon.widthAnchor.constraint(equalToConstant: 72),
      launchIcon.heightAnchor.constraint(equalToConstant: 72)
    ])

    let tray = FlutterMethodChannel(name: "com.fcxray.client/window",
                                   binaryMessenger: flutterViewController.engine.binaryMessenger)
    tray.setMethodCallHandler { [weak self, weak launchIcon] call, result in
      if call.method == "firstFrame" {
        launchIcon?.removeFromSuperview()
        result(nil)
        return
      }
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
