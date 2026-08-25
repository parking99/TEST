import Foundation
import CoreLocation
import AVFoundation
import AudioToolbox
import UserNotifications

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static let defaultScriptURL = "https://script.google.com/macros/s/AKfycbx_fhQ1XnZGKoHy29quDke3Y3w-JpFCCrTv8I7Nhb4TTCiAPuREqtimwQqaPsPkSbyalg/exec"
    private let manager = CLLocationManager()
    private var syncTimer: Timer?
    private var vibrationTimer: Timer?
    private var latestLocation: CLLocation?
    private var isSyncInFlight = false
    private var lastSyncAttempt = Date.distantPast
    private var alarmPlayer: AVAudioPlayer?

    @Published private(set) var latitude = 0.0
    @Published private(set) var longitude = 0.0
    @Published private(set) var speed = 0.0
    @Published private(set) var isTracking = false
    @Published private(set) var lastSync = "Never"
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = "Status: Offline"
    @Published private(set) var isAlarmActive = false
    
    @Published var deviceId: String {
        didSet {
            UserDefaults.standard.set(deviceId, forKey: "deviceId")
        }
    }
    
    @Published var scriptURL: String {
        didSet {
            UserDefaults.standard.set(scriptURL, forKey: "scriptURL")
        }
    }

    override init() {
        scriptURL = UserDefaults.standard.string(forKey: "scriptURL") ?? Self.defaultScriptURL
        deviceId = UserDefaults.standard.string(forKey: "deviceId") ?? "Device_01"
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
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { requestPermissions(); errorMessage = "Allow Location access in Settings, then press Start again."; return }
        isTracking = true
        errorMessage = nil
        statusMessage = "Status: Secure & Monitoring"
        manager.startUpdatingLocation()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.syncLatestLocation() }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    func stopTracking() {
        isTracking = false
        statusMessage = "Status: Offline"
        manager.stopUpdatingLocation()
        syncTimer?.invalidate()
        syncTimer = nil
        stopAlarm()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        latestLocation = location
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        
        let rawSpeed = location.speed >= 0 ? location.speed * 3.6 : 0.0
        speed = rawSpeed < 2.0 ? 0.0 : rawSpeed
        
        if isTracking { sync(location: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { errorMessage = "Location error: \(error.localizedDescription)" }

    private func syncLatestLocation() { if let location = latestLocation, isTracking { sync(location: location) } }

    private func sync(location: CLLocation) {
        guard let url = URL(string: scriptURL), !isSyncInFlight, Date().timeIntervalSince(lastSyncAttempt) >= 2 else { return }
        isSyncInFlight = true
        lastSyncAttempt = Date()
        
        let apnsToken = UserDefaults.standard.string(forKey: "apnsToken") ?? ""
        
        let payload: [String: Any] = [
            "deviceId": deviceId,
            "token": apnsToken,
            "fcmToken": apnsToken,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "speed": speed
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { isSyncInFlight = false; return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncInFlight = false
                if let error {
                    self.errorMessage = "Sync failed: \(error.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "The server returned an invalid response."
                    return
                }
                
                self.errorMessage = nil
                self.lastSync = Date().formatted(date: .omitted, time: .standard)
                
                let globalEmergency = (json["global_emergency"] as? String ?? "OFF").uppercased()
                let alarmState = (json["alarm_state"] as? String ?? "OFF").uppercased()
                let serverMsg = json["message"] as? String ?? ""
                
                let isEmergency = globalEmergency == "ON" || alarmState == "ON"
                self.isAlarmActive = isEmergency
                
                if isEmergency {
                    self.statusMessage = "DANGER: EMERGENCY ALERT ACTIVE"
                    self.triggerAlarm(message: serverMsg.isEmpty ? "Remote Command" : serverMsg)
                } else {
                    self.statusMessage = serverMsg.isEmpty ? "Status: Secure & Monitoring" : serverMsg
                    self.stopAlarm()
                }
            }
        }.resume()
    }

    private func triggerAlarm(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "DANGER ALARM"
        content.body = message
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "dashboard-alarm", content: content, trigger: nil))
        
        // Continuous vibration loop
        if vibrationTimer == nil {
            vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
        
        // Alarm sound loop
        if alarmPlayer == nil {
            if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)
                alarmPlayer = try? AVAudioPlayer(contentsOf: url)
                alarmPlayer?.numberOfLoops = -1
                alarmPlayer?.play()
            } else {
                AudioServicesPlaySystemSound(1005)
            }
        }
    }
    
    func stopAlarm() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dashboard-alarm"])
    }
}
