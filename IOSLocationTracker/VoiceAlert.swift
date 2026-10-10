//
//  VoiceAlert.swift
//  SecurityPass
//
//  التنبيه الصوتي عند الحالة الحرجة: نغمة إنذار ثم رسالة صوتية مسجّلة بالعربية
//  (بدون أرقام) تذكر الأمراض المزمنة المسجّلة، وتتكرر حتى «أنا بخير» أو تحسّن الحالة.
//
//  المقاطع في مجلد AlertVoice: alert_<mask>.mp3 لكل تركيبة من الأمراض الست،
//  حتى تُقرأ كل رسالة جملةً واحدة طبيعية بدل تركيب مقاطع متقطعة.
//

import Foundation
import AVFoundation
import UserNotifications

/// الأمراض المزمنة — الترتيب يطابق ترقيم مقاطع AlertVoice/alert_<mask>.mp3، فلا تغيّره.
public enum ChronicCondition: Int, CaseIterable, Identifiable {
    case hypertension = 0, diabetes, heart, asthma, epilepsy, allergy

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .hypertension: return "ارتفاع ضغط الدم"
        case .diabetes:     return "السكري"
        case .heart:        return "أمراض القلب"
        case .asthma:       return "الربو"
        case .epilepsy:     return "الصرع"
        case .allergy:      return "حساسية شديدة"
        }
    }

    public var bit: Int { 1 << rawValue }
}

public final class VoiceAlertManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = VoiceAlertManager()

    public static let enabledKey = "voice_alert_enabled"
    public static let conditionsKey = "chronic_conditions_mask"
    public static let otherKey = "chronic_conditions_other"

    static let notificationCategory = "CRITICAL_STATE"
    static let okAction = "IM_OK"
    private static let notificationID = "critical-state"

    /// ما الذي أطلق التنبيه — يحدد متى يتوقف تلقائياً.
    public enum Trigger {
        /// التقييم «خطر».
        case criticalState
        /// عدم حركة مع نبض غير طبيعي.
        case inactivity
    }

    /// التنبيه يعمل الآن.
    @Published public private(set) var isActive = false
    @Published public private(set) var activeTrigger: Trigger?
    private var detail: String?

    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    private var repeatTimer: Timer?
    private var startedAt: Date?
    private var snoozedUntil: Date?

    private let repeatInterval: TimeInterval = 30
    private let maxDuration: TimeInterval = 10 * 60
    /// بعد «أنا بخير» لا يعود التنبيه قبل هذه المدة إلا إذا تحسّنت الحالة ثم ساءت.
    private let snooze: TimeInterval = 10 * 60

    private override init() {
        super.init()
        // مكالمة أو تطبيق آخر قد يقطع الصوت — نكمل التنبيه بعد انتهاء المقاطعة.
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        DispatchQueue.main.async {
            if self.isActive { self.playOnce() }
        }
    }

    /// تنبيه بقي «نشطاً» بعد انتهاء مدته (توقّف مؤقت التكرار في الخلفية) كان يمنع أي تنبيه جديد
    /// حتى يُعاد تشغيل التطبيق — نُنهيه هنا.
    public func recoverIfStale(now: Date = Date()) {
        guard isActive else { return }
        if let started = startedAt, now.timeIntervalSince(started) >= maxDuration {
            stop()
        } else if repeatTimer == nil || repeatTimer?.isValid == false {
            scheduleRepeat()
        }
    }

    // MARK: الإعدادات

    public var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    public var conditionsMask: Int {
        UserDefaults.standard.integer(forKey: Self.conditionsKey) & 0b111111
    }

    public var otherConditions: String {
        (UserDefaults.standard.string(forKey: Self.otherKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// الأمراض المسجّلة نصاً للإشعارات، أو nil إن لم يُسجّل شيء.
    public var conditionsText: String? {
        var names = ChronicCondition.allCases.filter { conditionsMask & $0.bit != 0 }.map { $0.title }
        if !otherConditions.isEmpty { names.append(otherConditions) }
        return names.isEmpty ? nil : names.joined(separator: "، ")
    }

    // MARK: التشغيل

    /// آخر تقييم «خطر» — لعلاج التذبذب حول الحد.
    private var lastCriticalAt: Date?
    /// مدة الاستقرار تحت حد الخطر قبل أن يُسمح بتنبيه جديد بعد «أنا بخير».
    private let calmBeforeRearm: TimeInterval = 5 * 60

    /// نادِها بعد كل تقييم: تبدأ عند «خطر».
    /// لا تتوقف بنزول القراءة تحت الحد — قد تبقى مرتفعة، أو تتذبذب حوله، أو تكون قراءة عابرة؛
    /// الإيقاف بـ«أنا بخير» أو بانتهاء المدة القصوى فقط.
    public func evaluate(_ assessment: HealthAssessment, now: Date = Date()) {
        let critical = !assessment.isEmpty && assessment.band == .danger
        guard critical else {
            // بعد «أنا بخير» لا يعود التنبيه إلا إذا استقرت الحالة ٥ دقائق ثم ساءت من جديد.
            if !isActive, let last = lastCriticalAt, now.timeIntervalSince(last) >= calmBeforeRearm {
                snoozedUntil = nil
            }
            return
        }
        lastCriticalAt = now
        _ = trigger(.criticalState, now: now)
    }

    /// يبدأ التنبيه إن لم يكن يعمل ولم يؤجَّل. يعيد true إن بدأ فعلاً.
    @discardableResult
    public func trigger(_ trigger: Trigger, detail: String? = nil, now: Date = Date()) -> Bool {
        recoverIfStale(now: now)
        guard isEnabled, !isActive else { return false }
        if let until = snoozedUntil, now < until { return false }
        activeTrigger = trigger
        self.detail = detail
        start(now: now)
        return true
    }



    /// زر «أنا بخير» في التطبيق أو في الإشعار.
    public func acknowledge() {
        // التأجيل يبقى حتى تستقر الحالة (انظر evaluate) — المدة هنا حد أقصى فقط.
        snoozedUntil = Date().addingTimeInterval(snooze)
        stop()
        IdoSmartManager.shared.stopBuzz()
    }

    /// تجربة الصوت من الإعدادات: مرة واحدة، بلا إشعار.
    public func test() {
        guard !isActive else { return }
        playOnce()
    }

    private func start(now: Date) {
        isActive = true
        startedAt = now
        postNotification()
        playOnce()
        HealthAlertCenter.shared.buzzWatch?()
        scheduleRepeat()
    }

    private func scheduleRepeat() {
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let started = self.startedAt, Date().timeIntervalSince(started) >= self.maxDuration {
                self.stop()
                return
            }
            self.playOnce()
        }
        // وضع .common يبقي المؤقت يعمل أثناء التمرير والتفاعل مع الشاشة.
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stop() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        queue.removeAll()
        player?.stop()
        player = nil
        isActive = false
        activeTrigger = nil
        detail = nil
        startedAt = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        deactivateSession()
    }

    private func playOnce() {
        var urls: [URL] = []
        if let tone = Bundle.main.url(forResource: "medical_alert", withExtension: "wav") { urls.append(tone) }
        if let voice = voiceURL() { urls.append(voice) }
        guard !urls.isEmpty else { return }

        activateSession()
        player?.stop()
        queue = urls
        playNext()
    }

    private func voiceURL() -> URL? {
        Bundle.main.url(forResource: "alert_\(conditionsMask)", withExtension: "mp3", subdirectory: "AlertVoice")
            ?? Bundle.main.url(forResource: "alert_0", withExtension: "mp3", subdirectory: "AlertVoice")
    }

    private func playNext() {
        guard !queue.isEmpty else {
            if !isActive { deactivateSession() }
            return
        }
        let url = queue.removeFirst()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = 1
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            playNext()
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.playNext() }
    }

    // MARK: جلسة الصوت

    /// التشغيل يتجاهل زر الصامت، ويخفض صوت التطبيقات الأخرى بدل إيقافها —
    /// الجلسة القابلة للمزج هي ما يسمح iOS بتفعيله من الخلفية.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: الإشعار

    public static var notificationCategoryDefinition: UNNotificationCategory {
        UNNotificationCategory(
            identifier: notificationCategory,
            actions: [UNNotificationAction(identifier: okAction, title: "أنا بخير", options: [])],
            intentIdentifiers: [], options: []
        )
    }

    private func postNotification() {
        let content = UNMutableNotificationContent()
        let title: String
        var body: String
        if activeTrigger == .inactivity {
            title = "🚨 اشتباه إغماء"
            body = "لا حركة منذ ١٠ دقائق" + (detail.map { " مع \($0)" } ?? "") + ". تم تشغيل التنبيه الصوتي لطلب المساعدة."
        } else {
            title = "🚨 حالة صحية حرجة"
            body = "تم تشغيل التنبيه الصوتي لطلب المساعدة."
            AlertLog.shared.add(.critical, title: title, body: body)
        }
        body += " اضغط «أنا بخير» لإيقافه."
        if let card = MedicalProfile.summary { body += "\n" + card }
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "medical_alert.wav"))
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.notificationCategory

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        )
    }
}
