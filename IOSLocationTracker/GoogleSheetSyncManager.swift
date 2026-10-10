import Foundation

struct SyncHistoryRecord: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let heartRate: Int
    let spo2: Int
    let bloodPressure: String
    let battery: Int
    let latitude: Double
    let longitude: Double
    let isSos: Bool
    var bodyTemp: Double?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, heartRate, spo2, bloodPressure, battery, latitude, longitude, isSos, bodyTemp
    }

    init(timestamp: Date, heartRate: Int, spo2: Int, bloodPressure: String, battery: Int, latitude: Double, longitude: Double, isSos: Bool, bodyTemp: Double? = nil) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.spo2 = spo2
        self.bloodPressure = bloodPressure
        self.battery = battery
        self.latitude = latitude
        self.longitude = longitude
        self.isSos = isSos
        self.bodyTemp = bodyTemp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        heartRate = try container.decode(Int.self, forKey: .heartRate)
        spo2 = try container.decode(Int.self, forKey: .spo2)
        bloodPressure = try container.decode(String.self, forKey: .bloodPressure)
        battery = try container.decode(Int.self, forKey: .battery)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        isSos = try container.decode(Bool.self, forKey: .isSos)
        bodyTemp = try container.decodeIfPresent(Double.self, forKey: .bodyTemp)
    }
}
class GoogleSheetSyncManager: ObservableObject {
    static let shared = GoogleSheetSyncManager()
    
    private let sheetUrlString = "https://script.google.com/macros/s/AKfycbyS4yuJfljE5wnhppJws8D3ia2WBGT_4-kHryRat1T-GNaV01OCGf02WOnV7t9sdjch/exec"
    private let urlSession: URLSession

    @Published var lastSyncTime: Date?
    @Published var isSyncing: Bool = false
    @Published var lastSyncStatus: String = "لم تتم المزامنة بعد"
    @Published var isAutoSyncActive: Bool = false
    @Published var history: [SyncHistoryRecord] = []

    private var autoSyncTimer: Timer?
    private var lastSyncAttemptTime: Date = .distantPast

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        self.urlSession = URLSession(configuration: config)

        if let savedDate = UserDefaults.standard.object(forKey: "last_google_sheet_sync_time") as? Date {
            self.lastSyncTime = savedDate
        }

        if let data = UserDefaults.standard.data(forKey: "sync_history_logs"),
           let savedHistory = try? JSONDecoder().decode([SyncHistoryRecord].self, from: data) {
            let limitDate = Date().addingTimeInterval(-31 * 24 * 3600)
            self.history = savedHistory.filter { $0.timestamp >= limitDate }
        }
    }

    struct HealthPayload: Codable {
        let emp_id: String
        let lat: Double
        let lng: Double
        let heart_rate: Int
        let spo2: Int
        let body_temp: Double
        let battery: Int
        let status: String
        let fcm_token: String
        let blood_pressure: String
    }

    // MARK: - Auto Sync Timer (Every 60 seconds)

    func startAutoSyncTimer() {
        stopAutoSyncTimer()
        isAutoSyncActive = true
        print("[GoogleSheetSyncManager] Starting auto-sync timer (every 60 seconds) ⏱️")

        // Initial sync after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.performAutoSync(force: true)
        }

        // Periodic repeating timer every 60 seconds
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performAutoSync()
        }
    }

    func stopAutoSyncTimer() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        isAutoSyncActive = false
        print("[GoogleSheetSyncManager] Auto-sync timer stopped")
    }

    func checkAndTriggerPeriodicSyncIfNeeded() {
        guard !isSyncing else { return }
        let now = Date()
        let interval = now.timeIntervalSince(lastSyncTime ?? .distantPast)
        if interval >= 60.0 {
            print("[GoogleSheetSyncManager] 60s interval elapsed since last sync (\(Int(interval))s). Triggering auto-sync...")
            performAutoSync()
        }
    }

    func performAutoSync(isSos: Bool = false, force: Bool = false, completion: ((Result<String, Error>) -> Void)? = nil) {
        guard !isSyncing else {
            completion?(.failure(NSError(domain: "GoogleSheetSync", code: -2, userInfo: [NSLocalizedDescriptionKey: "Sync in progress"])))
            return
        }

        let now = Date()
        if !force && !isSos {
            if now.timeIntervalSince(lastSyncAttemptTime) < 45.0 {
                return
            }
        }
        lastSyncAttemptTime = now

        let ido = IdoSmartManager.shared
        guard ido.isConnected || isSos else {
            print("[GoogleSheetSyncManager] Auto-sync skipped: watch not connected")
            return
        }

        let loc = LocationManager.shared
        let empId = UserDefaults.standard.string(forKey: "saved_employee_id")
            ?? UserDefaults.standard.string(forKey: "WATCH_APP_DEFAULT")
            ?? "WATCH_001"

        let bp = BloodPressureAlgorithm.estimate(
            heartRate: ido.currentHeartRate,
            spo2: ido.currentSpo2,
            prevBP: ido.currentBloodPressure
        )

        let devId = ido.currentDeviceUUID.isEmpty ? (ido.currentConnectedModel?.macAddress ?? "") : ido.currentDeviceUUID

        sendData(
            empId: empId,
            latitude: loc.latitude,
            longitude: loc.longitude,
            heartRate: ido.currentHeartRate,
            spo2: ido.currentSpo2,
            bodyTemp: ido.currentTemperature,
            battery: ido.currentBattery,
            isSos: isSos,
            deviceIdentifier: devId,
            bloodPressure: bp.formatted,
            completion: completion
        )
    }

    // MARK: - Core Send Data

    func sendData(
        empId: String,
        latitude: Double,
        longitude: Double,
        heartRate: Int,
        spo2: Int,
        bodyTemp: Double,
        battery: Int,
        isSos: Bool,
        deviceIdentifier: String,
        bloodPressure: String,
        completion: ((Result<String, Error>) -> Void)? = nil
    ) {
        guard let url = URL(string: sheetUrlString) else {
            let err = NSError(domain: "GoogleSheetSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Google Sheet URL"])
            DispatchQueue.main.async {
                self.lastSyncStatus = "خطأ في رابط Google Sheets"
                completion?(.failure(err))
            }
            return
        }

        DispatchQueue.main.async {
            self.isSyncing = true
        }

        let status = isSos ? "SOS" : "NORMAL"
        let fcmToken = deviceIdentifier.isEmpty ? "WATCH_APP_DEFAULT" : "WATCH_\(deviceIdentifier.replacingOccurrences(of: "-", with: "").prefix(12))"

        let payload = HealthPayload(
            emp_id: empId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WATCH_001" : empId,
            lat: latitude,
            lng: longitude,
            heart_rate: heartRate,
            spo2: spo2,
            body_temp: bodyTemp,
            battery: battery,
            status: status,
            fcm_token: fcmToken,
            blood_pressure: bloodPressure
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            DispatchQueue.main.async {
                self.isSyncing = false
                self.lastSyncStatus = "خطأ في ترميز البيانات"
                completion?(.failure(error))
            }
            return
        }

        // حفظ محلي فوري قبل محاولة الإرسال للشبكة لضمان عدم ضياع البيانات
        let recordDate = Date()
        let record = SyncHistoryRecord(timestamp: recordDate, heartRate: heartRate, spo2: spo2, bloodPressure: bloodPressure, battery: battery, latitude: latitude, longitude: longitude, isSos: isSos, bodyTemp: bodyTemp)
        
        DispatchQueue.main.async {
            self.history.insert(record, at: 0)
            let limitDate = Date().addingTimeInterval(-31 * 24 * 3600)
            self.history.removeAll { $0.timestamp < limitDate }
            if let historyData = try? JSONEncoder().encode(self.history) {
                UserDefaults.standard.set(historyData, forKey: "sync_history_logs")
            }
            let assessment = HealthEngine.assess(self.history)
            let forecast = HealthEngine.forecast(self.history, fatigue: SleepStore.shared.fatigue())
            HealthAlertCenter.shared.evaluate(assessment)
            HealthAlertCenter.shared.evaluateForecast(forecast)
            let hr = heartRate > 0 ? heartRate : 0
            let o2 = spo2 > 0 ? spo2 : 0
            if hr > 0 || o2 > 0 {
                // الخطر المتوقع المرتفع يظهر على شاشة القفل قبل أن يصبح خطراً قائماً.
                var message = assessment.headline
                if assessment.score >= 50, let top = forecast.risks.first, top.level == .high {
                    message = "تنبيه استباقي: \(top.name) (\(Int((top.probability * 100).rounded()))٪)"
                }
                if #available(iOS 16.1, *) {
                    HealthLiveActivityManager.shared.update(
                        heartRate: hr,
                        spo2: o2,
                        isCritical: assessment.score < 50,
                        message: message
                    )
                }
            }
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.lastSyncStatus = "فشلت المزامنة: \(error.localizedDescription)"
                    print("[GoogleSheetSyncManager] Send failed: \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }

                let respString = data != nil ? String(data: data!, encoding: .utf8) ?? "OK" : "OK"
                self?.lastSyncTime = recordDate
                self?.lastSyncStatus = "تمت المزامنة بنجاح ✅"
                UserDefaults.standard.set(recordDate, forKey: "last_google_sheet_sync_time")
                print("[GoogleSheetSyncManager] Measurements sent successfully to Google Sheets at \(recordDate)")
                completion?(.success(respString))
            }
        }
        task.resume()
    }
}





