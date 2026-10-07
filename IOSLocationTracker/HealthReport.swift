//
//  HealthReport.swift
//  SecurityPass
//
//  نموذج التقرير الصحي: يجمّع السجلات المخزّنة محلياً في بنية جاهزة للطباعة.
//  لا شبكة، ولا حقل جديد، ولا تغيير على قاعدة البيانات أو البروتوكول.
//

import Foundation

public enum ReportPeriod: String, CaseIterable, Identifiable {
    case today, week, month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "اليوم"
        case .week:  return "آخر ٧ أيام"
        case .month: return "آخر ٣٠ يوماً"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .today: return 24 * 3600
        case .week:  return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        }
    }
}

public struct IndicatorSummary {
    public let kind: VitalKind
    public let latest: String
    public let minimum: String
    public let average: String
    public let maximum: String
    public let band: VitalBand
    /// نسبة الوقت ضمن النطاق الطبيعي ٠…١.
    public let inRange: Double
}

public struct DailyStat {
    public let day: Date
    public let count: Int
    public let score: Int
    public let band: HealthBand
    public let avgHeartRate: Double?
    public let maxHeartRate: Double?
    public let minSpo2: Double?
    public let maxTemp: Double?
}

public struct ReadingLine {
    public let date: Date
    public let heartRate: String
    public let spo2: String
    public let pressure: String
    public let temperature: String
    public let band: HealthBand
}

public struct HealthReport {
    public let employeeID: String
    public let period: ReportPeriod
    public let from: Date
    public let to: Date
    public let generatedAt: Date
    public let assessment: HealthAssessment
    public let summary: [IndicatorSummary]
    public let daily: [DailyStat]

    /// أحدث القراءات، مقصوصة عند `maxReadings` — تقرير شهر بالإرسال كل دقيقة يتجاوز ٤٠ ألف سطر.
    public let readings: [ReadingLine]
    /// العدد الكامل قبل القص، ليُذكر في التقرير بصدق.
    public let readingsTotal: Int
    /// سلسلة النبض للرسم البياني.
    public let heartRateSeries: [(date: Date, value: Double)]

    public var isEmpty: Bool { readings.isEmpty }
    public var isTruncated: Bool { readingsTotal > readings.count }
}

// MARK: - البناء

public enum HealthReportBuilder {
    public static func build(
        from samples: [VitalSample],
        employeeID: String,
        period: ReportPeriod,
        now: Date = Date(),
        maxReadings: Int = 400,
        config: HealthThresholds = .default
    ) -> HealthReport {
        let from = now.addingTimeInterval(-period.duration)
        let window = samples
            .filter { $0.sampleDate >= from && $0.sampleDate <= now }
            .sorted { $0.sampleDate < $1.sampleDate }

        let assessment = HealthEngine.assess(window, now: now, config: config)

        return HealthReport(
            employeeID: employeeID,
            period: period,
            from: from,
            to: now,
            generatedAt: now,
            assessment: assessment,
            summary: summaries(window, config: config),
            daily: dailyStats(window, config: config),
            readings: window.reversed().prefix(maxReadings).map { line(for: $0, config: config) },
            readingsTotal: window.count,
            heartRateSeries: window.compactMap { s in
                s.vHeartRate.map { (date: s.sampleDate, value: Double($0)) }
            }
        )
    }

    // MARK: ملخص كل مؤشر

    private static func summaries(_ window: [VitalSample],
                                  config: HealthThresholds) -> [IndicatorSummary] {
        var out: [IndicatorSummary] = []

        func add(_ kind: VitalKind, _ band: HealthThresholds.Band,
                 _ values: [Double], decimals: Int = 0) {
            guard let latest = values.last,
                  let lo = values.min(), let hi = values.max() else { return }

            let avg = values.reduce(0, +) / Double(values.count)
            let inRange = Double(values.filter { band.normal.contains($0) }.count) / Double(values.count)

            func f(_ v: Double) -> String {
                decimals == 0 ? "\(Int(v.rounded()))" : String(format: "%.\(decimals)f", v)
            }

            out.append(IndicatorSummary(
                kind: kind, latest: f(latest), minimum: f(lo),
                average: f(avg), maximum: f(hi),
                band: HealthEngine.classify(latest, band), inRange: inRange
            ))
        }

        add(.heartRate, config.heartRate, window.compactMap { $0.vHeartRate.map(Double.init) })
        add(.spo2, config.spo2, window.compactMap { $0.vSpo2.map(Double.init) })
        add(.bodyTemp, config.bodyTemp, window.compactMap { $0.bodyTemp }, decimals: 1)
        add(.pressure, config.systolic, window.compactMap { $0.systolic.map(Double.init) })

        return out
    }

    // MARK: التجميع اليومي

    private static func dailyStats(_ window: [VitalSample],
                                   config: HealthThresholds) -> [DailyStat] {
        let calendar = Calendar(identifier: .gregorian)
        let groups = Dictionary(grouping: window) { calendar.startOfDay(for: $0.sampleDate) }

        return groups.keys.sorted(by: >).map { day in
            let items = groups[day] ?? []
            let endOfDay = day.addingTimeInterval(24 * 3600 - 1)
            var dayConfig = config
            dayConfig.displayWindow = 24 * 3600
            let assessment = HealthEngine.assess(items, now: endOfDay, config: dayConfig)

            let hr = items.compactMap { $0.vHeartRate.map(Double.init) }
            let spo2 = items.compactMap { $0.vSpo2.map(Double.init) }
            let temp = items.compactMap { $0.bodyTemp }

            return DailyStat(
                day: day,
                count: items.count,
                score: assessment.score,
                band: assessment.band,
                avgHeartRate: hr.isEmpty ? nil : hr.reduce(0, +) / Double(hr.count),
                maxHeartRate: hr.max(),
                minSpo2: spo2.min(),
                maxTemp: temp.max()
            )
        }
    }

    // MARK: سطر قراءة

    private static func line(for s: VitalSample, config: HealthThresholds) -> ReadingLine {
        let single = HealthEngine.assess([s], now: s.sampleDate, config: config)
        return ReadingLine(
            date: s.sampleDate,
            heartRate: s.vHeartRate.map { "\($0)" } ?? "—",
            spo2: s.vSpo2.map { "\($0)%" } ?? "—",
            pressure: {
                guard let sys = s.systolic else { return "—" }
                guard let dia = s.diastolic else { return "\(sys)" }
                return "\(sys)/\(dia)"
            }(),
            temperature: s.bodyTemp.map { String(format: "%.1f", $0) } ?? "—",
            band: single.band
        )
    }
}

// MARK: - تنسيق التواريخ

public enum ReportFormat {
    public static let locale = Locale(identifier: "ar_SA")

    public static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "hh:mm a"
        return f
    }()

    public static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMMM"
        return f
    }()

    public static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EEEE d MMMM yyyy — hh:mm a"
        return f
    }()

    public static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f
    }()
}
