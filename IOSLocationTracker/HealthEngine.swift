//
//  HealthEngine.swift
//  SecurityPass
//
//  محرك التقييم الصحي والتنبؤ — يعمل بالكامل على الجهاز.
//  لا يضيف أي حقل، ولا يغيّر قاعدة البيانات أو بروتوكول الإرسال.
//  كل ما يحتاجه موجود أصلاً في سجلات المزامنة المخزّنة محلياً.
//
//  الإصدار ٣:
//  • دوال نقية: التقييم لا يكتب أي حالة. الذاكرة التراكمية (Leaky Bucket) تُعاد
//    بناؤها من السجل نفسه، فلا تُفسدها إعادة رسم الشاشة ولا تقييم تقرير أو قراءة قديمة.
//  • التنبؤ بمرشّح كالمان (مستوى + اتجاه) لكل مؤشر مع رفض القراءات الشاذة،
//    ويعمل من أول قراءة. الاحتمال هو احتمال بلوغ العتبة الحرجة خلال الأفق،
//    والثقة تُعرض منفصلة عنه بدل ضربه بالتغطية.
//

import Foundation

// MARK: - مصدر البيانات

/// البروتوكول الوحيد الذي يربط المحرك ببيانات التطبيق الحالية.
public protocol VitalSample {
    var sampleDate: Date { get }
    var vHeartRate: Int? { get }
    var vSpo2: Int? { get }
    var systolic: Int? { get }
    var diastolic: Int? { get }
    var bodyTemp: Double? { get }
    var vLatitude: Double? { get }
    var vLongitude: Double? { get }
}

// MARK: - الإعدادات (ملف ضبط واحد)

public struct HealthThresholds {
    /// نطاق مؤشر واحد: الطبيعي، والعتبتان الحرجتان التي تصل عندهما الدرجة إلى صفر.
    public struct Band {
        public var normal: ClosedRange<Double>
        public var criticalLow: Double
        public var criticalHigh: Double
        public init(normal: ClosedRange<Double>, criticalLow: Double, criticalHigh: Double) {
            self.normal = normal
            self.criticalLow = criticalLow
            self.criticalHigh = criticalHigh
        }
    }

    /// الطبيعي حتى ١٢٠ نبضة، والحرج من ١٤٠.
    public var heartRate = Band(normal: 60...120, criticalLow: 40, criticalHigh: 140)
    public var spo2      = Band(normal: 95...100, criticalLow: 90, criticalHigh: 100)
    public var bodyTemp  = Band(normal: 36.1...37.2, criticalLow: 35.0, criticalHigh: 38.0)
    public var systolic  = Band(normal: 90...129, criticalLow: 85, criticalHigh: 140)
    /// الانحراف المعياري للنبض خلال آخر ١٥ دقيقة.
    public var stability = Band(normal: 0...8, criticalLow: 0, criticalHigh: 15)

    public var weightHeartRate: Double = 30
    public var weightSpo2: Double      = 25
    public var weightBodyTemp: Double  = 20
    public var weightPressure: Double  = 15
    public var weightStability: Double = 10

    /// نافذة حساب التذبذب ومعاينة الاتجاه في الشاشة.
    public var trendWindow: TimeInterval = 40 * 60
    /// أفق الإسقاط.
    public var forecastHorizon: TimeInterval = 60 * 60
    /// نافذة العرض في الشاشة.
    public var displayWindow: TimeInterval = 6 * 3600
    /// الفاصل المتوقع بين قراءتين (الإرسال التلقائي كل دقيقة).
    public var expectedInterval: TimeInterval = 60
    /// احتفظ به للتوافق — التنبؤ يعمل الآن من أول قراءة وتُعرض ثقته بدلاً من حجبه.
    public var minimumCoverageForForecast: Double = 0.40
    /// مدة التجاوز المتواصل قبل اعتبار الحالة إنذاراً.
    public var sustainedBreach: TimeInterval = 0

    public static let `default` = HealthThresholds()
    public init() {}
}

// MARK: - النتائج

public enum VitalBand: String {
    case normal
    case caution
    case critical
    case unknown
}

public enum HealthBand: String, Codable {
    case excellent   // ٨٥–١٠٠
    case good        // ٧٠–٨٤
    case attention   // ٥٠–٦٩
    case danger      // ٠–٤٩

    public var title: String {
        switch self {
        case .excellent: return "ممتاز"
        case .good:      return "جيد"
        case .attention: return "يحتاج انتباه"
        case .danger:    return "خطر"
        }
    }

    /// ترتيب الخطورة — المقارنة بـ rawValue كانت أبجدية لا منطقية.
    public var severity: Int {
        switch self {
        case .excellent: return 0
        case .good:      return 1
        case .attention: return 2
        case .danger:    return 3
        }
    }

    static func from(score: Int) -> HealthBand {
        switch score {
        case 85...:  return .excellent
        case 70..<85: return .good
        case 50..<70: return .attention
        default:      return .danger
        }
    }
}

public enum VitalKind: String, CaseIterable {
    case heartRate, spo2, bodyTemp, pressure, stability

    /// المؤشرات المقاسة فعلاً (الاستقرار مشتق من النبض).
    public static let vitals: [VitalKind] = [.heartRate, .spo2, .bodyTemp, .pressure]

    public var title: String {
        switch self {
        case .heartRate: return "نبض القلب"
        case .spo2:      return "الأكسجين"
        case .bodyTemp:  return "حرارة الجسم"
        case .pressure:  return "ضغط الدم"
        case .stability: return "الاستقرار"
        }
    }

    public var iconEmoji: String {
        switch self {
        case .heartRate: return "🫀"
        case .spo2:      return "🫁"
        case .bodyTemp:  return "🌡️"
        case .pressure:  return "🩸"
        case .stability: return "⏱️"
        }
    }

    public var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .spo2:      return "%"
        case .bodyTemp:  return "°م"
        case .pressure:  return ""
        case .stability: return ""
        }
    }
}

public struct IndicatorReading {
    public let kind: VitalKind
    public let value: Double
    public let display: String
    public let band: VitalBand
    public let score: Double      // ٠…١٠٠
    public let weight: Double
    public let trend: Trend?
}

public struct Trend {
    public enum Direction { case rising, falling, steady }

    /// وحدة المؤشر لكل دقيقة (ميل مرشّح كالمان).
    public let slopePerMinute: Double
    /// ثقة الاتجاه ٠…١: نسبة قوة الميل إلى عدم اليقين فيه.
    public let rSquared: Double
    /// القيمة المتوقعة بعد أفق الإسقاط.
    public let projected: Double
    /// الدقائق المتبقية لبلوغ عتبة الإنذار، إن كان الاتجاه يقود إليها.
    public let minutesToThreshold: Double?
    /// الانحراف المعياري لتقدير الميل.
    public let slopeSD: Double
    /// هل الميل حقيقي أم ضجيج قياس؟
    public let isSignificant: Bool

    public var direction: Direction {
        guard isSignificant else { return .steady }
        return slopePerMinute > 0 ? .rising : .falling
    }

    public var directionTitle: String {
        switch direction {
        case .rising:  return "صاعد ↗"
        case .falling: return "هابط ↘"
        case .steady:  return "مستقر ↔"
        }
    }
}

public struct HealthAssessment {
    public let score: Int
    public let band: HealthBand
    public let headline: String
    public let indicators: [IndicatorReading]
    /// اكتمال القراءات وحداثتها ٠…١ — هي «دقة التقييم» المعروضة.
    public let coverage: Double
    public let sampleCount: Int
    public let updatedAt: Date?

    public var isEmpty: Bool { indicators.isEmpty }
}

public struct RiskForecast: Identifiable {
    public enum Level: String {
        case low, medium, high
        public var title: String {
            switch self {
            case .low:    return "منخفض"
            case .medium: return "متوسط"
            case .high:   return "مرتفع"
            }
        }
        var rank: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }
    }

    public let id: String
    public let name: String
    public let probability: Double   // ٠…١
    public let level: Level
    public let why: String
    public let tags: [String]
    public var kind: VitalKind? = nil
    /// الدقائق المتوقعة لبلوغ الحد الحرج وفق الاتجاه الحالي.
    public var minutesToThreshold: Double? = nil
}

public struct ForecastResult {
    public let risks: [RiskForecast]
    public let projectedScore: Int?
    public let coverage: Double
    /// صحيح فقط عند عدم وجود أي قراءة حديثة — التنبؤ يبدأ من أول قراءة.
    public let insufficientCoverage: Bool
    /// ثقة التنبؤ ٠…١ — تكبر مع عدد القراءات وحداثتها.
    public var confidence: Double = 0
    /// عدد القراءات المقبولة لأكثر المؤشرات اكتمالاً.
    public var sampleCount: Int = 0
    /// تنبؤ أولي مبني على قراءات قليلة.
    public var isPreliminary: Bool = true
    public var horizonMinutes: Int = 60
}

/// تغيّر سريع في مؤشر خلال دقائق.
public struct VitalChange {
    public let kind: VitalKind
    public let from: Double
    public let to: Double
    public let minutes: Int
    public var isRise: Bool { to > from }
}

/// نوبة تجاوز حرج متواصلة لمؤشر واحد.
public struct HealthEpisode: Identifiable {
    public let id = UUID()
    public let kind: VitalKind
    public let start: Date
    public let end: Date
    /// أسوأ قيمة خلال النوبة.
    public let peak: Double
    public let readings: Int
    /// صحيح عند الارتفاع فوق الحد، خطأ عند الانخفاض تحته.
    public let isHigh: Bool

    public var durationMinutes: Int {
        max(1, Int((end.timeIntervalSince(start) / 60).rounded()) + 1)
    }
}

// MARK: - المحرك

public enum HealthEngine {

    // MARK: ثوابت الذاكرة التراكمية
    public static let hrLoadWeight = 1.0
    public static let spo2LoadWeight = 5.0
    public static let tempLoadWeight = 2.0
    public static let recoveryRate = 0.3
    public static let acuteCriticalThresholdMinutes = 5

    /// المدى الزمني لبناء مسار كالمان.
    static let trackLookback: TimeInterval = 120 * 60
    /// بعد هذه المدة بلا قراءة لا يصدر تنبؤ للمؤشر.
    static let staleAfter: TimeInterval = 30 * 60

    // MARK: - التقييم اللحظي

    public static func assess(
        _ samples: [VitalSample],
        now: Date = Date(),
        config: HealthThresholds = .default
    ) -> HealthAssessment {
        let window = prepared(samples, from: now.addingTimeInterval(-config.displayWindow), to: now)
        let cvg = coverage(window, from: now.addingTimeInterval(-config.displayWindow), to: now, config: config)

        guard let latest = window.last else {
            return emptyAssessment(headline: "لا توجد بيانات كافية")
        }

        let loads = replayLoads(window, config: config)
        var indicators: [IndicatorReading] = []
        var weighted = 0.0
        var totalWeight = 0.0
        var worst: HealthBand = .excellent

        for kind in VitalKind.vitals {
            guard let v = current(kind, in: window) else { continue }
            let w = weight(kind, config)
            // كل نقطة حمل تراكمي تخصم درجتين: لا يعود المؤشر أخضر مع إجهاد متراكم.
            let s = max(0, subScore(v, band(kind, config)) - loads.value(for: kind) * 2.0)
            let hb = HealthBand.from(score: Int(s))
            if hb.severity > worst.severity { worst = hb }

            indicators.append(IndicatorReading(
                kind: kind, value: v, display: format(v, kind), band: vitalBand(score: s),
                score: s, weight: w,
                trend: track(kind, window, now: now).map { trend($0, kind: kind, config: config, now: now) }
            ))
            weighted += s * w
            totalWeight += w
        }

        guard totalWeight > 0 else {
            return emptyAssessment(headline: "لا توجد قراءات حيوية — السوار غير متصل", count: window.count, at: latest.sampleDate)
        }

        if let sd = heartRateVariability(window, endingAt: latest.sampleDate) {
            let s = subScore(sd, config.stability)
            indicators.append(IndicatorReading(
                kind: .stability, value: sd,
                display: sd <= config.stability.normal.upperBound ? "مستقر" : "متذبذب",
                band: classify(sd, config.stability), score: s, weight: config.weightStability, trend: nil
            ))
            weighted += s * config.weightStability
            totalWeight += config.weightStability
        }

        var finalScore = Int((weighted / totalWeight).rounded())
        // السقف المطلق لأسوأ مؤشر — المتوسط لا يُخفي مؤشراً خطراً.
        if worst == .danger && finalScore > 49 { finalScore = 49 }
        else if worst == .attention && finalScore > 74 { finalScore = 74 }

        let overall = HealthBand.from(score: finalScore)
        return HealthAssessment(
            score: finalScore, band: overall,
            headline: headline(band: overall, indicators: indicators, loads: loads),
            indicators: indicators, coverage: cvg, sampleCount: window.count, updatedAt: latest.sampleDate
        )
    }

    // MARK: - التنبؤ

    /// - Parameter fatigue: إرهاق من قلة النوم ٠…١ (من `SleepStore`). يُمرَّر صفراً في التقارير المشتركة
    ///   حتى لا تتسرّب بيانات النوم الخاصة إليها.
    public static func forecast(
        _ samples: [VitalSample],
        now: Date = Date(),
        config: HealthThresholds = .default,
        fatigue: Double = 0
    ) -> ForecastResult {
        let horizonMinutes = Int(config.forecastHorizon / 60)
        let window = prepared(samples, from: now.addingTimeInterval(-config.displayWindow), to: now)
        let cvg = coverage(window, from: now.addingTimeInterval(-config.displayWindow), to: now, config: config)

        guard let latest = window.last, now.timeIntervalSince(latest.sampleDate) <= staleAfter else {
            return ForecastResult(risks: [], projectedScore: nil, coverage: cvg, insufficientCoverage: true,
                                  confidence: 0, sampleCount: 0, isPreliminary: true, horizonMinutes: horizonMinutes)
        }

        let loads = replayLoads(window, config: config)
        let horizon = config.forecastHorizon / 60
        var risks: [RiskForecast] = []
        var projectedWeighted = 0.0
        var projectedWeight = 0.0
        var trackedCount = 0
        var worstProjected: HealthBand = .excellent

        for kind in VitalKind.vitals {
            guard let t = track(kind, window, now: now),
                  now.timeIntervalSince(t.lastTime) <= staleAfter else { continue }
            let m = model(kind)
            let b = band(kind, config)
            let w = weight(kind, config)
            let lag = max(0, now.timeIntervalSince(t.lastTime) / 60)
            trackedCount = max(trackedCount, t.accepted)

            let projected = clamp(t.project(minutes: horizon + lag, model: m).mean, m.plausible)
            let projectedSub = subScore(projected, b)
            projectedWeighted += projectedSub * w
            projectedWeight += w
            let pb = HealthBand.from(score: Int(projectedSub))
            if pb.severity > worstProjected.severity { worstProjected = pb }

            let crit = criticalLimits(kind, config)
            let norm = normalLimits(kind, config)
            let load = min(1, loads.value(for: kind) / 100)
            let tired = min(1, max(0, fatigue))
            // الإجهاد المتراكم يرفع الاحتمال بحد أقصى ربع المسافة المتبقية، وقلة النوم بحد أقصى ١٥٪ منها.
            let pCrit = 1 - (1 - crossingProbability(t, model: m, now: now, horizon: horizon,
                                                     upper: crit.upper, lower: crit.lower))
                * (1 - 0.25 * load) * (1 - 0.15 * tired)
            let pOut = crossingProbability(t, model: m, now: now, horizon: horizon,
                                           upper: norm.upper, lower: norm.lower)
            let tr = trend(t, kind: kind, config: config, now: now)

            let level: RiskForecast.Level
            let probability: Double
            let name: String
            if pCrit >= 0.6 {
                level = .high; probability = pCrit; name = "احتمال تجاوز \(kind.title) الحد الحرج"
            } else if pCrit >= 0.3 {
                level = .medium; probability = pCrit; name = "احتمال تجاوز \(kind.title) الحد الحرج"
            } else if pOut >= 0.6 && b.normal.contains(t.level) {
                level = .low; probability = pOut; name = "احتمال خروج \(kind.title) عن النطاق الطبيعي"
            } else {
                continue
            }

            var tags = [kind.title]
            if tr.direction != .steady { tags.append(tr.direction == .rising ? "ارتفاع مستمر" : "هبوط مستمر") }
            if load > 0.5 { tags.append("إجهاد متراكم") }
            if tired >= 0.5 { tags.append("قلة نوم") }
            if t.accepted < 10 { tags.append("تقدير أولي") }

            risks.append(RiskForecast(
                id: kind.rawValue, name: name, probability: probability, level: level,
                why: explain(kind: kind, track: t, trend: tr, load: load, tired: tired, config: config),
                tags: tags, kind: kind, minutesToThreshold: tr.minutesToThreshold
            ))
        }

        if trackedCount == 0 {
            return ForecastResult(risks: [], projectedScore: nil, coverage: cvg, insufficientCoverage: true,
                                  confidence: 0, sampleCount: 0, isPreliminary: true, horizonMinutes: horizonMinutes)
        }

        var projectedScore = Int((projectedWeighted / max(projectedWeight, 1)).rounded())
        if worstProjected == .danger && projectedScore > 49 { projectedScore = 49 }
        else if worstProjected == .attention && projectedScore > 74 { projectedScore = 74 }

        // الثقة: تكبر مع عدد القراءات (تشبع قرب ٢٠ قراءة) وتتراجع مع قِدم آخر قراءة.
        let age = now.timeIntervalSince(latest.sampleDate)
        let freshness = age <= 5 * 60 ? 1 : exp(-(age - 5 * 60) / (15 * 60))
        let confidence = (1 - exp(-Double(trackedCount) / 8)) * freshness

        return ForecastResult(
            risks: risks.sorted {
                $0.level.rank != $1.level.rank ? $0.level.rank > $1.level.rank : $0.probability > $1.probability
            },
            projectedScore: projectedScore,
            coverage: cvg,
            insufficientCoverage: false,
            confidence: confidence,
            sampleCount: trackedCount,
            isPreliminary: trackedCount < 10,
            horizonMinutes: horizonMinutes
        )
    }

    // MARK: - تقييم فترة (للتقارير والسجل اليومي)

    /// يقيّم فترة كاملة لا اللحظة الأخيرة: متوسط الدرجات مع وزن مماثل لأسوأ ١٠٪ من الوقت،
    /// وأي نوبة تجاوز حرج متواصلة تسقف المؤشر في نطاق الخطر.
    public static func assessPeriod(
        _ samples: [VitalSample],
        from: Date,
        to: Date,
        config: HealthThresholds = .default
    ) -> HealthAssessment {
        let window = prepared(samples, from: from, to: to)
        guard let latest = window.last else {
            return emptyAssessment(headline: "لا توجد قراءات في هذه الفترة")
        }

        let eps = episodes(window, config: config)
        var indicators: [IndicatorReading] = []
        var weighted = 0.0
        var totalWeight = 0.0
        var worst: HealthBand = .excellent

        for kind in VitalKind.vitals {
            let values = window.compactMap { value($0, kind) }
            guard !values.isEmpty else { continue }
            let b = band(kind, config)
            let w = weight(kind, config)
            let scores = values.map { subScore($0, b) }.sorted()
            let mean = scores.reduce(0, +) / Double(scores.count)
            var s = 0.5 * mean + 0.5 * percentile(scores, 0.10)
            if eps.contains(where: { $0.kind == kind }) { s = min(s, 49) }

            let hb = HealthBand.from(score: Int(s))
            if hb.severity > worst.severity { worst = hb }
            let med = median(values)
            indicators.append(IndicatorReading(
                kind: kind, value: med, display: format(med, kind), band: vitalBand(score: s),
                score: s, weight: w, trend: nil
            ))
            weighted += s * w
            totalWeight += w
        }

        guard totalWeight > 0 else {
            return emptyAssessment(headline: "لا توجد قراءات حيوية في هذه الفترة", count: window.count, at: latest.sampleDate)
        }

        var finalScore = Int((weighted / totalWeight).rounded())
        if worst == .danger && finalScore > 49 { finalScore = 49 }
        else if worst == .attention && finalScore > 74 { finalScore = 74 }
        let overall = HealthBand.from(score: finalScore)

        let headline: String
        if eps.isEmpty {
            headline = overall.severity <= 1
                ? "لم تُسجَّل أي نوبة تجاوز حرج خلال الفترة، والمؤشرات ضمن النطاق في معظم الوقت."
                : "لم تُسجَّل نوبات تجاوز حرج، لكن بعض المؤشرات خرجت عن النطاق الطبيعي لفترات ملحوظة."
        } else {
            let longest = eps.map { $0.durationMinutes }.max() ?? 0
            let kinds = Array(Set(eps.map { $0.kind.title })).sorted().joined(separator: "، ")
            headline = "سُجّلت \(eps.count) نوبة تجاوز حرج (\(kinds))، أطولها \(longest) دقيقة."
        }

        return HealthAssessment(
            score: finalScore, band: overall, headline: headline, indicators: indicators,
            coverage: coverage(window, from: from, to: to, config: config),
            sampleCount: window.count, updatedAt: latest.sampleDate
        )
    }

    /// النوبات الحرجة: قراءتان متتاليتان على الأقل خارج الحد الحرج، بلا فجوة تتجاوز ٣ دقائق.
    public static func episodes(
        _ samples: [VitalSample],
        config: HealthThresholds = .default,
        minReadings: Int = 2,
        maxGap: TimeInterval = 180
    ) -> [HealthEpisode] {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }
        var out: [HealthEpisode] = []

        for kind in VitalKind.vitals {
            let limits = criticalLimits(kind, config)
            var run: (start: Date, end: Date, peak: Double, count: Int, high: Bool)?

            func flush() {
                if let o = run, o.count >= minReadings {
                    out.append(HealthEpisode(kind: kind, start: o.start, end: o.end, peak: o.peak,
                                             readings: o.count, isHigh: o.high))
                }
                run = nil
            }

            for s in sorted {
                guard let v = value(s, kind) else { continue }
                let high = limits.upper.map { v >= $0 } ?? false
                let low = limits.lower.map { v <= $0 } ?? false
                guard high || low else { flush(); continue }

                if let o = run, o.high == high, s.sampleDate.timeIntervalSince(o.end) <= maxGap {
                    run = (o.start, s.sampleDate, high ? max(o.peak, v) : min(o.peak, v), o.count + 1, high)
                } else {
                    flush()
                    run = (s.sampleDate, s.sampleDate, v, 1, high)
                }
            }
            flush()
        }
        return out.sorted { $0.start > $1.start }
    }

    /// التغيّرات السريعة: وسيط آخر ٣ دقائق مقابل وسيط فترة سابقة.
    /// النبض ±٢٥ خلال ٥–١٥ دقيقة، الأكسجين هبوط ٤ نقاط، الحرارة ±٠٫٨ خلال ١٠–٣٠ دقيقة.
    /// الوسيط على الطرفين يمنع قراءة حركة واحدة من إطلاق تنبيه.
    public static func rapidChanges(_ samples: [VitalSample], config: HealthThresholds = .default) -> [VitalChange] {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }
        guard let end = sorted.last?.sampleDate else { return [] }

        func values(_ kind: VitalKind, from a: TimeInterval, to b: TimeInterval) -> [(Date, Double)] {
            sorted.compactMap { s in
                let age = end.timeIntervalSince(s.sampleDate)
                guard age >= a, age <= b, let v = value(s, kind) else { return nil }
                return (s.sampleDate, v)
            }
        }

        let rules: [(VitalKind, earlier: (TimeInterval, TimeInterval), rise: Double?, drop: Double?)] = [
            (.heartRate, (5 * 60, 15 * 60), 25, 25),
            (.spo2, (5 * 60, 15 * 60), nil, 4),
            (.bodyTemp, (10 * 60, 30 * 60), 0.8, 0.8)
        ]

        var out: [VitalChange] = []
        for rule in rules {
            let now = values(rule.0, from: 0, to: 3 * 60)
            let before = values(rule.0, from: rule.earlier.0, to: rule.earlier.1)
            guard now.count >= 2, before.count >= 2 else { continue }
            let a = median(before.map { $0.1 })
            let b = median(now.map { $0.1 })
            let mid = before[before.count / 2].0
            let minutes = max(1, Int((end.timeIntervalSince(mid) / 60).rounded()))
            if let r = rule.rise, b - a >= r {
                out.append(VitalChange(kind: rule.0, from: a, to: b, minutes: minutes))
            } else if let d = rule.drop, a - b >= d {
                out.append(VitalChange(kind: rule.0, from: a, to: b, minutes: minutes))
            }
        }
        return out
    }

    /// المسافة بالأمتار بين نقطتين (خط عرض، خط طول).
    public static func distanceMeters(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        distance(a, b)
    }

    /// تصنيف قراءة منفردة بلا ذاكرة — لصفوف السجل والتقارير.
    public static func quickBand(_ sample: VitalSample, config: HealthThresholds = .default) -> HealthBand {
        var weighted = 0.0
        var total = 0.0
        var worst: HealthBand = .excellent
        for kind in VitalKind.vitals {
            guard let v = value(sample, kind) else { continue }
            let s = subScore(v, band(kind, config))
            let w = weight(kind, config)
            weighted += s * w
            total += w
            let hb = HealthBand.from(score: Int(s))
            if hb.severity > worst.severity { worst = hb }
        }
        guard total > 0 else { return .good }
        var score = Int((weighted / total).rounded())
        if worst == .danger && score > 49 { score = 49 }
        else if worst == .attention && score > 74 { score = 74 }
        return HealthBand.from(score: score)
    }

    // MARK: - أدوات عامة

    public static func classify(_ v: Double, _ b: HealthThresholds.Band) -> VitalBand {
        if b.normal.contains(v) { return .normal }
        if v >= b.criticalHigh || v <= b.criticalLow { return .critical }
        return .caution
    }

    public static func subScore(_ v: Double, _ b: HealthThresholds.Band) -> Double {
        if b.normal.contains(v) { return 100 }
        if v > b.normal.upperBound {
            let span = b.criticalHigh - b.normal.upperBound
            guard span > 0 else { return 0 }
            return max(0, 100 - (v - b.normal.upperBound) / span * 100)
        }
        let span = b.normal.lowerBound - b.criticalLow
        guard span > 0 else { return 0 }
        return max(0, 100 - (b.normal.lowerBound - v) / span * 100)
    }

    public static func isStationary(_ samples: [VitalSample], metres: Double = 20) -> Bool {
        let points = samples.compactMap { s -> (Double, Double)? in
            guard let la = s.vLatitude, let lo = s.vLongitude else { return nil }
            return (la, lo)
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return false }
        return distance(first, last) < metres
    }

    /// القيمة المقاسة لمؤشر بعد استبعاد المستحيل فسيولوجياً (حرارة ٠ = السوار لم يقسها).
    public static func value(_ s: VitalSample, _ kind: VitalKind) -> Double? {
        let v: Double?
        switch kind {
        case .heartRate: v = s.vHeartRate.map(Double.init)
        case .spo2:      v = s.vSpo2.map(Double.init)
        case .bodyTemp:  v = s.bodyTemp
        case .pressure:  v = s.systolic.map(Double.init)
        case .stability: v = nil
        }
        guard let x = v, model(kind).plausible.contains(x) else { return nil }
        return x
    }

    public static func band(_ kind: VitalKind, _ config: HealthThresholds) -> HealthThresholds.Band {
        switch kind {
        case .heartRate: return config.heartRate
        case .spo2:      return config.spo2
        case .bodyTemp:  return config.bodyTemp
        case .pressure:  return config.systolic
        case .stability: return config.stability
        }
    }

    public static func format(_ v: Double, _ kind: VitalKind) -> String {
        kind == .bodyTemp ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
    }

    // MARK: - نموذج القياس لكل مؤشر

    struct VitalModel {
        /// انحراف القياس المعياري للسوار.
        let noise: Double
        /// ضجيج عملية الميل (q) — مدى سرعة تغيّر الاتجاه نفسه.
        let slopeNoise: Double
        /// ضجيج عملية المستوى.
        let levelNoise: Double
        /// عدم اليقين المبدئي في الميل (وحدة/دقيقة) قبل توفر قراءات.
        let slopePrior: Double
        let plausible: ClosedRange<Double>
    }

    /// معاملات معايرة باختبار رجعي على سيناريوهات ارتفاع تدريجي ومفاجئ وشبه-تجاوز.
    static func model(_ kind: VitalKind) -> VitalModel {
        switch kind {
        case .heartRate: return VitalModel(noise: 2.0, slopeNoise: 0.004, levelNoise: 0.1, slopePrior: 0.3, plausible: 30...220)
        case .spo2:      return VitalModel(noise: 1.0, slopeNoise: 0.00016, levelNoise: 0.01, slopePrior: 0.06, plausible: 70...100)
        case .bodyTemp:  return VitalModel(noise: 0.1, slopeNoise: 0.00001, levelNoise: 0.00025, slopePrior: 0.01, plausible: 33...42.5)
        case .pressure:  return VitalModel(noise: 3.0, slopeNoise: 0.004, levelNoise: 0.1, slopePrior: 0.3, plausible: 70...230)
        case .stability: return VitalModel(noise: 1.0, slopeNoise: 0.001, levelNoise: 0.05, slopePrior: 0.1, plausible: 0...100)
        }
    }

    static func weight(_ kind: VitalKind, _ config: HealthThresholds) -> Double {
        switch kind {
        case .heartRate: return config.weightHeartRate
        case .spo2:      return config.weightSpo2
        case .bodyTemp:  return config.weightBodyTemp
        case .pressure:  return config.weightPressure
        case .stability: return config.weightStability
        }
    }

    static func criticalLimits(_ kind: VitalKind, _ config: HealthThresholds) -> (upper: Double?, lower: Double?) {
        switch kind {
        case .heartRate: return (config.heartRate.criticalHigh, config.heartRate.criticalLow)
        case .spo2:      return (nil, config.spo2.criticalLow)   // لا خطر في ارتفاع الأكسجين
        case .bodyTemp:  return (config.bodyTemp.criticalHigh, config.bodyTemp.criticalLow)
        case .pressure:  return (config.systolic.criticalHigh, config.systolic.criticalLow)
        case .stability: return (nil, nil)
        }
    }

    static func normalLimits(_ kind: VitalKind, _ config: HealthThresholds) -> (upper: Double?, lower: Double?) {
        let b = band(kind, config)
        return (kind == .spo2 ? nil : b.normal.upperBound, b.normal.lowerBound)
    }

    // MARK: - مرشّح كالمان (مستوى + اتجاه)

    struct Track {
        var level: Double
        var slope: Double
        var p00: Double
        var p01: Double
        var p11: Double
        var lastTime: Date
        var accepted: Int
        var rejected: Int

        /// توزيع القيمة بعد h دقيقة من آخر قراءة.
        func project(minutes h: Double, model m: VitalModel) -> (mean: Double, sd: Double) {
            var v = p00 + 2 * h * p01 + h * h * p11
            v += m.slopeNoise * h * h * h / 3 + m.levelNoise * h + m.noise * m.noise
            return (level + slope * h, max(v, 1e-9).squareRoot())
        }
    }

    static func track(_ kind: VitalKind, _ sorted: [VitalSample], now: Date) -> Track? {
        let m = model(kind)
        let points: [(Date, Double)] = sorted.compactMap { s in
            guard s.sampleDate <= now, now.timeIntervalSince(s.sampleDate) <= trackLookback,
                  let v = value(s, kind) else { return nil }
            return (s.sampleDate, v)
        }
        guard let first = points.first else { return nil }

        let r = m.noise * m.noise
        var t = Track(level: first.1, slope: 0, p00: r * 4, p01: 0, p11: m.slopePrior * m.slopePrior,
                      lastTime: first.0, accepted: 1, rejected: 0)
        var pendingSide = 0

        for (date, y) in points.dropFirst() {
            let dt = max(0.5, date.timeIntervalSince(t.lastTime) / 60)
            t.lastTime = date

            // التنبؤ بالخطوة
            t.level += t.slope * dt
            let p00 = t.p00 + 2 * dt * t.p01 + dt * dt * t.p11 + m.slopeNoise * dt * dt * dt / 3 + m.levelNoise * dt
            let p01 = t.p01 + dt * t.p11 + m.slopeNoise * dt * dt / 2
            let p11 = t.p11 + m.slopeNoise * dt
            t.p00 = p00
            t.p01 = p01
            t.p11 = p11

            // بوابة القراءات الشاذة (٤ انحرافات معيارية)
            let s = t.p00 + r
            let innovation = y - t.level
            if innovation * innovation > 16 * s {
                let side = innovation > 0 ? 1 : -1
                if pendingSide == side {
                    // قراءتان شاذتان متتاليتان في الاتجاه نفسه: تغيّر حقيقي لا ضجيج حركة.
                    t.level = y
                    t.p00 = r * 2
                    t.p01 = 0
                    t.p11 += m.slopePrior * m.slopePrior
                    t.accepted += 1
                    pendingSide = 0
                } else {
                    pendingSide = side
                    t.rejected += 1
                }
                continue
            }
            pendingSide = 0

            // التصحيح
            let k0 = t.p00 / s
            let k1 = t.p01 / s
            t.level += k0 * innovation
            t.slope += k1 * innovation
            let n00 = (1 - k0) * t.p00
            let n01 = (1 - k0) * t.p01
            let n11 = t.p11 - k1 * t.p01
            t.p00 = n00
            t.p01 = n01
            t.p11 = max(n11, 1e-9)
            t.accepted += 1
        }
        return t
    }

    static func trend(_ t: Track, kind: VitalKind, config: HealthThresholds, now: Date) -> Trend {
        let m = model(kind)
        let horizon = config.forecastHorizon / 60
        let lag = max(0, now.timeIntervalSince(t.lastTime) / 60)
        let sd = t.p11.squareRoot()
        let signal = t.slope * t.slope
        let limits = criticalLimits(kind, config)
        return Trend(
            slopePerMinute: t.slope,
            rSquared: signal / (signal + t.p11),
            projected: clamp(t.level + t.slope * (horizon + lag), m.plausible),
            minutesToThreshold: minutesToCross(t, lag: lag, upper: limits.upper, lower: limits.lower),
            slopeSD: sd,
            // ميل يتجاوز ضعفي عدم يقينه ويحرّك القيمة انحرافاً معيارياً واحداً على الأقل خلال ٣٠ دقيقة.
            isSignificant: abs(t.slope) > 2 * sd && abs(t.slope) * 30 >= m.noise
        )
    }

    /// احتمال أن يبلغ المسار العتبة خلال الأفق: أقصى احتمال على شبكة كل ٥ دقائق.
    static func crossingProbability(_ t: Track, model m: VitalModel, now: Date, horizon: Double,
                                    upper: Double?, lower: Double?) -> Double {
        let lag = max(0, now.timeIntervalSince(t.lastTime) / 60)
        var best = 0.0
        var h = 5.0
        while h <= horizon + 0.001 {
            let p = t.project(minutes: h + lag, model: m)
            if let u = upper { best = max(best, normalCDF((p.mean - u) / p.sd)) }
            if let l = lower { best = max(best, normalCDF((l - p.mean) / p.sd)) }
            h += 5
        }
        return best
    }

    static func minutesToCross(_ t: Track, lag: Double, upper: Double?, lower: Double?) -> Double? {
        var candidates: [Double] = []
        if let u = upper, t.slope > 1e-6, t.level < u { candidates.append((u - t.level) / t.slope - lag) }
        if let l = lower, t.slope < -1e-6, t.level > l { candidates.append((l - t.level) / t.slope - lag) }
        return candidates.filter { $0 > 0 && $0 <= 180 }.min()
    }

    static func normalCDF(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    // MARK: - الذاكرة التراكمية (تُعاد من السجل)

    struct Loads {
        var hr = 0.0
        var spo2 = 0.0
        var temp = 0.0

        func value(for kind: VitalKind) -> Double {
            switch kind {
            case .heartRate: return hr
            case .spo2:      return spo2
            case .bodyTemp:  return temp
            default:         return 0
            }
        }
    }

    /// يعيد تشغيل الدلو المتسرّب على نافذة القراءات بالترتيب الزمني.
    /// يستعمل وسيط آخر ٣ قراءات حتى لا تضيف قراءة حركة شاذة واحدة حِملاً.
    static func replayLoads(_ sorted: [VitalSample], config: HealthThresholds) -> Loads {
        var loads = Loads()
        var last: Date?
        var recent: [VitalKind: [Double]] = [:]

        for s in sorted {
            let elapsed = last.map { min(5.0, max(0, s.sampleDate.timeIntervalSince($0) / 60)) } ?? 1.0
            if let l = last, s.sampleDate.timeIntervalSince(l) > 10 * 60 { recent.removeAll() }
            last = s.sampleDate

            func robust(_ kind: VitalKind) -> Double? {
                guard let v = value(s, kind) else { return nil }
                var buffer = recent[kind] ?? []
                buffer.append(v)
                if buffer.count > 3 { buffer.removeFirst() }
                recent[kind] = buffer
                return buffer.count < 3 ? v : median(buffer)
            }

            if let hr = robust(.heartRate) {
                if hr >= config.heartRate.criticalHigh || hr <= config.heartRate.criticalLow {
                    loads.hr = min(100, loads.hr + hrLoadWeight * elapsed * 2.0)
                } else if config.heartRate.normal.contains(hr) {
                    loads.hr = max(0, loads.hr - recoveryRate * elapsed)
                }
            }
            if let spo2 = robust(.spo2) {
                if spo2 <= config.spo2.criticalLow {
                    loads.spo2 = min(100, loads.spo2 + spo2LoadWeight * elapsed * 2.0)
                } else if config.spo2.normal.contains(spo2) {
                    loads.spo2 = max(0, loads.spo2 - recoveryRate * elapsed)
                }
            }
            if let temp = robust(.bodyTemp) {
                if temp >= config.bodyTemp.criticalHigh {
                    loads.temp = min(100, loads.temp + tempLoadWeight * elapsed * 2.0)
                } else if config.bodyTemp.normal.contains(temp) {
                    loads.temp = max(0, loads.temp - recoveryRate * elapsed)
                }
            }
        }
        return loads
    }

    // MARK: - مساعدات داخلية

    static func prepared(_ samples: [VitalSample], from: Date, to: Date) -> [VitalSample] {
        samples
            .filter { $0.sampleDate >= from && $0.sampleDate <= to }
            .sorted { $0.sampleDate < $1.sampleDate }
    }

    /// القيمة الحالية المتينة: وسيط آخر ٣ قراءات خلال ٥ دقائق.
    /// قراءة حركة شاذة واحدة لا تغيّر الحالة، والتغيّر الحقيقي يظهر من القراءة الثانية.
    static func current(_ kind: VitalKind, in sorted: [VitalSample]) -> Double? {
        guard let lastDate = sorted.last(where: { value($0, kind) != nil })?.sampleDate else { return nil }
        let recent = sorted
            .filter { lastDate.timeIntervalSince($0.sampleDate) <= 5 * 60 && $0.sampleDate <= lastDate }
            .compactMap { value($0, kind) }
            .suffix(3)
        guard let latest = recent.last else { return nil }
        return recent.count < 3 ? latest : median(Array(recent))
    }

    /// تذبذب النبض خلال آخر ١٥ دقيقة (٣ قراءات على الأقل): انحراف معياري متين
    /// (١٫٤٨ × الانحراف المطلق عن الوسيط) حتى لا تجعل قراءة حركة واحدة النبضَ «متذبذباً».
    static func heartRateVariability(_ sorted: [VitalSample], endingAt end: Date) -> Double? {
        let values = sorted
            .filter { end.timeIntervalSince($0.sampleDate) <= 15 * 60 && $0.sampleDate <= end }
            .compactMap { value($0, .heartRate) }
        guard values.count >= 3 else { return nil }
        let med = median(values)
        return 1.4826 * median(values.map { abs($0 - med) })
    }

    /// اكتمال القراءات خلال المدة الفعلية للمراقبة (لا الست ساعات كاملة)، مضروباً في حداثتها.
    static func coverage(_ window: [VitalSample], from: Date, to: Date, config: HealthThresholds) -> Double {
        guard let first = window.first, let last = window.last else { return 0 }
        let start = max(from, first.sampleDate)
        let observed = max(0, to.timeIntervalSince(start)) + config.expectedInterval
        let completeness = min(1, Double(window.count) * config.expectedInterval / observed)
        let age = to.timeIntervalSince(last.sampleDate)
        let freshness = age <= 5 * 60 ? 1 : exp(-(age - 5 * 60) / (30 * 60))
        return completeness * freshness
    }

    static func vitalBand(score s: Double) -> VitalBand {
        if s < 50 { return .critical }
        if s < 80 { return .caution }
        return .normal
    }

    static func emptyAssessment(headline: String, count: Int = 0, at: Date? = nil) -> HealthAssessment {
        HealthAssessment(score: 0, band: .danger, headline: headline, indicators: [],
                         coverage: 0, sampleCount: count, updatedAt: at)
    }

    static func headline(band: HealthBand, indicators: [IndicatorReading], loads: Loads) -> String {
        let vitals = indicators.filter { $0.kind != .stability }
        let critical = vitals.filter { $0.band == .critical }.map { "\($0.kind.title) \($0.display)" }
        let caution = vitals.filter { $0.band == .caution }.map { $0.kind.title }
        let strained = max(loads.hr, loads.spo2, loads.temp) > 25

        switch band {
        case .excellent:
            return "جميع المؤشرات ضمن النطاق الطبيعي والحالة مستقرة."
        case .good:
            return caution.isEmpty
                ? "الحالة جيدة عموماً."
                : "الحالة جيدة؛ يُستحسن متابعة \(caution.joined(separator: " و"))."
        case .attention:
            let names = (critical + caution).joined(separator: "، ")
            let extra = strained ? " مع إجهاد متراكم من الفترة السابقة" : ""
            return names.isEmpty
                ? "انتباه: يرجى مراقبة الحالة\(extra)."
                : "انتباه: \(names) خارج النطاق الطبيعي\(extra). خفّف الجهد وراقب."
        case .danger:
            let names = critical.isEmpty ? caution.joined(separator: "، ") : critical.joined(separator: "، ")
            return "تحذير: \(names.isEmpty ? "مؤشرات حيوية" : names) تجاوز الحد الآمن — توقف وخذ راحة وتواصل مع غرفة العمليات."
        }
    }

    static func explain(kind: VitalKind, track t: Track, trend tr: Trend, load: Double, tired: Double,
                        config: HealthThresholds) -> String {
        let now = format(t.level, kind)
        let unit = kind.unit.isEmpty ? "" : " \(kind.unit)"
        var parts: [String] = []
        switch tr.direction {
        case .rising:
            parts.append("\(kind.title) الآن \(now)\(unit) ويرتفع بمعدل \(String(format: "%.1f", abs(tr.slopePerMinute) * 10)) كل ١٠ دقائق")
        case .falling:
            parts.append("\(kind.title) الآن \(now)\(unit) وينخفض بمعدل \(String(format: "%.1f", abs(tr.slopePerMinute) * 10)) كل ١٠ دقائق")
        case .steady:
            parts.append("\(kind.title) الآن \(now)\(unit) قريب من الحد")
        }
        if let eta = tr.minutesToThreshold, eta <= Double(config.forecastHorizon / 60) {
            parts.append("وقد يبلغ الحد الحرج خلال ~\(max(1, Int(eta.rounded()))) دقيقة")
        }
        if load > 0.5 { parts.append("مع إجهاد متراكم") }
        if tired >= 0.5 { parts.append("مع قلة نوم الليلة الماضية") }
        var text = parts.joined(separator: " ") + "."
        if t.accepted < 10 { text += " (تقدير أولي — القراءات ما تزال قليلة)" }
        return text
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }

    static func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }

    private static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6_371_000.0
        let lat1 = a.0 * .pi / 180
        let lat2 = b.0 * .pi / 180
        let dLat = (b.0 - a.0) * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let aVal = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        return r * 2 * atan2(sqrt(aVal), sqrt(1-aVal))
    }
}

// MARK: - الربط بسجلّك الحالي

extension SyncHistoryRecord: VitalSample {
    public var sampleDate: Date  { timestamp }
    public var vHeartRate: Int?   { self.heartRate > 0 ? self.heartRate : nil }
    public var vSpo2: Int?        { self.spo2 > 0 ? self.spo2 : nil }
    public var systolic: Int? {
        let parts = bloodPressure.split(separator: "/")
        guard parts.count == 2, let sys = Int(parts[0]), sys > 0 else { return nil }
        return sys
    }
    public var diastolic: Int? {
        let parts = bloodPressure.split(separator: "/")
        guard parts.count == 2, let dia = Int(parts[1]), dia > 0 else { return nil }
        return dia
    }

    public var vLatitude: Double? { self.latitude != 0.0 ? self.latitude : nil }
    public var vLongitude: Double? { self.longitude != 0.0 ? self.longitude : nil }
}
