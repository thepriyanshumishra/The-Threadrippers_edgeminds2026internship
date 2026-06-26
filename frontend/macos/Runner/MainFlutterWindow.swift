import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "com.kivo.kivo_workspace/eyedropper",
                                       binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { (call, result) in
      if call.method == "pickColor" {
        if #available(macOS 10.15, *) {
          let sampler = NSColorSampler()
          sampler.show { (color) in
            if let color = color {
              guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
                result(nil)
                return
              }
              let red = Int(rgbColor.redComponent * 255)
              let green = Int(rgbColor.greenComponent * 255)
              let blue = Int(rgbColor.blueComponent * 255)
              let hex = String(format: "#%02X%02X%02X", red, green, blue)
              result(hex)
            } else {
              result(nil)
            }
          }
        } else {
          result(FlutterError(code: "UNSUPPORTED", message: "Requires macOS 10.15+", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
