import Foundation
import CoreLocation
import AVFoundation
import UserNotifications

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static let defaultScriptURL = "https://script.google.com/macros/s/AKfycbxW27wZfTwIDfe29qdqVmDi6quaJCkV3b6qc9r9j2-SN5msNjqQY1pvYUnCxdFQH_SP3A/exec"
    private let manager = CLLocationManager()
    private var syncTimer: Timer?
    private var latestLocation: CLLocation?
    private var lastAlarmState = "OFF"
    private var isSyncInFlight = false
    private var lastSyncAttempt = Date.distantPast
    private var alarmPlayer: AVAudioPlayer?

    @Published private(set) var latitude = 0.0
    @Published private(set) var longitude = 0.0
    @Published private(set) var isTracking = false
    @Published private(set) var lastSync = "Never"
    @Published private(set) var errorMessage: String?
    @Published var alarmMessage: String?
    @Published var scriptURL: String { didSet { UserDefaults.standard.set(scriptURL, forKey: "scriptURL") } }

    override init() {
        scriptURL = UserDefaults.standard.string(forKey: "scriptURL") ?? Self.defaultScriptURL
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .otherNavigation
    }

    func requestPermissions() {
        manager.requestAlwaysAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func toggleTracking() { isTracking ? stopTracking() : startTracking() }

    private func startTracking() {
        guard URL(string: scriptURL)?.scheme?.hasPrefix("http") == true else { errorMessage = "Enter a valid HTTPS Google Apps Script URL."; return }
        guard manager.authorizationStatus == .authorizedAlways else { requestPermissions(); errorMessage = "Allow Always Location access in Settings, then press Start again."; return }
        isTracking = true; errorMessage = nil; manager.startUpdatingLocation()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.syncLatestLocation() }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    func stopTracking() {
        isTracking = false; manager.stopUpdatingLocation(); syncTimer?.invalidate(); syncTimer = nil; stopAlarm()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        latestLocation = location; latitude = location.coordinate.latitude; longitude = location.coordinate.longitude
        if isTracking { sync(location: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { errorMessage = "Location error: \(error.localizedDescription)" }

    private func syncLatestLocation() { if let location = latestLocation, isTracking { sync(location: location) } }

    private func sync(location: CLLocation) {
        guard let url = URL(string: scriptURL), !isSyncInFlight, Date().timeIntervalSince(lastSyncAttempt) >= 3 else { return }
        isSyncInFlight = true; lastSyncAttempt = Date()
        let payload: [String: Any] = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { isSyncInFlight = false; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.timeoutInterval = 20; request.httpBody = body
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }; self.isSyncInFlight = false
                if let error { self.errorMessage = "Sync failed: \(error.localizedDescription)"; return }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { self.errorMessage = "The server returned an invalid response."; return }
                self.errorMessage = nil; self.lastSync = Date().formatted(date: .omitted, time: .standard); self.handleAlarmState((json["alarm_state"] as? String ?? "OFF").uppercased())
            }
        }.resume()
    }

    private func handleAlarmState(_ state: String) { if state == "ON", lastAlarmState != "ON" { triggerAlarm() }; if state == "OFF" { stopAlarm() }; lastAlarmState = state }
    private func triggerAlarm() {
        alarmMessage = "Dashboard Alarm Active!"
        let content = UNMutableNotificationContent(); content.title = "ALARM"; content.body = "Dashboard Alarm Active!"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "dashboard-alarm", content: content, trigger: nil))
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") { try? AVAudioSession.sharedInstance().setCategory(.playback); try? AVAudioSession.sharedInstance().setActive(true); alarmPlayer = try? AVAudioPlayer(contentsOf: url); alarmPlayer?.numberOfLoops = -1; alarmPlayer?.play() } else { AudioServicesPlaySystemSound(1005) }
    }
    func stopAlarm() { alarmPlayer?.stop(); alarmPlayer = nil; alarmMessage = nil; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dashboard-alarm"]) }
}
