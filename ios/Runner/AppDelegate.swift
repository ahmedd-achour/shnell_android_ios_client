import UIKit
import Flutter
import GoogleMaps // Add this

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Add your API Key here
    GMSServices.provideAPIKey("AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}