import SwiftUI
import UIKit
import Flutter
import FlutterPluginRegistrant
import protocol_channel
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var flutterEngine: FlutterEngine?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        initFlutterEngine()
        LocationManager.shared.requestPermissions()
        IdoSmartManager.shared.initSdk()
        HealthAlertCenter.shared.requestAuthorization()
        // اهتزاز السوار مع التنبيهات الحرجة والسريعة.
        HealthAlertCenter.shared.buzzWatch = {
            IdoSmartManager.shared.buzz(seconds: Double(AlertSettings.alarmBuzzSeconds))
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            VoiceAlertManager.notificationCategoryDefinition,
            ReminderStore.notificationCategoryDefinition
        ])
        ReminderStore.shared.scheduleNotifications()
        return true
    }

    // MARK: - الإشعارات

    /// إظهار الإشعارات والتطبيق مفتوح أيضاً — تنبيه الخطر لا يُخفى لأن الشاشة أمام المستخدم.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // أي تفاعل مع إشعار (منبّه أو تنبيه صحي) يوقف اهتزاز السوار — المستخدم انتبه.
        DispatchQueue.main.async { IdoSmartManager.shared.stopBuzz() }
        switch response.actionIdentifier {
        case VoiceAlertManager.okAction:
            DispatchQueue.main.async { VoiceAlertManager.shared.acknowledge() }
        case ReminderStore.snoozeAction:
            ReminderStore.shared.snooze(response.notification.request.content)
        default:
            break
        }
        completionHandler()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        IdoSmartManager.shared.beginBackgroundKeepAlive()
        GoogleSheetSyncManager.shared.checkAndTriggerPeriodicSyncIfNeeded()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        IdoSmartManager.shared.endBackgroundKeepAlive()
        ReminderStore.shared.expireOneTime()
        // فتح التطبيق يعني أن المستخدم انتبه — يتوقف اهتزاز التنبيهات العادية.
        if !VoiceAlertManager.shared.isActive { IdoSmartManager.shared.stopBuzz() }
        VoiceAlertManager.shared.recoverIfStale()
        GoogleSheetSyncManager.shared.checkAndTriggerPeriodicSyncIfNeeded()
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
