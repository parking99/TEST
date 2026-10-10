//
//  SleepStore.swift
//  SecurityPass
//
//  بيانات النوم من السوار: تُحفظ على الجهاز فقط ولا تُرسل إلى لوحة التحكم ولا تدخل التقارير المشتركة.
//  المفاتيح مأخوذة من مكتبة iDO (بيانات النوم V2 و V3)، والقراءة متسامحة مع غياب أي منها.
//

import Foundation
import UserNotifications

// MARK: - ليلة نوم

public struct SleepRecord: Codable, Identifiable, Equatable {
    /// بداية يوم الاستيقاظ — مفتاح الليلة.
    public let day: Date
    public let fellAsleep: Date?
    public let wokeUp: Date?
    public let totalMinutes: Int
    public let deepMinutes: Int
    public let lightMinutes: Int
    public let remMinutes: Int
    public let awakeMinutes: Int
    public let awakeCount: Int
    /// تقييم السوار ١…١٠٠ إن أرسله.
    public let deviceScore: Int?
    public let avgHeartRate: Int?
    public let avgSpo2: Int?
    public let avgRespiration: Int?

    public var id: Date { day }
}

// MARK: - التقييم

public struct SleepInsight {
    public enum Level {
        case good, fair, poor

        public var title: String {
            switch self {
            case .good: return "جيد"
            case .fair: return "متوسط"
            case .poor: return "ضعيف"
            }
        }
    }

    public let quality: Int
    public let level: Level
    public let message: String
    /// قلة نوم متراكمة: متوسط آخر ٣ ليالٍ أقل من ٦ ساعات.
    public let hasDebt: Bool
    /// ٠…١ — يرفع حساسية التنبؤ عند قلة النوم.
    public let fatigue: Double
}

public enum SleepAnalyzer {
    /// جودة النوم: تقييم السوار إن وُجد، وإلا تقدير من المدة ونسبة النوم العميق والاستيقاظات.
    public static func quality(_ r: SleepRecord) -> Int {
        if let s = r.deviceScore, (1...100).contains(s) { return s }

        let hours = Double(r.totalMinutes) / 60
        let duration: Double
        if hours < 7 { duration = max(0, 100 - (7 - hours) * 20) }
        else if hours > 9 { duration = max(0, 100 - (hours - 9) * 10) }
        else { duration = 100 }

        let deepShare = r.totalMinutes > 0 ? Double(r.deepMinutes) / Double(r.totalMinutes) : 0
        let deep = min(100, deepShare / 0.15 * 100)
        let penalty = min(30, Double(r.awakeCount) * 3 + Double(r.awakeMinutes) / 2)

        return Int(min(100, max(0, 0.65 * duration + 0.35 * deep - penalty)).rounded())
    }

    public static func insight(for r: SleepRecord, history: [SleepRecord]) -> SleepInsight {
        let q = quality(r)
        var level: SleepInsight.Level = q >= 70 ? .good : (q >= 50 ? .fair : .poor)
        if r.totalMinutes < 5 * 60 { level = .poor }

        let lastThree = history.filter { $0.day <= r.day }.sorted { $0.day > $1.day }.prefix(3)
        let hasDebt = lastThree.count == 3
            && Double(lastThree.map { $0.totalMinutes }.reduce(0, +)) / 3 < 6 * 60

        var message: String
        switch level {
        case .good: message = "نومك كان كافياً — جسمك مستعد لنشاط اليوم."
        case .fair: message = "نومك أقل من المثالي — خذ فترات راحة قصيرة واشرب الماء بانتظام."
        case .poor: message = "نومك غير كافٍ — خفّف الجهد اليوم وتجنّب المهام الشاقة قدر الإمكان، وخذ فترات راحة أكثر."
        }
        if hasDebt { message += " قلة النوم متراكمة خلال آخر ٣ ليالٍ؛ حاول النوم مبكراً الليلة." }

        var fatigue: Double
        switch level {
        case .good: fatigue = 0
        case .fair: fatigue = 0.5
        case .poor: fatigue = 1
        }
        if hasDebt { fatigue = min(1, fatigue + 0.3) }

        return SleepInsight(quality: q, level: level, message: message, hasDebt: hasDebt, fatigue: fatigue)
    }

    public static func format(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) د" }
        return m == 0 ? "\(h) س" : "\(h) س \(m) د"
    }
}

// MARK: - المخزن

public final class SleepStore: ObservableObject {
    public static let shared = SleepStore()

    @Published public private(set) var records: [SleepRecord] = []

    private let storageKey = "sleep_records_v1"
    private let notifiedKey = "sleep_notified_day_v1"
    private let keepNights = 30

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([SleepRecord].self, from: data) {
            records = saved.sorted { $0.day > $1.day }
        }
    }

    /// آخر ليلة انتهت خلال ٢٠ ساعة — هي التي تؤثر على اليوم الحالي.
    public func recentNight(now: Date = Date()) -> SleepRecord? {
        guard let last = records.first else { return nil }
        let end = last.wokeUp ?? last.day.addingTimeInterval(8 * 3600)
        return now.timeIntervalSince(end) <= 20 * 3600 ? last : nil
    }

    public func latestInsight() -> SleepInsight? {
        records.first.map { SleepAnalyzer.insight(for: $0, history: records) }
    }

    /// معامل الإرهاق للتنبؤ — صفر إن لم توجد ليلة حديثة.
    public func fatigue(now: Date = Date()) -> Double {
        guard let night = recentNight(now: now) else { return 0 }
        return SleepAnalyzer.insight(for: night, history: records).fatigue
    }

    // MARK: الاستقبال من السوار

    /// يُستدعى بمحتوى مزامنة النوم (JSON مفكوك) على الخيط الرئيسي.
    public func ingest(json root: Any, now: Date = Date()) {
        var found: [SleepRecord] = []
        collect(root, into: &found, now: now)
        guard !found.isEmpty else { return }

        var byDay = Dictionary(records.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for r in found {
            // عند تكرار الليلة نُبقي الأطول — السوار قد يرسل جزءاً ثم الليلة كاملة.
            if let old = byDay[r.day], old.totalMinutes >= r.totalMinutes { continue }
            byDay[r.day] = r
        }
        records = byDay.values.sorted { $0.day > $1.day }.prefix(keepNights).map { $0 }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        notifyIfNeeded(now: now)
    }

    private func collect(_ element: Any, into out: inout [SleepRecord], now: Date) {
        if let dict = element as? [String: Any] {
            if let r = record(from: dict, now: now) {
                out.append(r)
            } else {
                for value in dict.values { collect(value, into: &out, now: now) }
            }
        } else if let array = element as? [Any] {
            for item in array { collect(item, into: &out, now: now) }
        }
    }

    private func record(from d: [String: Any], now: Date) -> SleepRecord? {
        let deep = int(d, "deep_sleep_mins", "deep_mins", "deep_sleep_minute") ?? 0
        let light = int(d, "light_sleep_mins", "light_mins", "light_sleep_minute", "ligth_sleep_minute") ?? 0
        let rem = int(d, "rem_mins") ?? 0
        guard let total = int(d, "total_sleep_time_mins", "total_sleep_mins") ?? nonZero(deep + light + rem),
              total >= 30, total <= 16 * 60 else { return nil }

        let calendar = Calendar.current
        var fellAsleep: Date?
        if let y = int(d, "fall_asleep_year"), let mo = int(d, "fall_asleep_month"), let da = int(d, "fall_asleep_day"),
           let h = int(d, "fall_asleep_hour"), let mi = int(d, "fall_asleep_minute", "fall_asleep_minte") {
            fellAsleep = calendar.date(from: DateComponents(year: y, month: mo, day: da, hour: h, minute: mi))
        }

        // يوم الاستيقاظ: من تاريخ السجل إن وُجد، وإلا من وقت النوم، وإلا اليوم.
        var wakeDay = calendar.startOfDay(for: now)
        if let y = int(d, "year"), let mo = int(d, "month"), let da = int(d, "day"),
           let date = calendar.date(from: DateComponents(year: y, month: mo, day: da)) {
            wakeDay = date
        } else if let start = fellAsleep {
            wakeDay = calendar.startOfDay(for: start.addingTimeInterval(Double(total) * 60))
        }

        var wokeUp: Date?
        if let h = int(d, "awake_hour"), let mi = int(d, "awake_minute") {
            wokeUp = calendar.date(bySettingHour: h, minute: mi, second: 0, of: wakeDay)
        } else if let start = fellAsleep {
            wokeUp = start.addingTimeInterval(Double(total + (int(d, "wake_mins") ?? 0)) * 60)
        }
        if fellAsleep == nil, let end = wokeUp {
            fellAsleep = end.addingTimeInterval(-Double(total + (int(d, "wake_mins") ?? 0)) * 60)
        }

        return SleepRecord(
            day: wakeDay,
            fellAsleep: fellAsleep,
            wokeUp: wokeUp,
            totalMinutes: total,
            deepMinutes: deep,
            lightMinutes: light,
            remMinutes: rem,
            awakeMinutes: int(d, "wake_mins") ?? 0,
            awakeCount: int(d, "wake_count") ?? 0,
            deviceScore: int(d, "sleep_score").flatMap { (1...100).contains($0) ? $0 : nil },
            avgHeartRate: int(d, "sleep_avg_hr_value").flatMap { $0 > 0 ? $0 : nil },
            avgSpo2: int(d, "sleep_avg_spo2_value").flatMap { $0 > 0 ? $0 : nil },
            avgRespiration: int(d, "sleep_avg_respir_rate_value").flatMap { $0 > 0 ? $0 : nil }
        )
    }

    private func int(_ d: [String: Any], _ keys: String...) -> Int? {
        for k in keys {
            guard let v = d[k] else { continue }
            if let i = v as? Int { return i }
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String, let i = Int(s) { return i }
        }
        return nil
    }

    private func nonZero(_ v: Int) -> Int? { v > 0 ? v : nil }

    // MARK: التنبيه

    /// تنبيه واحد لكل ليلة، يظهر في التطبيق فقط، عند نوم ضعيف أو قلة نوم متراكمة.
    private func notifyIfNeeded(now: Date) {
        guard let night = recentNight(now: now) else { return }
        let stamp = night.day.timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: notifiedKey) != stamp else { return }

        let insight = SleepAnalyzer.insight(for: night, history: records)
        guard insight.level == .poor || insight.hasDebt else { return }
        UserDefaults.standard.set(stamp, forKey: notifiedKey)

        let content = UNMutableNotificationContent()
        content.title = "😴 نومك الليلة الماضية \(SleepAnalyzer.format(minutes: night.totalMinutes))"
        content.body = insight.message
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "sleep-\(Int(stamp))", content: content, trigger: nil)
        )
    }
}
