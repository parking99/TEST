//
//  AlertsFeature.swift
//  SecurityPass
//
//  منطق «التنبيهات»: المنبّهات (على السوار + إشعار بالملاحظة)، سجل التنبيهات،
//  البطاقة الطبية، وكشف الإغماء (عدم حركة مع نبض غير طبيعي).
//

import Foundation
import UserNotifications
import protocol_channel

// MARK: - إعدادات التنبيهات الذكية

public enum AlertSettings {
    public static let outOfRangeKey = "alert_out_of_range_enabled"
    public static let rapidChangeKey = "alert_rapid_change_enabled"
    public static let faintKey = "alert_faint_detection_enabled"

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    public static var outOfRange: Bool { isOn(outOfRangeKey) }
    public static var rapidChange: Bool { isOn(rapidChangeKey) }
    public static var faintDetection: Bool { isOn(faintKey) }

    /// مدة اهتزاز السوار عند المنبّه (حين يهزّه التطبيق).
    public static let alarmBuzzSecondsKey = "alarm_buzz_seconds"
    public static let alarmBuzzChoices: [(seconds: Int, title: String)] = [(30, "٣٠ ثانية"), (60, "دقيقة"), (120, "دقيقتان")]
    public static var alarmBuzzSeconds: Int {
        let v = UserDefaults.standard.integer(forKey: alarmBuzzSecondsKey)
        return v > 0 ? v : 60
    }
}

// MARK: - البطاقة الطبية

public enum MedicalProfile {
    public static let bloodTypeKey = "medical_blood_type"
    public static let allergiesKey = "medical_allergies"
    public static let emergencyNameKey = "medical_emergency_name"
    public static let emergencyPhoneKey = "medical_emergency_phone"

    public static let unknownBloodType = "غير معروف"
    public static let bloodTypes = [unknownBloodType, "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    private static func text(_ key: String) -> String? {
        let v = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    public static var bloodType: String? {
        guard let v = text(bloodTypeKey), v != unknownBloodType else { return nil }
        return v
    }
    public static var allergies: String? { text(allergiesKey) }
    public static var emergencyName: String? { text(emergencyNameKey) }
    public static var emergencyPhone: String? { text(emergencyPhoneKey) }

    /// رابط الاتصال برقم الطوارئ (يطلب iOS تأكيد المستخدم دائماً).
    public static var emergencyCallURL: URL? {
        guard let phone = emergencyPhone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel://\(digits)")
    }

    /// سطور البطاقة كما تظهر في الإشعارات وشاشة القفل.
    public static var lines: [String] {
        var out: [String] = []
        if let b = bloodType { out.append("فصيلة الدم: \(b)") }
        if let c = VoiceAlertManager.shared.conditionsText { out.append("الأمراض المزمنة: \(c)") }
        if let a = allergies { out.append("الحساسية: \(a)") }
        if let p = emergencyPhone {
            out.append("رقم الطوارئ: " + (emergencyName.map { "\($0) " } ?? "") + p)
        }
        return out
    }

    public static var summary: String? {
        lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// MARK: - سجل التنبيهات

public struct AlertLogEntry: Codable, Identifiable {
    public enum Kind: String, Codable {
        case critical, outOfRange, rapid, faint, predictive, sleep, other
    }

    public var id = UUID()
    public let date: Date
    public let kind: Kind
    public let title: String
    public let body: String
}

public final class AlertLog: ObservableObject {
    public static let shared = AlertLog()

    @Published public private(set) var entries: [AlertLogEntry] = []

    private let key = "alert_log_v1"
    private let limit = 60

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AlertLogEntry].self, from: data) {
            entries = saved
        }
    }

    public func add(_ kind: AlertLogEntry.Kind, title: String, body: String) {
        let entry = AlertLogEntry(date: Date(), kind: kind, title: title, body: body)
        let apply = {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.limit { self.entries.removeLast(self.entries.count - self.limit) }
            if let data = try? JSONEncoder().encode(self.entries) {
                UserDefaults.standard.set(data, forKey: self.key)
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    public func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - المنبّهات

public enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case medication, water, rest, wakeUp, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .medication: return "دواء"
        case .water:      return "شرب ماء"
        case .rest:       return "استراحة"
        case .wakeUp:     return "استيقاظ"
        case .other:      return "تذكير"
        }
    }

    public var emoji: String {
        switch self {
        case .medication: return "💊"
        case .water:      return "💧"
        case .rest:       return "☕"
        case .wakeUp:     return "⏰"
        case .other:      return "🔔"
        }
    }

    public var symbol: String {
        switch self {
        case .medication: return "pills.fill"
        case .water:      return "drop.fill"
        case .rest:       return "cup.and.saucer.fill"
        case .wakeUp:     return "alarm.fill"
        case .other:      return "bell.fill"
        }
    }

    var idoType: IDOAlarmType {
        switch self {
        case .medication: return .medication
        case .wakeUp:     return .wakeUp
        case .rest, .water, .other: return .other
        }
    }
}

public struct Reminder: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var hour: Int
    public var minute: Int
    /// أيام التكرار بترقيم Apple: ١ الأحد … ٧ السبت. فارغة = مرة واحدة.
    public var weekdays: Set<Int>
    public var note: String
    public var kind: ReminderKind
    public var isEnabled: Bool = true
    public var vibrateBand: Bool = true
    /// موعد المرة الواحدة — يُعطَّل المنبّه بعده.
    public var oneTimeDate: Date? = nil

    public var timeText: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "ص" : "م")
    }

    public var daysText: String {
        if weekdays.isEmpty { return "مرة واحدة" }
        if weekdays.count == 7 { return "كل يوم" }
        if weekdays == [1, 2, 3, 4, 5] { return "الأحد – الخميس" }
        return Reminder.weekdayOrder.filter { weekdays.contains($0) }
            .map { Reminder.shortDayNames[$0] ?? "" }
            .joined(separator: "، ")
    }

    public var displayText: String {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? kind.title : n
    }

    /// ترتيب الأسبوع عربياً: يبدأ بالأحد.
    public static let weekdayOrder = [1, 2, 3, 4, 5, 6, 7]
    public static let shortDayNames: [Int: String] = [
        1: "أحد", 2: "إثنين", 3: "ثلاثاء", 4: "أربعاء", 5: "خميس", 6: "جمعة", 7: "سبت"
    ]
}

public final class ReminderStore: ObservableObject {
    public static let shared = ReminderStore()

    static let notificationCategory = "REMINDER"
    static let snoozeAction = "REMINDER_SNOOZE"
    static let doneAction = "REMINDER_DONE"
    private static let idPrefix = "reminder-"

    @Published public private(set) var reminders: [Reminder] = []
    /// نتيجة آخر إرسال للسوار — تُعرض في الشاشة.
    @Published public private(set) var bandStatus: String = ""

    /// كيف يهتز السوار في وقت المنبّه.
    public enum BandMode {
        case unknown
        /// المنبّهات محفوظة داخل السوار — تعمل حتى والتطبيق مغلق.
        case native
        /// السوار لا يحفظ المنبّهات (أو رفضها) — التطبيق يهزّه في الوقت بأمر الاهتزاز.
        case appDriven
    }
    @Published public private(set) var bandMode: BandMode = .unknown

    private var ticker: Timer?
    private var firedKeys: Set<String> = []

    private let key = "reminders_v1"
    public let maxReminders = 8

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = saved
        }
        expireOneTime()
        startTicker()
    }

    // MARK: الاهتزاز عبر التطبيق

    /// كل ٢٠ ثانية: إن حان منبّه والسوار لا يحفظ المنبّهات، يهزّه التطبيق بنفسه.
    /// يعمل ما دام التطبيق يعمل في الخلفية (الموقع والبلوتوث يبقيانه حياً).
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick(now: Date = Date()) {
        guard bandMode != .native else { return }
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        let stamp = String(format: "%04d%02d%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)

        for r in reminders where r.isEnabled && r.vibrateBand && r.hour == c.hour && r.minute == c.minute {
            let due: Bool
            if r.weekdays.isEmpty {
                due = r.oneTimeDate.map { cal.isDate($0, equalTo: now, toGranularity: .minute) } ?? false
            } else {
                due = r.weekdays.contains(c.weekday ?? 0)
            }
            let key = r.id.uuidString + stamp
            guard due, !firedKeys.contains(key) else { continue }
            firedKeys.insert(key)
            IdoSmartManager.shared.buzz(seconds: Double(AlertSettings.alarmBuzzSeconds))
        }
        if firedKeys.count > 50 { firedKeys.removeAll() }
    }

    /// زر «اختبار اهتزاز السوار»: عشر ثوانٍ تكفي لمعرفة الإحساس.
    public func testBuzz() {
        IdoSmartManager.shared.buzz(seconds: 10)
    }

    public static var notificationCategoryDefinition: UNNotificationCategory {
        UNNotificationCategory(
            identifier: notificationCategory,
            actions: [
                UNNotificationAction(identifier: snoozeAction, title: "ذكّرني بعد ١٠ دقائق", options: []),
                UNNotificationAction(identifier: doneAction, title: "تم", options: [])
            ],
            intentIdentifiers: [], options: []
        )
    }

    // MARK: التعديل

    public func save(_ reminder: Reminder) {
        var r = reminder
        r.oneTimeDate = r.weekdays.isEmpty ? Self.nextOccurrence(hour: r.hour, minute: r.minute) : nil
        if let i = reminders.firstIndex(where: { $0.id == r.id }) {
            reminders[i] = r
        } else {
            guard reminders.count < maxReminders else { return }
            reminders.append(r)
        }
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        persistAndApply()
    }

    public func delete(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        persistAndApply()
    }

    public func setEnabled(_ reminder: Reminder, _ on: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[i].isEnabled = on
        if on && reminders[i].weekdays.isEmpty {
            reminders[i].oneTimeDate = Self.nextOccurrence(hour: reminders[i].hour, minute: reminders[i].minute)
        }
        persistAndApply()
    }

    /// تعطيل منبّهات المرة الواحدة التي مضى موعدها — يُستدعى عند فتح التطبيق.
    public func expireOneTime(now: Date = Date()) {
        var changed = false
        for i in reminders.indices where reminders[i].isEnabled {
            if let d = reminders[i].oneTimeDate, d < now {
                reminders[i].isEnabled = false
                changed = true
            }
        }
        if changed { persistAndApply() }
    }

    private func persistAndApply() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: key)
        }
        scheduleNotifications()
        syncToBand()
    }

    // MARK: إشعارات الجوال

    /// كل منبّه يظهر إشعاراً بملاحظته في وقته — حتى يعرف المستخدم سبب اهتزاز السوار.
    public func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        let snapshot = reminders
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix(Self.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)

            for r in snapshot where r.isEnabled {
                let content = UNMutableNotificationContent()
                content.title = r.kind == .medication ? "💊 موعد الدواء" : "\(r.kind.emoji) \(r.kind.title)"
                content.body = r.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "حان موعد التذكير."
                    : r.note
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                content.categoryIdentifier = Self.notificationCategory

                if r.weekdays.isEmpty {
                    guard let date = r.oneTimeDate else { continue }
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    center.add(UNNotificationRequest(
                        identifier: "\(Self.idPrefix)\(r.id.uuidString)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                } else {
                    for day in r.weekdays {
                        var comps = DateComponents()
                        comps.weekday = day
                        comps.hour = r.hour
                        comps.minute = r.minute
                        center.add(UNNotificationRequest(
                            identifier: "\(Self.idPrefix)\(r.id.uuidString)-\(day)",
                            content: content,
                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
                    }
                }
            }
        }
    }

    /// زر «ذكّرني بعد ١٠ دقائق» في الإشعار.
    public func snooze(_ content: UNNotificationContent) {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        copy.title = "تذكير: " + content.title
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "snooze-\(UUID().uuidString)",
            content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)))
    }

    // MARK: السوار

    /// يرسل قائمة المنبّهات كاملة للسوار فيهتز في وقتها حتى لو كان الجوال بعيداً أو التطبيق مغلقاً.
    /// يُفحص جدول قدرات السوار أولاً: كثير من الأساور (خصوصاً بلا شاشة) لا تحفظ المنبّهات،
    /// وحينها يتولى التطبيق الاهتزاز في الوقت.
    public func syncToBand() {
        let ido = IdoSmartManager.shared
        guard ido.isConnected else {
            DispatchQueue.main.async { self.bandStatus = "السوار غير متصل — تُرسل المنبّهات عند الاتصال." }
            return
        }

        let table = sdk.funcTable
        let capacity = table.alarmCount
        guard capacity > 0 || table.syncV3SyncAlarm else {
            DispatchQueue.main.async {
                self.bandMode = .appDriven
                self.bandStatus = "سوارك لا يحفظ المنبّهات — سيهزّه التطبيق في وقت المنبّه (يلزم بقاء التطبيق في الخلفية والسوار متصلاً)."
            }
            return
        }

        let limit = capacity > 0 ? capacity : 5
        let forBand = Array(reminders.filter { $0.vibrateBand }.prefix(limit))
        let noSnooze = table.v3AlarmNotSupportRepeat

        let items: [IDOAlarmItem] = forBand.enumerated().map { index, r in
            IDOAlarmItem(
                alarmID: index + 1,
                delayMin: 0,
                hour: r.hour,
                minute: r.minute,
                name: Self.truncated(r.displayText, maxBytes: 23),
                repeats: Set(r.weekdays.compactMap(Self.idoWeek)),
                isOpen: r.isEnabled,
                repeatTimes: noSnooze ? 0 : 3,
                shockOnOff: 1,
                status: .displayed,
                tsnoozeDuration: noSnooze ? 0 : 10,
                type: Self.supportedType(for: r.kind, table: table)
            )
        }

        Cmds.setAlarm(alarm: IDOAlarmModel(items: items)).send { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.bandMode = .native
                    let skipped = self.reminders.filter { $0.vibrateBand }.count - forBand.count
                    self.bandStatus = skipped > 0
                        ? "أُرسلت \(forBand.count) منبّهات للسوار — يتّسع لـ\(limit) فقط، والباقي يهزّه التطبيق."
                        : "المنبّهات محفوظة في السوار."
                    if skipped > 0 { self.bandMode = .appDriven }
                case .failure(let error):
                    self.bandMode = .appDriven
                    self.bandStatus = "السوار رفض حفظ المنبّهات (رمز \(error.code)) — سيهزّه التطبيق في وقت المنبّه بدلاً من ذلك."
                }
            }
        }
    }

    /// نوع يدعمه السوار: «دواء» إن كان مدعوماً، وإلا منبّه الاستيقاظ العام.
    static func supportedType(for kind: ReminderKind, table: any IDOFuncTableInterface) -> IDOAlarmType {
        if kind == .medication && table.alarmMedicine { return .medication }
        if kind == .rest && table.alarmRest { return .other }
        return .wakeUp
    }

    /// اسم المنبّه لا يتجاوز ٢٣ بايت — العربية بايتان للحرف.
    static func truncated(_ text: String, maxBytes: Int) -> String {
        var out = ""
        for ch in text {
            if (out + String(ch)).utf8.count > maxBytes { break }
            out.append(ch)
        }
        return out
    }

    /// ترقيم Apple (١ الأحد) إلى ترقيم السوار (٠ الإثنين … ٦ الأحد).
    static func idoWeek(_ appleWeekday: Int) -> IDOWeek? {
        IDOWeek(rawValue: (appleWeekday + 5) % 7)
    }

    static func nextOccurrence(hour: Int, minute: Int, after now: Date = Date()) -> Date? {
        Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                  matchingPolicy: .nextTime)
    }
}

// MARK: - كشف الإغماء

/// عدم حركة لعشر دقائق (الموقع ثابت والخطوات لم تتغير) مع نبض غير طبيعي:
/// عند أحد الحدين الحرجين، أو هبوط سريع. يطلق التنبيه الصوتي فوراً.
public final class FaintDetector {
    public static let shared = FaintDetector()

    private var stepLog: [(date: Date, steps: Int)] = []
    private let window: TimeInterval = 10 * 60
    private let stillMeters = 25.0

    private init() {}

    public func evaluate(_ samples: [VitalSample], steps: Int, now: Date = Date(),
                         config: HealthThresholds = .default) {
        stepLog.append((now, steps))
        stepLog.removeAll { now.timeIntervalSince($0.date) > window + 5 * 60 }

        let recent = samples
            .filter { now.timeIntervalSince($0.sampleDate) <= window && $0.sampleDate <= now }
            .sorted { $0.sampleDate < $1.sampleDate }

        let moving = isMoving(recent, now: now)
        if moving { VoiceAlertManager.shared.resolve(.inactivity) }
        guard AlertSettings.faintDetection, !moving, let reason = abnormalHeart(samples, now: now, config: config) else {
            return
        }

        if VoiceAlertManager.shared.trigger(.inactivity, detail: reason) {
            AlertLog.shared.add(.faint, title: "اشتباه إغماء",
                                body: "لا حركة منذ ١٠ دقائق مع \(reason). شُغّل التنبيه الصوتي.")
        }
    }

    /// يتحرك ما لم يثبت العكس: نحتاج قراءات تغطي النافذة كاملة، كلها ضمن دائرة صغيرة، والخطوات ثابتة.
    private func isMoving(_ recent: [VitalSample], now: Date) -> Bool {
        let points = recent.compactMap { s -> (Double, Double)? in
            guard let la = s.vLatitude, let lo = s.vLongitude else { return nil }
            return (la, lo)
        }
        guard points.count >= 5, let firstDate = recent.first?.sampleDate,
              now.timeIntervalSince(firstDate) >= window - 2 * 60, let anchor = points.first else {
            return true
        }
        if points.contains(where: { HealthEngine.distanceMeters(anchor, $0) > stillMeters }) { return true }

        if let oldest = stepLog.first(where: { now.timeIntervalSince($0.date) >= window - 60 }),
           let latest = stepLog.last, oldest.steps > 0, latest.steps - oldest.steps > 10 {
            return true
        }
        return false
    }

    private func abnormalHeart(_ samples: [VitalSample], now: Date, config: HealthThresholds) -> String? {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }
        guard let hr = HealthEngine.current(.heartRate, in: sorted),
              let last = sorted.last, now.timeIntervalSince(last.sampleDate) <= 3 * 60 else { return nil }

        if hr <= config.heartRate.criticalLow { return "انخفاض شديد في النبض (\(Int(hr)))" }
        if hr >= config.heartRate.criticalHigh { return "ارتفاع حرج في النبض (\(Int(hr)))" }
        // الهبوط وحده لا يكفي (يحدث طبيعياً عند الجلوس بعد جهد) — يجب أن ينتهي تحت الطبيعي.
        if let drop = HealthEngine.rapidChanges(samples, config: config)
            .first(where: { $0.kind == .heartRate && !$0.isRise && $0.to < config.heartRate.normal.lowerBound }) {
            return "هبوط مفاجئ في النبض من \(Int(drop.from)) إلى \(Int(drop.to))"
        }
        return nil
    }
}
