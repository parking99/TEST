import Foundation

class GoogleSheetSyncManager {
    static let shared = GoogleSheetSyncManager()
    
    private let sheetUrlString = "https://script.google.com/macros/s/AKfycbyS4yuJfljE5wnhppJws8D3ia2WBGT_4-kHryRat1T-GNaV01OCGf02WOnV7t9sdjch/exec"
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        self.urlSession = URLSession(configuration: config)
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
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: sheetUrlString) else {
            completion(.failure(NSError(domain: "GoogleSheetSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Google Sheet URL"])))
            return
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
            completion(.failure(error))
            return
        }

        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            let respString = data != nil ? String(data: data!, encoding: .utf8) ?? "OK" : "OK"
            DispatchQueue.main.async {
                completion(.success(respString))
            }
        }
        task.resume()
    }
}
