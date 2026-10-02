import SwiftUI
import UIKit
import Flutter
import FlutterPluginRegistrant
import protocol_channel

class AppDelegate: NSObject, UIApplicationDelegate {
    private var flutterEngine: FlutterEngine?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        initFlutterEngine()
        IdoSmartManager.shared.initSdk()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        IdoSmartManager.shared.beginBackgroundKeepAlive()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        IdoSmartManager.shared.endBackgroundKeepAlive()
    }

    private func initFlutterEngine() {
        flutterEngine = FlutterEngine(name: "io.flutter", project: nil)
        flutterEngine?.run(withEntrypoint: nil)
        if let engine = flutterEngine {
            GeneratedPluginRegistrant.register(with: engine)
            print("[AppDelegate] FlutterEngine and plugins initialized successfully")
        }
    }
}

@main
struct IOSLocationTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
