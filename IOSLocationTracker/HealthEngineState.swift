import Foundation

// MARK: - Daily Health Summary & State
public struct DailyHealthSummary: Codable {
    public let date: Date
    public let sampleCount: Int
    public let coverage: Double
    
    public struct IndicatorStats: Codable {
        public let min: Double
        public let max: Double
        public let avg: Double
        public let restingAvg: Double
        public let peakLoad: Double
        public let minutesInNormal: Int
        public let minutesInCaution: Int
        public let minutesInCritical: Int
    }
    
    public let heartRateStats: IndicatorStats?
    public let spo2Stats: IndicatorStats?
    public let bodyTempStats: IndicatorStats?
    
    public let bloodPressureMin: String?
    public let bloodPressureMax: String?
    public let bloodPressureAvg: String?
    
    public let worstState: HealthBand
}

public struct HealthEngineState: Codable {
    public var hrLoad: Double = 0.0
    public var spo2Load: Double = 0.0
    public var tempLoad: Double = 0.0
    
    public var continuousHrCriticalMinutes: Int = 0
    public var continuousSpo2CriticalMinutes: Int = 0
    public var continuousTempCriticalMinutes: Int = 0
    
    public var baselineHr: Double = 75.0
    public var baselineSpo2: Double = 98.0
    
    public var lastUpdate: Date = .distantPast
    
    public init() {}
}

public class HealthEngineStateManager {
    public static let shared = HealthEngineStateManager()
    private let stateKey = "health_engine_state_v2"
    private let summariesKey = "health_engine_summaries_v2"
    
    public var state: HealthEngineState
    public var summaries: [DailyHealthSummary]
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let saved = try? JSONDecoder().decode(HealthEngineState.self, from: data) {
            self.state = saved
        } else {
            self.state = HealthEngineState()
        }
        
        if let data = UserDefaults.standard.data(forKey: summariesKey),
           let saved = try? JSONDecoder().decode([DailyHealthSummary].self, from: data) {
            self.summaries = saved
        } else {
            self.summaries = []
        }
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
        if let data = try? JSONEncoder().encode(summaries) {
            UserDefaults.standard.set(data, forKey: summariesKey)
        }
    }
}
