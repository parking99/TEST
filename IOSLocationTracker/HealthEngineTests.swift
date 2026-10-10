import XCTest
@testable import IOSLocationTracker

/// اختبارات المحرك. الملف خارج هدف التطبيق — أضِفه إلى هدف اختبار (Unit Testing Bundle) في Xcode لتشغيله.
final class HealthEngineTests: XCTestCase {

    private struct Sample: VitalSample {
        var sampleDate: Date
        var vHeartRate: Int?
        var vSpo2: Int?
        var systolic: Int? = nil
        var diastolic: Int? = nil
        var bodyTemp: Double? = nil
        var vLatitude: Double? = nil
        var vLongitude: Double? = nil
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// قراءة كل دقيقة تنتهي عند `now`.
    private func series(hr: [Int], spo2: Int = 98, temp: Double? = 36.6) -> [Sample] {
        hr.enumerated().map { i, v in
            Sample(sampleDate: now.addingTimeInterval(Double(i - hr.count + 1) * 60),
                   vHeartRate: v, vSpo2: spo2, bodyTemp: temp)
        }
    }

    private func indicator(_ a: HealthAssessment, _ kind: VitalKind) -> IndicatorReading? {
        a.indicators.first { $0.kind == kind }
    }

    // 7.1 التعافي المتناسب وتأثير الذاكرة
    func testMemoryAndProportionalRecovery() {
        let samples = series(hr: Array(repeating: 150, count: 30) + Array(repeating: 75, count: 5))
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertNotEqual(a.band, .excellent, "خمس دقائق راحة لا تمحو نصف ساعة إجهاد")
    }

    // 7.2 القراءة الشاذة المفردة
    func testSingleOutlierRejection() {
        let samples = series(hr: Array(repeating: 75, count: 20) + [195])
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertEqual(indicator(a, .heartRate)?.value, 75)
        XCTAssertEqual(a.band, .excellent)
    }

    // 7.3 التعافي الكاذب
    func testFalseRecovery() {
        let samples = series(hr: Array(repeating: 150, count: 10) + [75])
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertEqual(a.band, .danger)
    }

    // 7.4 الحدث الحاد الحقيقي (مسار الطوارئ)
    func testAcuteCriticalEvent() {
        let samples = series(hr: Array(repeating: 75, count: 30) + Array(repeating: 150, count: 3))
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertEqual(a.band, .danger)
        XCTAssertLessThanOrEqual(a.score, 49)
    }

    // 7.5 سقف أسوأ مؤشر (البند 2.11)
    func testWorstIndicatorCeiling() {
        let samples = series(hr: Array(repeating: 150, count: 5))
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertLessThanOrEqual(a.score, 49, "النبض خطر والباقي ممتاز — النتيجة خطر")
    }

    // 7.6 الأكسجين بالمنطق المقلوب
    func testSpo2InvertedLogic() {
        var samples = series(hr: Array(repeating: 75, count: 20), spo2: 88)
        samples += (1...3).map { i in
            Sample(sampleDate: now.addingTimeInterval(Double(i) * 60), vHeartRate: 75, vSpo2: 97, bodyTemp: 36.6)
        }
        let a = HealthEngine.assess(samples, now: now.addingTimeInterval(180))
        XCTAssertLessThan(indicator(a, .spo2)?.score ?? 100, 100, "نزول الأكسجين يراكم إجهاداً يخفض الدرجة")
        XCTAssertEqual(indicator(a, .spo2)?.band, .normal, "لكن قيمة ٩٧ تُعرض طبيعية لا حرجة")
    }

    func testNormalSpo2AfterDipIsNotCritical() {
        var samples = series(hr: Array(repeating: 75, count: 30), spo2: 98)
        for (i, o) in [89, 88, 89, 90, 99, 99, 99].enumerated() {
            samples[23 + i].vSpo2 = o
        }
        let a = HealthEngine.assess(samples, now: now)
        XCTAssertEqual(indicator(a, .spo2)?.value, 99)
        XCTAssertNotEqual(indicator(a, .spo2)?.band, .critical, "أكسجين ٩٩ لا يُطلق تنبيه تجاوز الحد")
    }

    // MARK: - التنبؤ

    func testForecastStartsFromFirstReading() {
        let f = HealthEngine.forecast(series(hr: [76]), now: now)
        XCTAssertFalse(f.insufficientCoverage)
        XCTAssertTrue(f.isPreliminary)
        XCTAssertNotNil(f.projectedScore)
        XCTAssertTrue(f.risks.isEmpty, "قراءة طبيعية واحدة لا تولّد خطراً")
    }

    func testRisingHeartRateIsForecast() {
        let f = HealthEngine.forecast(series(hr: Array(100...130)), now: now)
        XCTAssertEqual(f.risks.first?.kind, .heartRate)
        XCTAssertEqual(f.risks.first?.level, .high)
        XCTAssertNotNil(f.risks.first?.minutesToThreshold)
    }

    func testStableHeartRateHasNoRisk() {
        let hr = (0..<60).map { 72 + ($0 % 3) - 1 }
        let f = HealthEngine.forecast(series(hr: hr), now: now)
        XCTAssertTrue(f.risks.isEmpty)
        XCTAssertFalse(f.isPreliminary)
    }

    // MARK: - إصلاحات

    func testMissingTemperatureIsIgnored() {
        let a = HealthEngine.assess(series(hr: Array(repeating: 75, count: 5), temp: 0), now: now)
        XCTAssertNil(indicator(a, .bodyTemp), "حرارة ٠ تعني أن السوار لم يقسها، لا انخفاضاً حرجاً")
        XCTAssertEqual(a.band, .excellent)
    }

    func testAssessmentIsPure() {
        let samples = series(hr: Array(repeating: 150, count: 10))
        let first = HealthEngine.assess(samples, now: now).score
        for _ in 0..<20 { _ = HealthEngine.assess(samples, now: now) }
        XCTAssertEqual(HealthEngine.assess(samples, now: now).score, first, "إعادة الرسم لا تغيّر التقييم")
    }

    func testRapidRiseIsDetected() {
        let changes = HealthEngine.rapidChanges(series(hr: Array(repeating: 75, count: 12) + [112, 114, 113]))
        XCTAssertEqual(changes.first?.kind, .heartRate)
        XCTAssertEqual(changes.first?.isRise, true)
        XCTAssertEqual(changes.first?.from, 75)
    }

    func testSingleSpikeIsNotRapidChange() {
        let changes = HealthEngine.rapidChanges(series(hr: Array(repeating: 75, count: 12) + [76, 140, 75]))
        XCTAssertTrue(changes.isEmpty, "قراءة حركة واحدة لا تُعدّ تغيّراً سريعاً")
    }

    func testEpisodesNeedTwoConsecutiveReadings() {
        let samples = series(hr: [75, 145, 75, 75, 141, 142, 143, 75])
        let eps = HealthEngine.episodes(samples)
        XCTAssertEqual(eps.count, 1)
        XCTAssertEqual(eps.first?.peak, 143)
        XCTAssertEqual(eps.first?.readings, 3)
    }
}
