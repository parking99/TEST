import UserNotifications
//
//  ContentView.swift
//  SecurityPass — الواجهة الجديدة
//
//  يستبدل هذا الملف ContentView القديم بالكامل. لم يُمسّ أي مدير:
//  IdoSmartManager و LocationManager و GoogleSheetSyncManager و
//  BloodPressureAlgorithm تُستدعى بنفس أسمائها وتواقيعها الحالية.
//

import SwiftUI
import MapKit

struct ContentView: View {

    @StateObject private var ido = IdoSmartManager.shared
    @StateObject private var location = LocationManager.shared
    /// مراقبة السجل حتى تتحدّث شاشة السجل والتنبؤ فور وصول كل قراءة.
    @ObservedObject private var syncManager = GoogleSheetSyncManager.shared
    @ObservedObject private var voiceAlert = VoiceAlertManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// نفس مفتاح التخزين المستخدم في البناء الحالي.
    @AppStorage("WATCH_APP_DEFAULT") private var employeeId: String = "WATCH_001"

    @State private var tab: Tab = .status
    /// اتجاه الانتقال الأخير: للأمام = نحو التبويبات التالية في الشريط.
    @State private var movingForward = true

    enum Tab: Int, Hashable { case status, history, alerts, devices, sos, identity }

    var body: some View {
        ZStack(alignment: .bottom) {
            SP.Color.ground.ignoresSafeArea()

            ZStack {
                screen(for: tab)
                    .id(tab)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .padding(.bottom, 78)

            SPTabBar(selection: tab, onSelect: select)

            if voiceAlert.isActive {
                CriticalAlertBanner { voiceAlert.acknowledge() }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: voiceAlert.isActive)
        .onChange(of: ido.isConnected) { connected in
            if connected { ReminderStore.shared.syncToBand() }
        }
        .preferredColorScheme(.dark)
        .spArabic()
        .onAppear { 
            location.requestPermissions()
            HealthAlertCenter.shared.requestAuthorization()
            if #available(iOS 16.1, *) {
                HealthLiveActivityManager.shared.start(employeeID: employeeId, heartRate: 0, spo2: 0)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: Tab) -> some View {
        switch tab {
        case .status:
            StatusScreen(ido: ido, location: location, employeeId: employeeId) {
                select(.devices)
            }
        case .history:  HistoryScreen(samples: syncManager.history, employeeID: employeeId)
        case .alerts:   AlertsScreen(ido: ido)
        case .devices:  DevicesScreen(ido: ido)
        case .sos:      SOSScreen(ido: ido, location: location, employeeId: employeeId)
        case .identity: IdentityScreen(ido: ido, location: location, employeeId: $employeeId)
        }
    }

    /// انتقال اتجاهي: الشاشة الجديدة تدخل من جهة التبويب المختار والقديمة تخرج من الجهة المقابلة.
    /// مع «تقليل الحركة» يصبح تلاشياً فقط.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion: Edge = movingForward ? .trailing : .leading
        let removal: Edge = movingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private func select(_ newTab: Tab) {
        guard newTab != tab else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        // يُضبط الاتجاه أولاً في دورة رسم مستقلة حتى تلتقط الشاشة الخارجة انتقالها الصحيح.
        movingForward = newTab.rawValue > tab.rawValue
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.38, dampingFraction: 0.9)) {
                tab = newTab
            }
        }
    }
}

// MARK: - شريط الحالة الحرجة

/// يظهر فوق كل الشاشات ما دام التنبيه الصوتي يعمل.
struct CriticalAlertBanner: View {
    let onOK: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("حالة صحية حرجة")
                    .font(SP.Font.ui(15, .bold))
                Text("التنبيه الصوتي يعمل لطلب المساعدة")
                    .font(SP.Font.ui(12))
                    .opacity(0.9)
            }
            Spacer(minLength: 8)
            if let call = MedicalProfile.emergencyCallURL {
                Button {
                    UIApplication.shared.open(call)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SP.Color.danger)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("اتصال برقم الطوارئ")
            }
            Button(action: onOK) {
                Text("أنا بخير")
                    .font(SP.Font.ui(14, .bold))
                    .foregroundStyle(SP.Color.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(SP.Color.danger)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: SP.Color.danger.opacity(0.5), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

// MARK: - شريط التبويب

struct SPTabBar: View {
    let selection: ContentView.Tab
    let onSelect: (ContentView.Tab) -> Void
    @Namespace private var highlight

    var body: some View {
                HStack(spacing: 4) {
            item(.status,   "الحالة",  "shield",            SP.Color.accent)
            item(.history,  "السجل",   "clock",             SP.Color.ok)
            item(.alerts,   "التنبيهات", "bell",            SP.Color.caution)
            item(.devices,  "الأجهزة", "dot.radiowaves.left.and.right", SP.Color.measure)
            item(.sos,      "SOS",     "exclamationmark.triangle", SP.Color.dangerText)
            item(.identity, "الهوية",  "person.text.rectangle", SP.Color.accent)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(SP.Color.navBar)
        .overlay(Rectangle().fill(SP.Color.line).frame(height: 1), alignment: .top)
    }

    private func item(_ tab: ContentView.Tab, _ label: String,
                      _ icon: String, _ activeColor: Color) -> some View {
        let isActive = selection == tab
        // SOS يبقى أحمر حتى وهو غير نشط — إنه تحذير لا عنصر تنقّل عادي.
        let tint: Color = isActive ? activeColor
                        : (tab == .sos ? SP.Color.dangerText : SP.Color.muted)

        return Button { onSelect(tab) } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .scaleEffect(isActive ? 1.12 : 1)
                Text(label).font(SP.Font.ui(10.5, isActive || tab == .sos ? .semibold : .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: SP.Metric.minTarget + 2)
            .background {
                // خلفية التبويب النشط تنزلق بين العناصر بدل أن تختفي وتظهر.
                if isActive {
                    RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous)
                        .fill(SP.Color.raised)
                        .matchedGeometryEffect(id: "activeTab", in: highlight)
                }
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - شاشة الحالة (متصل / منقطع)

struct StatusScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @ObservedObject var location: LocationManager
    let employeeId: String
    var onNavigateToDevices: (() -> Void)? = nil

    @ObservedObject private var syncManager = GoogleSheetSyncManager.shared

    private var connected: Bool { ido.isConnected }
    private var fullyActive: Bool { ido.isConnected && ido.isActivated }

    var body: some View {
        ScrollView {
            VStack(spacing: SP.Metric.gap) {

                if !connected {
                    disconnectedBanner
                }

                heroCard

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11),
                                    GridItem(.flexible(), spacing: 11)], spacing: 11) {
                    SPMetricCard(title: "نسبة الأكسجين", value: connected ? text(ido.currentSpo2) : "—",
                                 unit: "%", icon: "drop", iconColor: SP.Color.measure,
                                 isStale: !connected)
                    SPMetricCard(title: "ضغط الدم", value: connected ? (ido.currentBloodPressure.isEmpty ? "—" : ido.currentBloodPressure) : "—",
                                 icon: "gauge.medium", iconColor: SP.Color.accent,
                                 isStale: !connected)
                    SPMetricCard(title: "حرارة الجسم", value: connected ? temperatureText : "—",
                                 unit: "°م", icon: "thermometer.medium",
                                 iconColor: SP.Color.dangerText, isStale: !connected)
                    SPMetricCard(title: "الخطوات", value: connected ? text(ido.currentSteps) : "—",
                                 icon: "figure.walk", iconColor: SP.Color.ok,
                                 isStale: !connected)
                    SPMetricCard(title: "السعرات", value: connected ? "\(Int(Double(ido.currentSteps) * 0.045))" : "--",
                                 unit: "سعرة", icon: "flame.fill", iconColor: .orange,
                                 isStale: !connected)
                    SPMetricCard(title: "بطارية السوار", value: connected ? text(ido.currentBattery) : "—",
                                 unit: "%", icon: "battery.75", iconColor: SP.Color.muted,
                                 isStale: !connected)
                    SPMetricCard(title: "الموقع", value: locationText,
                                 icon: "location", iconColor: SP.Color.measure)
                }

                syncStrip

                if !connected {
                    Button {
                        onNavigateToDevices?()
                    } label: {
                        Label("البحث عن السوار (يصدر ذبذبات)", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(SPPrimaryButton())
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, SP.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            SPScreenHeader(
                kicker: "منصة الرصد",
                title: "القراءات الحيوية",
                trailing: AnyView(
                    SPStatusPill(text: fullyActive ? "متصل ونشط" : (connected ? "متصل (جاري التنشيط)" : "غير متصل"),
                                 color: fullyActive ? SP.Color.ok : (connected ? SP.Color.measure : SP.Color.dangerText))
                )
            )
            .background(SP.Color.ground)
        }
    }

    // MARK: أجزاء

    private var disconnectedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(SP.Color.dangerText)
                Text("تم قطع الاتصال بالسوار")
                    .font(SP.Font.ui(14, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer(minLength: 0)
            }
            Text(ido.statusMessage.isEmpty
                 ? "جاري البحث لإعادة الاتصال فور رصد السوار..."
                 : ido.statusMessage)
                .font(SP.Font.ui(12.5))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0xFFB8B4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SP.Color.dangerSurf)
        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous)
                .stroke(SP.Color.dangerLine, lineWidth: 1)
        )
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(connected ? SP.Color.accent : SP.Color.muted)
                Text(connected ? "نبض القلب المباشر" : "نبض القلب — آخر قراءة")
                    .font(SP.Font.ui(13, .semibold))
                    .foregroundStyle(connected ? SP.Color.text : SP.Color.muted)
                Spacer(minLength: 0)
                if connected {
                    Text("تحديث قبل ثوانٍ")
                        .font(SP.Font.ui(11))
                        .foregroundStyle(SP.Color.muted)
                } else {
                    Text("دقيقة")
                        .font(SP.Font.ui(10, .semibold))
                        .foregroundStyle(SP.Color.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SP.Color.lineStrong, lineWidth: 1))
                }
            }

            HStack(alignment: .bottom, spacing: 9) {
                Text(text(ido.currentHeartRate))
                    .font(SP.Font.numeric(72))
                    .foregroundStyle(connected ? SP.Color.accent : SP.Color.dimmer)
                Text("نبضة/دقيقة")
                    .font(SP.Font.ui(12))
                    .foregroundStyle(SP.Color.muted)
                    .padding(.bottom, 9)
                Spacer(minLength: 0)
            }

            SPPulseStrip(live: connected)

            if connected { safeRangeBar }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SP.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous)
                .stroke(SP.Color.line, lineWidth: 1)
        )
    }

    private var safeRangeBar: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                bar(SP.Color.okDeep, 2); bar(SP.Color.ok, 3)
                bar(Color(hex: 0x1F4C94), 2); bar(SP.Color.line, 1)
            }
            HStack {
                Text("طبيعي").font(SP.Font.ui(10.5)).foregroundStyle(SP.Color.muted)
                Spacer()
                Text("النطاق الآمن").font(SP.Font.ui(10.5, .semibold)).foregroundStyle(SP.Color.ok)
                Spacer()
                Text("مرتفع").font(SP.Font.ui(10.5)).foregroundStyle(SP.Color.muted)
            }
        }
    }

    private func bar(_ color: Color, _ weight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color)
            .frame(height: 5).layoutPriority(weight)
    }

    private var syncStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncManager.isAutoSyncActive ? SP.Color.ok : SP.Color.muted)
                        .frame(width: 7, height: 7)
                    Text(syncManager.isAutoSyncActive ? "إرسال تلقائي (كل دقيقة)" : "آخر إرسال وصل")
                        .font(SP.Font.ui(11.5))
                        .foregroundStyle(SP.Color.muted)
                }
                Text(syncManager.lastSyncTime.map(Self.timeFormatter.string(from:)) ?? "—")
                    .font(SP.Font.numeric(13))
                    .foregroundStyle(SP.Color.text)
            }
            Spacer(minLength: 0)
            Button(syncManager.isSyncing ? "جاري الإرسال..." : "إرسال الآن") {
                send()
            }
            .font(SP.Font.ui(13, .semibold))
            .foregroundStyle(SP.Color.onAccent)
            .padding(.horizontal, 15)
            .frame(minHeight: SP.Metric.minTarget)
            .background(SP.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .disabled(syncManager.isSyncing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(SP.Color.raised)
        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous)
                .stroke(SP.Color.line, lineWidth: 1)
        )
    }

    // MARK: منطق العرض فقط — الإرسال يمر بنفس المدير الحالي

    private func send() {
        syncManager.performAutoSync(force: true)
    }

    private func text(_ value: Int) -> String { value > 0 ? "\(value)" : "—" }

    private var temperatureText: String {
        ido.currentTemperature > 0 ? String(format: "%.1f", ido.currentTemperature) : "—"
    }

    private var locationText: String {
        location.latitude == 0 && location.longitude == 0 ? "—" : "مُحدّث"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "hh:mm a"
        return f
    }()
}

import SwiftUI

struct LocationAnnotation: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude == 0 ? 24.7136 : latitude, longitude: longitude == 0 ? 46.6753 : longitude)
    }
}

struct HistoryRow: View {
    let record: SyncHistoryRecord
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        f.locale = Locale(identifier: "ar")
        return f
    }()
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(HistoryRow.formatter.string(from: record.timestamp))
                    .font(SP.Font.ui(12, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer()
                if record.isSos {
                    Text("حالة طوارئ")
                        .font(SP.Font.ui(10, .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SP.Color.dangerText.opacity(0.2))
                        .foregroundStyle(SP.Color.dangerText)
                        .cornerRadius(4)
                } else {
                    Text("مزامنة دورية")
                        .font(SP.Font.ui(10, .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SP.Color.ok.opacity(0.2))
                        .foregroundStyle(SP.Color.ok)
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 12) {
                MetricMini(icon: "heart.fill", value: "\(record.heartRate)", color: SP.Color.dangerText)
                MetricMini(icon: "drop.fill", value: "\(record.spo2)%", color: SP.Color.measure)
                MetricMini(icon: "battery.100", value: "\(record.battery)%", color: SP.Color.ok)
                MetricMini(icon: "location.fill", value: "مُحدّث", color: SP.Color.accent)
            }
        }
        .padding()
        .background(SP.Color.card)
        .cornerRadius(SP.Metric.controlRadius)
    }
}

struct MetricMini: View {
    let icon: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(SP.Font.ui(12, .semibold))
                .foregroundStyle(SP.Color.text)
        }
    }
}



//
//  HealthAlerts.swift
//  SecurityPass
//
//  التنبيهات المحلية: إشعار على الجوال + اهتزاز في السوار.
//  لا شبكة، ولا حقل جديد، ولا تغيير على البروتوكول.
//  غرفة العمليات ترصد الحالة من القراءات التي تصلها كل دقيقة أصلاً.
//

import Foundation


public final class HealthAlertCenter {
    public static let shared = HealthAlertCenter()

    /// يُستدعى عند وجوب التنبيه على المعصم.
    /// اربطه بأمر الاهتزاز في iDO SDK من مكان واحد عند الإقلاع.
    public var buzzWatch: (() -> Void)?

    private var config = HealthThresholds.default

    /// بداية أول تجاوز متواصل لكل مؤشر.
    private var breachStartedAt: [VitalKind: Date] = [:]

    /// آخر إشعار أُرسل لكل مؤشر — لمنع التكرار.
    private var lastNotified: [VitalKind: Date] = [:]

    private let cooldown: TimeInterval = 60

    private init() {}

    public func configure(_ thresholds: HealthThresholds) {
        config = thresholds
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// نادِها بعد كل تقييم جديد — أي بعد كل قراءة تصل من السوار.
    public func evaluate(_ assessment: HealthAssessment, now: Date = Date()) {
        criticalNow.removeAll()
        // الاستقرار مؤشر مشتق من النبض — لا يستحق إنذاراً مستقلاً.
        for indicator in assessment.indicators where indicator.kind != .stability {
            switch indicator.band {
            case .critical:
                criticalNow.insert(indicator.kind)
                handleBreach(indicator, now: now)
            case .normal, .caution, .unknown:
                breachStartedAt[indicator.kind] = nil
            }
        }
    }

    // MARK: التنبيه الاستباقي

    /// المؤشرات الحرجة في آخر تقييم — لها إنذارها الفوري، فلا يُكرَّر باستباقي.
    private var criticalNow: Set<VitalKind> = []
    /// الخطر المرتفع في التقييم السابق — يُشترط تكراره مرتين متتاليتين.
    private var pendingRiskID: String?
    private var lastPredictiveAlert: Date?
    private let predictiveCooldown: TimeInterval = 20 * 60

    /// نادِها بعد كل تنبؤ جديد. تُنبّه قبل بلوغ الحد الحرج، لا بعده،
    /// بشرط خطر مرتفع بثقة كافية في تقييمين متتاليين.
    public func evaluateForecast(_ forecast: ForecastResult, now: Date = Date()) {
        guard let top = forecast.risks.first, top.level == .high, forecast.confidence >= 0.5,
              !(top.kind.map { criticalNow.contains($0) } ?? false) else {
            pendingRiskID = nil
            return
        }
        guard pendingRiskID == top.id else {
            pendingRiskID = top.id
            return
        }
        if let last = lastPredictiveAlert, now.timeIntervalSince(last) < predictiveCooldown { return }
        lastPredictiveAlert = now

        notify(
            title: "⚠️ تنبيه استباقي: \(top.kind?.title ?? "مؤشر حيوي")",
            body: "\(top.why) خفّف الجهد الآن وخذ استراحة قصيرة، وتواصل مع غرفة العمليات إذا لم تتحسن.",
            log: .predictive
        )
    }

    // MARK: الارتفاع والانخفاض والتغيّر السريع

    private var lastRangeAlert: [String: Date] = [:]
    private let rangeCooldown: TimeInterval = 20 * 60
    private let rapidCooldown: TimeInterval = 15 * 60

    /// نادِها بعد كل قراءة: تنبيه عند خروج مؤشر عن الطبيعي (دون الحرج — للحرج إنذاره)،
    /// وعند تغيّر سريع خلال دقائق حتى لو بقي ضمن الطبيعي.
    public func evaluateChanges(_ samples: [VitalSample], now: Date = Date()) {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }
        guard let last = sorted.last, now.timeIntervalSince(last.sampleDate) <= 5 * 60 else { return }

        if AlertSettings.outOfRange {
            for kind in [VitalKind.heartRate, .spo2, .bodyTemp] {
                guard let v = HealthEngine.current(kind, in: sorted) else { continue }
                let band = HealthEngine.band(kind, config)
                guard HealthEngine.classify(v, band) == .caution else { continue }
                let high = v > band.normal.upperBound
                let key = "range-\(kind.rawValue)-\(high)"
                if let t = lastRangeAlert[key], now.timeIntervalSince(t) < rangeCooldown { continue }
                lastRangeAlert[key] = now

                let limit = high
                    ? "أعلى من الطبيعي (حتى \(HealthEngine.format(band.normal.upperBound, kind)))"
                    : "أقل من الطبيعي (من \(HealthEngine.format(band.normal.lowerBound, kind)))"
                notify(
                    title: "\(high ? "⬆️ ارتفاع" : "⬇️ انخفاض") في \(kind.title)",
                    body: "\(kind.title) الآن \(HealthEngine.format(v, kind))\(kind.unit) — \(limit). خفّف الجهد وراقب حالتك.",
                    log: .outOfRange,
                    sound: .default
                )
            }
        }

        if AlertSettings.rapidChange {
            for change in HealthEngine.rapidChanges(sorted, config: config) where meaningful(change) {
                let key = "rapid-\(change.kind.rawValue)-\(change.isRise)"
                if let t = lastRangeAlert[key], now.timeIntervalSince(t) < rapidCooldown { continue }
                lastRangeAlert[key] = now

                let k = change.kind
                notify(
                    title: "⚡ \(change.isRise ? "ارتفاع" : "هبوط") سريع في \(k.title)",
                    body: "من \(HealthEngine.format(change.from, k)) إلى \(HealthEngine.format(change.to, k))\(k.unit) خلال \(change.minutes) دقيقة. توقّف قليلاً وراقب حالتك.",
                    log: .rapid
                )
                buzzWatch?()
            }
        }
    }

    private func handleBreach(_ indicator: IndicatorReading, now: Date) {
        let start = breachStartedAt[indicator.kind] ?? now
        breachStartedAt[indicator.kind] = start

        // التجاوز اللحظي لا يُنبّه — فقط المتواصل.
        guard now.timeIntervalSince(start) >= config.sustainedBreach else { return }

        if let last = lastNotified[indicator.kind], now.timeIntervalSince(last) < cooldown { return }
        lastNotified[indicator.kind] = now

        var body = "\(indicator.kind.iconEmoji) قيمة \(indicator.kind.title) أصبحت \(indicator.display)\(indicator.kind.unit) وهذا يمثل خطورة. يرجى التوقف وأخذ قسط من الراحة فوراً."
        if let card = MedicalProfile.summary {
            body += "\n" + card
        }
        notify(title: "🚨 تحذير: \(indicator.kind.title) غير طبيعي", body: body, log: .critical)

        buzzWatch?()
    }

    /// هبوط النبض بعد الجهد طبيعي، وارتفاعه مع بدء النشاط طبيعي — لا يُنبَّه إلا حين ينتهي
    /// الهبوط تحت الطبيعي أو يقترب الارتفاع من الحد الأعلى.
    private func meaningful(_ change: VitalChange) -> Bool {
        guard change.kind == .heartRate else { return true }
        let band = HealthEngine.band(.heartRate, config)
        return change.isRise
            ? change.to >= band.normal.upperBound - 20
            : change.to < band.normal.lowerBound
    }

    private func notify(title: String, body: String, log: AlertLogEntry.Kind,
                        sound: UNNotificationSound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "medical_alert.wav"))) {
        AlertLog.shared.add(log, title: title, body: body)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

//
//  HistoryScreen.swift
//  SecurityPass
//
//  شاشة السجل الجديدة: تقييم عام + تفاصيل المؤشرات + تنبؤ.
//  تقرأ نفس السجلات المخزّنة محلياً. لا استدعاء شبكة ولا حقل جديد.
//

import SwiftUI

private extension VitalBand {
    var color: Color {
        switch self {
        case .normal: return SP.Color.ok
        case .caution: return SP.Color.caution
        case .critical: return SP.Color.danger
        case .unknown: return SP.Color.muted
        }
    }
    var title: String {
        switch self {
        case .normal: return "طبيعي"
        case .caution: return "خارج النطاق"
        case .critical: return "تجاوز الحد"
        case .unknown: return "—"
        }
    }
}

private extension HealthBand {
    var color: Color {
        switch self {
        case .excellent: return SP.Color.ok
        case .good: return SP.Color.accent
        case .attention: return SP.Color.caution
        case .danger: return SP.Color.danger
        }
    }
}

private extension RiskForecast.Level {
    var color: Color {
        switch self {
        case .low: return SP.Color.accent
        case .medium: return SP.Color.caution
        case .high: return SP.Color.danger
        }
    }
}

// MARK: - الشاشة

public struct HistoryScreen: View {
    public let samples: [VitalSample]
    public var employeeID: String
    public var onSelect: (VitalSample) -> Void

    @State private var selectedIndicator: IndicatorReading?
    @State private var showPastHistory: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var sleepStore = SleepStore.shared

    public init(samples: [VitalSample],
                employeeID: String,
                onSelect: @escaping (VitalSample) -> Void = { _ in }) {
        self.samples = samples
        self.employeeID = employeeID
        self.onSelect = onSelect
    }

    /// انتقال دفع (push): التفاصيل تدخل من جهة التقدّم والقائمة تنزاح قليلاً للخلف.
    private var pushAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.88)
    }

    private var detailTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var listTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(x: -60).combined(with: .opacity)
    }

    public var body: some View {
        // يُحسب التقييم والتنبؤ مرة واحدة لكل رسم بدل كل وصول للخاصية.
        let assessment = HealthEngine.assess(samples)
        let forecast = HealthEngine.forecast(samples, fatigue: sleepStore.fatigue())

        return ZStack {
            SP.Color.ground.ignoresSafeArea()

            if let selected = selectedIndicator {
                IndicatorDetailScreen(
                    indicator: selected,
                    samples: samples,
                    config: HealthThresholds.default,
                    onBack: {
                        withAnimation(pushAnimation) {
                            selectedIndicator = nil
                        }
                    }
                )
                .transition(detailTransition)
                .zIndex(1)
            } else {
                mainContent(assessment: assessment, forecast: forecast)
                    .transition(listTransition)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func mainContent(assessment: HealthAssessment, forecast: ForecastResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if assessment.isEmpty {
                    emptyState
                } else {
                    ScoreCard(assessment: assessment)
                    ForecastCard(forecast: forecast, currentScore: assessment.score)
                    SleepCard(records: sleepStore.records)
                    sectionTitle("المؤشرات الحيوية", trailing: "دقة التقييم \(Int((assessment.coverage * 100).rounded()))٪")
                    metricsGrid(assessment)
                    sectionTitle("سجل القراءات", trailing: nil)
                    readingsList
                }
                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showPastHistory) {
            NavigationView {
                HealthHistoryView()
            }
        }
    }

    // MARK: الأجزاء

    @State private var isSharing = false

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("تحليل آخر ٦ ساعات · \(employeeID)")
                    .font(.system(size: 14))
                    .foregroundColor(SP.Color.muted)
                Text("السجل الصحي")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(SP.Color.text)
            }
            Spacer()
            Button {
                showPastHistory = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundColor(SP.Color.text)
                    .frame(width: 44, height: 44)
                    .background(SP.Color.card)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
            }
            
            Button {
                isSharing = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(SP.Color.text)
                    .frame(width: 44, height: 44)
                    .background(SP.Color.card)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isSharing) {
            ShareHealthReportView(samples: samples, employeeID: employeeID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundColor(SP.Color.dim)
            Text("لا يوجد سجل حتى الآن")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SP.Color.text)
            Text("سيبدأ التقييم تلقائياً بعد وصول أول قراءات من السوار.")
                .font(.system(size: 14))
                .foregroundColor(SP.Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(cardBackground(border: SP.Color.raised))
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(SP.Color.text)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundColor(SP.Color.muted)
            }
        }
        .padding(.top, 8)
    }

    private func metricsGrid(_ assessment: HealthAssessment) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)], spacing: 14) {
            ForEach(assessment.indicators.filter { $0.kind != .stability }, id: \.kind) { indicator in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(pushAnimation) {
                        selectedIndicator = indicator
                    }
                } label: {
                    MetricCard(indicator: indicator, series: series(for: indicator.kind))
                }
                .buttonStyle(SPPressableCard())
            }
        }
    }

    private var readingsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recentSamples.enumerated()), id: \.offset) { _, sample in
                Button { onSelect(sample) } label: {
                    ReadingRow(sample: sample)
                }
                .buttonStyle(.plain)
                Divider().overlay(SP.Color.raised)
            }
        }
        .background(cardBackground(border: SP.Color.raised))
    }

    private var disclaimer: some View {
        Text("تقييم إرشادي للسلامة، مبني على قراءات السوار فقط. ليس تشخيصاً طبياً ولا بديلاً عن مراجعة الطبيب.")
            .font(.system(size: 12))
            .lineSpacing(4)
            .foregroundColor(SP.Color.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: بيانات مساعدة

    private var recentSamples: [VitalSample] {
        samples.sorted { $0.sampleDate > $1.sampleDate }.prefix(20).map { $0 }
    }

    private func series(for kind: VitalKind) -> [Double] {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }.suffix(40)
        switch kind {
        case .heartRate: return sorted.compactMap { $0.vHeartRate.map(Double.init) }
        case .spo2:      return sorted.compactMap { $0.vSpo2.map(Double.init) }
        case .bodyTemp:  return sorted.compactMap { $0.bodyTemp }
        case .pressure:  return sorted.compactMap { $0.systolic.map(Double.init) }
        case .stability: return []
        }
    }
}

// MARK: - بطاقة التقييم العام

private struct ScoreCard: View {
    let assessment: HealthAssessment

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(SP.Color.raised, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(assessment.score) / 100)
                    .stroke(assessment.band.color,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.7), value: assessment.score)
                
                VStack(spacing: 0) {
                    Text("\(assessment.score)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(SP.Color.text)
                    Text("من ١٠٠")
                        .font(.system(size: 11))
                        .foregroundColor(SP.Color.muted)
                }
            }
            .frame(width: 90, height: 90)
            .shadow(color: assessment.band.color.opacity(0.3), radius: 12, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الحالة الحالية")
                        .font(.system(size: 13))
                        .foregroundColor(SP.Color.muted)
                    HStack(spacing: 8) {
                        Circle().fill(assessment.band.color).frame(width: 8, height: 8)
                        Text(assessment.band.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(SP.Color.text)
                            .id(assessment.band)
                            .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.3), value: assessment.band)
                }
                
                Text(assessment.headline)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundColor(SP.Color.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [SP.Color.card, SP.Color.navBar], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(SP.Color.raised, lineWidth: 1)
                )
        )
    }
}

// MARK: - بطاقة التنبؤ

private struct ForecastCard: View {
    let forecast: ForecastResult
    let currentScore: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label {
                    Text("تنبؤ الساعة القادمة")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SP.Color.text)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundColor(SP.Color.caution)
                }
                Spacer()
                if !forecast.insufficientCoverage {
                    if forecast.isPreliminary {
                        chip("أولي", color: SP.Color.caution)
                    }
                    chip("الثقة \(Int((forecast.confidence * 100).rounded()))٪", color: SP.Color.muted)
                }
            }

            if forecast.insufficientCoverage {
                Text("بانتظار قراءة حديثة من السوار — يبدأ التنبؤ فور وصولها.")
                    .font(.system(size: 14))
                    .foregroundColor(SP.Color.muted)
            } else {
                if let projected = forecast.projectedScore {
                    projectedRow(projected)
                }

                if forecast.risks.isEmpty {
                    Label("جميع المؤشرات مستقرة للساعة القادمة.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(SP.Color.ok)
                } else {
                    ForEach(forecast.risks.prefix(3)) { risk in
                        riskRow(risk)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground(radius: 20, border: borderColor))
        .animation(.easeInOut(duration: 0.35), value: forecast.risks.map { $0.id + $0.level.rawValue })
    }

    private var borderColor: Color {
        guard let top = forecast.risks.first, top.level != .low else { return SP.Color.raised }
        return top.level.color.opacity(0.5)
    }

    private func projectedRow(_ projected: Int) -> some View {
        let delta = projected - currentScore
        let color: Color = delta <= -10 ? SP.Color.dangerText : (delta < 0 ? SP.Color.caution : SP.Color.ok)
        return HStack(spacing: 6) {
            Text("الدرجة المتوقعة بعد ساعة")
                .font(.system(size: 13))
                .foregroundColor(SP.Color.muted)
            Spacer()
            Text("\(projected)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(SP.Color.text)
            if delta != 0 {
                Text(delta > 0 ? "▲ \(delta)" : "▼ \(-delta)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
    }

    private func riskRow(_ risk: RiskForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(risk.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(risk.level.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(Int((risk.probability * 100).rounded()))٪")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(SP.Color.text)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SP.Color.raised)
                    Capsule()
                        .fill(LinearGradient(colors: [risk.level.color.opacity(0.5), risk.level.color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(risk.probability, 0), 1)))
                        .animation(.easeOut(duration: 0.6), value: risk.probability)
                }
            }
            .frame(height: 6)

            Text(risk.why)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundColor(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let eta = risk.minutesToThreshold, eta <= Double(forecast.horizonMinutes) {
                Label("متوقع خلال ~\(max(1, Int(eta.rounded()))) دقيقة", systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(risk.level.color)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - بطاقة النوم

/// تظهر لصاحب الجهاز فقط — لا تُرسل ولا تدخل التقرير المشترك.
private struct SleepCard: View {
    let records: [SleepRecord]

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA")
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label {
                    Text("النوم")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SP.Color.text)
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(SP.Color.measure)
                }
                Spacer()
                if let night = records.first {
                    let insight = SleepAnalyzer.insight(for: night, history: records)
                    Text(insight.level.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color(insight.level))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color(insight.level).opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let night = records.first {
                content(night)
            } else {
                Text("لا توجد بيانات نوم بعد — ارتدِ السوار أثناء النوم وستظهر هنا بعد المزامنة.")
                    .font(.system(size: 13))
                    .foregroundColor(SP.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardBackground(radius: 20, border: SP.Color.raised))
    }

    @ViewBuilder
    private func content(_ night: SleepRecord) -> some View {
        let insight = SleepAnalyzer.insight(for: night, history: records)

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(SleepAnalyzer.format(minutes: night.totalMinutes))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(SP.Color.text)
            Text("الجودة \(insight.quality)/100")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color(insight.level))
            Spacer()
        }

        if let start = night.fellAsleep, let end = night.wokeUp {
            Text("من \(Self.time.string(from: start)) إلى \(Self.time.string(from: end))")
                .font(.system(size: 12))
                .foregroundColor(SP.Color.muted)
        }

        stagesBar(night)

        if records.count > 1 {
            weekBars
        }

        Text(insight.message)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundColor(SP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// توزيع مراحل النوم.
    private func stagesBar(_ n: SleepRecord) -> some View {
        let stages: [(String, Int, Color)] = [
            ("عميق", n.deepMinutes, SP.Color.accent),
            ("خفيف", n.lightMinutes, SP.Color.measure),
            ("حالم", n.remMinutes, SP.Color.ok),
            ("استيقاظ", n.awakeMinutes, SP.Color.caution)
        ].filter { $0.1 > 0 }
        let total = max(1, stages.map { $0.1 }.reduce(0, +))

        return VStack(alignment: .leading, spacing: 8) {
            if !stages.isEmpty {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(stages.indices, id: \.self) { i in
                            Rectangle()
                                .fill(stages[i].2)
                                .frame(width: max(2, (geo.size.width - CGFloat(stages.count - 1) * 2)
                                                  * CGFloat(stages[i].1) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())

                HStack(spacing: 12) {
                    ForEach(stages.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            Circle().fill(stages[i].2).frame(width: 6, height: 6)
                            Text("\(stages[i].0) \(SleepAnalyzer.format(minutes: stages[i].1))")
                                .font(.system(size: 11))
                                .foregroundColor(SP.Color.muted)
                        }
                    }
                }
            }
        }
    }

    /// آخر ٧ ليالٍ — ارتفاع العمود بالمدة ولونه بالجودة، والخط المتقطع عند ٧ ساعات.
    private var weekBars: some View {
        let nights = Array(records.prefix(7).reversed())
        let maxMinutes = Double(max(9 * 60, nights.map { $0.totalMinutes }.max() ?? 0))

        return VStack(alignment: .leading, spacing: 6) {
            Text("آخر \(nights.count) ليالٍ")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SP.Color.muted)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(nights) { n in
                    let level = SleepAnalyzer.insight(for: n, history: records).level
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(level))
                            .frame(height: max(4, 60 * CGFloat(Double(n.totalMinutes) / maxMinutes)))
                        Text(String(format: "%.1f", Double(n.totalMinutes) / 60))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(SP.Color.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
    }

    private func color(_ level: SleepInsight.Level) -> Color {
        switch level {
        case .good: return SP.Color.ok
        case .fair: return SP.Color.caution
        case .poor: return SP.Color.danger
        }
    }
}

// MARK: - بطاقة مؤشر

private struct MetricCard: View {
    let indicator: IndicatorReading
    let series: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(indicator.kind.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SP.Color.text)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(indicator.band.color)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(indicator.display)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(indicator.band == .critical ? SP.Color.dangerText : SP.Color.text)
                Text(indicator.kind.unit)
                    .font(.system(size: 12))
                    .foregroundColor(SP.Color.muted)
            }

            Sparkline(values: series)
                .stroke(
                    LinearGradient(colors: [indicator.band.color.opacity(0.3), indicator.band.color], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .frame(height: 34)

            HStack(spacing: 8) {
                StatusPill(text: indicator.band.title, color: indicator.band.color)
                Spacer()
                if let trend = indicator.trend {
                    Text(trend.directionTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SP.Color.muted)
                }
            }
        }
        .padding(16)
        .background(cardBackground(radius: 20, border: indicator.band == .normal
                                   ? SP.Color.raised
                                   : indicator.band.color.opacity(0.5)))
    }

    private var icon: String {
        switch indicator.kind {
        case .heartRate: return "heart.fill"
        case .spo2: return "drop.fill"
        case .bodyTemp: return "thermometer.medium"
        case .pressure: return "waveform.path.ecg"
        case .stability: return "chart.bar.fill"
        }
    }
}

// MARK: - شاشة التفاصيل (IndicatorDetailScreen)

private struct IndicatorDetailScreen: View {
    let indicator: IndicatorReading
    let samples: [VitalSample]
    let config: HealthThresholds
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                        Text("رجوع")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(SP.Color.accent)
                }
                Spacer()
                Text(indicator.kind.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(SP.Color.text)
                Spacer()
                // Empty view for symmetry
                Text("رجوع").opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 24) {
                    // Big Value Card
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(indicator.display)
                                .font(.system(size: 54, weight: .bold, design: .monospaced))
                                .foregroundColor(indicator.band == .critical ? SP.Color.dangerText : SP.Color.text)
                            Text(indicator.kind.unit)
                                .font(.system(size: 18))
                                .foregroundColor(SP.Color.muted)
                        }
                        StatusPill(text: indicator.band.title, color: indicator.band.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(cardBackground(border: SP.Color.raised))
                    .padding(.horizontal, 20)

                    // Trend Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("الاتجاه · آخر ٤٠ دقيقة")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(SP.Color.text)
                            Spacer()
                            if let trend = indicator.trend {
                                Text(trend.directionTitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(SP.Color.muted)
                            }
                        }
                        
                        TrendChart(values: series, color: indicator.band.color)
                            .frame(height: 160)

                        if let trend = indicator.trend, indicator.kind != .stability {
                            Divider().overlay(SP.Color.raised)
                            HStack {
                                Text("المتوقع بعد ساعة")
                                    .font(.system(size: 13))
                                    .foregroundColor(SP.Color.muted)
                                Spacer()
                                Text("\(HealthEngine.format(trend.projected, indicator.kind)) \(indicator.kind.unit)")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(SP.Color.text)
                            }
                            if let eta = trend.minutesToThreshold, eta <= 60 {
                                Label("قد يبلغ الحد الحرج خلال ~\(max(1, Int(eta.rounded()))) دقيقة",
                                      systemImage: "clock.badge.exclamationmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SP.Color.caution)
                            }
                        }
                    }
                    .padding(20)
                    .background(cardBackground(border: SP.Color.raised))
                    .padding(.horizontal, 20)

                    // Ranges Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("نطاقات المؤشر")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SP.Color.text)
                        
                        RangeBar(kind: indicator.kind, value: indicator.value, config: config)
                    }
                    .padding(20)
                    .background(cardBackground(border: SP.Color.raised))
                    .padding(.horizontal, 20)

                    // Recommendation Card
                    if indicator.band != .normal {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(indicator.band.color)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("توصية")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(indicator.band.color)
                                Text(recommendation)
                                    .font(.system(size: 13))
                                    .lineSpacing(4)
                                    .foregroundColor(SP.Color.text)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(indicator.band.color.opacity(0.1))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(indicator.band.color.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(SP.Color.ground.ignoresSafeArea())
    }

    /// التوصية تتبع جهة الانحراف فعلاً — النص القديم كان يقول «أعلى» حتى عند الانخفاض.
    private var recommendation: String {
        let b = HealthEngine.band(indicator.kind, config)
        let isLow = indicator.value < b.normal.lowerBound
        switch indicator.kind {
        case .heartRate:
            return isLow
                ? "النبض أقل من المعدل الطبيعي. إذا شعرت بدوار أو إعياء توقف واجلس وتواصل مع غرفة العمليات."
                : "النبض أعلى من المعدل الطبيعي. خفّف الجهد وخذ قسطاً من الراحة واشرب الماء، وتواصل مع غرفة العمليات إذا استمر الارتفاع."
        case .spo2:
            return "الأكسجين أقل من الطبيعي. انتقل إلى مكان جيد التهوية وتنفّس بعمق وتأكد من ثبات السوار على المعصم، وتواصل مع غرفة العمليات إذا لم يتحسن."
        case .bodyTemp:
            return isLow
                ? "حرارة الجسم منخفضة. ابتعد عن البرودة وارتدِ ملابس دافئة."
                : "حرارة الجسم مرتفعة. انتقل إلى الظل أو مكان بارد واشرب الماء وخفّف الملابس الثقيلة."
        case .pressure:
            return "قيمة الضغط خارج النطاق (قد تكون تقديرية من النبض). خذ قسطاً من الراحة وأعد القياس، وتواصل مع غرفة العمليات إذا استمرت."
        case .stability:
            return "النبض متذبذب أكثر من المعتاد. خفّف الحركة لدقائق حتى يستقر."
        }
    }

    private var series: [Double] {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }.suffix(40)
        switch indicator.kind {
        case .heartRate: return sorted.compactMap { $0.vHeartRate.map(Double.init) }
        case .spo2:      return sorted.compactMap { $0.vSpo2.map(Double.init) }
        case .bodyTemp:  return sorted.compactMap { $0.bodyTemp }
        case .pressure:  return sorted.compactMap { $0.systolic.map(Double.init) }
        case .stability: return []
        }
    }
}

// MARK: - Trend Chart

private struct TrendChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pathInfo = makePath(in: geo.size)
            
            ZStack {
                // Gradient Fill
                pathInfo.fillPath
                    .fill(LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                
                // Line
                pathInfo.linePath
                    .stroke(
                        LinearGradient(colors: [color.opacity(0.5), color], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                
                // Dots
                ForEach(pathInfo.points.indices, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(pathInfo.points[i])
                        .shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 2)
                }
            }
        }
    }

    private func makePath(in size: CGSize) -> (linePath: Path, fillPath: Path, points: [CGPoint]) {
        var line = Path()
        var fill = Path()
        var pts: [CGPoint] = []
        guard values.count > 1, let minVal = values.min(), let maxVal = values.max() else {
            return (line, fill, pts)
        }
        
        let span = maxVal - minVal
        let paddedSpan = span == 0 ? 1 : span * 1.5
        let stepX = size.width / CGFloat(values.count - 1)
        
        for (i, v) in values.enumerated() {
            let ratio = span == 0 ? 0.5 : (v - minVal + (span * 0.25)) / paddedSpan
            let pt = CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(ratio) * size.height)
            pts.append(pt)
            
            if i == 0 {
                line.move(to: pt)
                fill.move(to: CGPoint(x: pt.x, y: size.height))
                fill.addLine(to: pt)
            } else {
                line.addLine(to: pt)
                fill.addLine(to: pt)
            }
            
            if i == values.count - 1 {
                fill.addLine(to: CGPoint(x: pt.x, y: size.height))
                fill.closeSubpath()
            }
        }
        return (line, fill, pts)
    }
}

// MARK: - Range Bar

/// شريط النطاقات بالقيم الحقيقية من الإعدادات مع مؤشر للقيمة الحالية.
private struct RangeBar: View {
    let kind: VitalKind
    let value: Double
    let config: HealthThresholds

    private var band: HealthThresholds.Band { HealthEngine.band(kind, config) }

    /// مجال العرض: من تحت الحد الحرج الأدنى بقليل إلى فوق الأعلى بقليل.
    private var domain: ClosedRange<Double> {
        let b = band
        let pad = max((b.criticalHigh - b.criticalLow) * 0.12, 0.5)
        let lo = min(b.criticalLow - pad, value)
        let hi = max(b.criticalHigh + (kind == .spo2 ? 0 : pad), value)
        return lo...max(hi, lo + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach(segments.indices, id: \.self) { i in
                        let s = segments[i]
                        Rectangle()
                            .fill(s.color)
                            .frame(width: max(0, x(s.to, w) - x(s.from, w)), height: 12)
                            .offset(x: x(s.from, w))
                    }
                    Capsule()
                        .fill(SP.Color.text)
                        .frame(width: 4, height: 22)
                        .offset(x: min(max(x(value, w) - 2, 0), w - 4))
                        .shadow(color: Color.black.opacity(0.4), radius: 3)
                }
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)
            .environment(\.layoutDirection, .leftToRight)

            HStack {
                Text(HealthEngine.format(band.criticalLow, kind))
                Spacer()
                Text("الطبيعي \(HealthEngine.format(band.normal.lowerBound, kind))–\(HealthEngine.format(band.normal.upperBound, kind))")
                Spacer()
                Text(kind == .spo2 ? "" : HealthEngine.format(band.criticalHigh, kind))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(SP.Color.muted)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private struct Segment { let from: Double; let to: Double; let color: Color }

    private var segments: [Segment] {
        let b = band
        let d = domain
        return [
            Segment(from: d.lowerBound, to: b.criticalLow, color: SP.Color.danger),
            Segment(from: b.criticalLow, to: b.normal.lowerBound, color: SP.Color.caution),
            Segment(from: b.normal.lowerBound, to: b.normal.upperBound, color: SP.Color.ok),
            Segment(from: b.normal.upperBound, to: b.criticalHigh, color: SP.Color.caution),
            Segment(from: b.criticalHigh, to: d.upperBound, color: SP.Color.danger)
        ].filter { $0.to > $0.from }
    }

    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        let d = domain
        let r = (min(max(v, d.lowerBound), d.upperBound) - d.lowerBound) / (d.upperBound - d.lowerBound)
        return CGFloat(r) * width
    }
}

// MARK: - صف قراءة

private struct ReadingRow: View {
    let sample: VitalSample

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(dotColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString(sample.sampleDate))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(SP.Color.text)
                Text(vitalsLine)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(SP.Color.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA")
        f.dateFormat = "hh:mm a"
        return f.string(from: date)
    }

    private var vitalsLine: String {
        var parts: [String] = []
        if let hr = sample.vHeartRate { parts.append("\(hr) bpm") }
        if let o = sample.vSpo2 { parts.append("\(o)%") }
        if let t = sample.bodyTemp { parts.append(String(format: "%.1f°", t)) }
        if let s = sample.systolic, let d = sample.diastolic { parts.append("\(s)/\(d)") }
        return parts.isEmpty ? "لا توجد قراءة — السوار غير متصل" : parts.joined(separator: " · ")
    }

    private var dotColor: Color {
        guard sample.vHeartRate != nil || sample.vSpo2 != nil else { return SP.Color.muted }
        return HealthEngine.quickBand(sample).color
    }
}

// MARK: - عناصر صغيرة

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1,
              let minVal = values.min(), let maxVal = values.max() else { return path }
        let span = maxVal - minVal
        let paddedSpan = span == 0 ? 1 : span * 1.5
        let stepX = rect.width / CGFloat(values.count - 1)

        for (i, v) in values.enumerated() {
            let ratio = span == 0 ? 0.5 : (v - minVal + (span * 0.25)) / paddedSpan
            let point = CGPoint(x: CGFloat(i) * stepX,
                                y: rect.height - CGFloat(ratio) * rect.height)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private func cardBackground(radius: CGFloat = 20, border: Color) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(SP.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
}


//
//  HealthReport.swift
//  SecurityPass
//
//  نموذج التقرير الصحي: يجمّع السجلات المخزّنة محلياً في بنية جاهزة للطباعة.
//  لا شبكة، ولا حقل جديد، ولا تغيير على قاعدة البيانات أو البروتوكول.
//

import Foundation

public enum ReportPeriod: String, CaseIterable, Identifiable {
    case eightHours, today, week, month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .eightHours: return "آخر ٨ ساعات"
        case .today: return "آخر ٢٤ ساعة"
        case .week:  return "آخر ٧ أيام"
        case .month: return "آخر ٣٠ يوماً"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .eightHours: return 8 * 3600
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
    /// نسبة الوقت خارج الطبيعي دون الحد الحرج ٠…١.
    public var cautionShare: Double = 0
    /// نسبة الوقت عند الحد الحرج أو بعده ٠…١.
    public var criticalShare: Double = 0
}

/// جودة البيانات: كم قراءة وصلت مقارنة بالمتوقع، وأين انقطع السوار.
public struct ReportDataQuality {
    public let received: Int
    public let expected: Int
    public let coverage: Double
    /// عدد الانقطاعات التي تتجاوز ٥ دقائق.
    public let gapCount: Int
    public let longestGapMinutes: Int
    public let firstReading: Date?
    public let lastReading: Date?
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
    /// نوبات التجاوز الحرج المتواصلة، الأحدث أولاً.
    public var episodes: [HealthEpisode] = []
    /// تنبؤ الساعة القادمة — فقط إن كانت آخر قراءة حديثة عند إنشاء التقرير.
    public var forecast: ForecastResult? = nil
    public var quality: ReportDataQuality? = nil
    /// أبرز النتائج والتوصيات المولّدة من البيانات.
    public var findings: [String] = []

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

        // تقييم الفترة كاملة، لا آخر ست ساعات منها فقط.
        let assessment = HealthEngine.assessPeriod(window, from: from, to: now, config: config)
        let summary = summaries(window, config: config)
        let episodes = HealthEngine.episodes(window, config: config)
        let quality = dataQuality(window, from: from, to: now, config: config)

        var forecast: ForecastResult?
        if let last = window.last, now.timeIntervalSince(last.sampleDate) <= 30 * 60 {
            forecast = HealthEngine.forecast(samples, now: now, config: config)
        }

        var report = HealthReport(
            employeeID: employeeID,
            period: period,
            from: from,
            to: now,
            generatedAt: now,
            assessment: assessment,
            summary: summary,
            daily: dailyStats(window, config: config),
            readings: window.reversed().prefix(maxReadings).map { line(for: $0, config: config) },
            readingsTotal: window.count,
            heartRateSeries: window.compactMap { s in
                HealthEngine.value(s, .heartRate).map { (date: s.sampleDate, value: $0) }
            }
        )
        report.episodes = episodes
        report.forecast = forecast
        report.quality = quality
        report.findings = findings(summary: summary, episodes: episodes, quality: quality,
                                   forecast: forecast, assessment: assessment)
        return report
    }

    // MARK: جودة البيانات

    private static func dataQuality(_ window: [VitalSample], from: Date, to: Date,
                                    config: HealthThresholds) -> ReportDataQuality {
        guard let first = window.first, let last = window.last else {
            return ReportDataQuality(received: 0, expected: 0, coverage: 0, gapCount: 0,
                                     longestGapMinutes: 0, firstReading: nil, lastReading: nil)
        }
        // المتوقع يبدأ من أول قراءة فعلية — لا يُحتسب وقت قبل بدء المراقبة.
        let span = to.timeIntervalSince(max(from, first.sampleDate))
        let expected = max(1, Int(span / config.expectedInterval) + 1)

        var gaps = 0
        var longest: TimeInterval = 0
        for (a, b) in zip(window, window.dropFirst()) {
            let gap = b.sampleDate.timeIntervalSince(a.sampleDate)
            if gap > 5 * 60 { gaps += 1 }
            longest = max(longest, gap)
        }
        let tail = to.timeIntervalSince(last.sampleDate)
        if tail > 5 * 60 { gaps += 1; longest = max(longest, tail) }

        return ReportDataQuality(
            received: window.count,
            expected: expected,
            coverage: min(1, Double(window.count) / Double(expected)),
            gapCount: gaps,
            longestGapMinutes: Int((longest / 60).rounded()),
            firstReading: first.sampleDate,
            lastReading: last.sampleDate
        )
    }

    // MARK: النتائج والتوصيات

    private static func findings(summary: [IndicatorSummary], episodes: [HealthEpisode],
                                 quality: ReportDataQuality, forecast: ForecastResult?,
                                 assessment: HealthAssessment) -> [String] {
        var out: [String] = []

        func count(_ kind: VitalKind, high: Bool) -> (n: Int, longest: Int) {
            let list = episodes.filter { $0.kind == kind && $0.isHigh == high }
            return (list.count, list.map { $0.durationMinutes }.max() ?? 0)
        }

        if episodes.isEmpty {
            out.append("لم تُسجَّل أي نوبة تجاوز حرج متواصلة خلال الفترة.")
        }

        let hrHigh = count(.heartRate, high: true)
        if hrHigh.n > 0 {
            out.append("ارتفاع النبض فوق الحد الحرج \(hrHigh.n) مرة (أطولها \(hrHigh.longest) دقيقة): راجع فترات الجهد البدني ووزّع الاستراحات عليها.")
        }
        let hrLow = count(.heartRate, high: false)
        if hrLow.n > 0 {
            out.append("انخفاض النبض تحت الحد الحرج \(hrLow.n) مرة: يستحق متابعة طبية إن تكرر مع دوار أو إعياء.")
        }
        let o2 = count(.spo2, high: false)
        if o2.n > 0 {
            out.append("انخفاض الأكسجين تحت الحد الحرج \(o2.n) مرة (أطولها \(o2.longest) دقيقة): تحقق من تهوية المكان وثبات السوار على المعصم.")
        }
        let heat = count(.bodyTemp, high: true)
        if heat.n > 0 {
            out.append("ارتفاع حرارة الجسم \(heat.n) مرة: راجع التعرض للحرارة وجدول شرب الماء والاستراحة في الظل.")
        }
        let bp = count(.pressure, high: true)
        if bp.n > 0 {
            out.append("ارتفاع الضغط \(bp.n) مرة (القيم قد تكون تقديرية من النبض): يُنصح بقياس مؤكد بجهاز ضغط.")
        }

        for s in summary where s.kind != .pressure && s.inRange < 0.7 {
            out.append("\(s.kind.title) خارج النطاق الطبيعي \(Int(((1 - s.inRange) * 100).rounded()))٪ من وقت المراقبة.")
        }

        if let f = forecast, let top = f.risks.first, top.level != .low {
            out.append("تنبؤ الساعة القادمة: \(top.name) بنسبة \(Int((top.probability * 100).rounded()))٪ (ثقة \(Int((f.confidence * 100).rounded()))٪).")
        }

        if quality.received > 0 && quality.coverage < 0.6 {
            out.append("وصل \(Int((quality.coverage * 100).rounded()))٪ فقط من القراءات المتوقعة (أطول انقطاع \(quality.longestGapMinutes) دقيقة) — الانقطاع يقلل دقة التقييم؛ تأكد من شحن السوار وبقائه متصلاً.")
        }

        if out.count == 1 && assessment.band.severity <= 1 {
            out.append("المؤشرات ضمن النطاق في معظم الوقت — يُنصح بالاستمرار على نمط النشاط والترطيب الحالي.")
        }
        return out
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
            let n = Double(values.count)
            let inRange = Double(values.filter { band.normal.contains($0) }.count) / n
            let critical = Double(values.filter { HealthEngine.classify($0, band) == .critical }.count) / n

            func f(_ v: Double) -> String {
                decimals == 0 ? "\(Int(v.rounded()))" : String(format: "%.\(decimals)f", v)
            }

            out.append(IndicatorSummary(
                kind: kind, latest: f(latest), minimum: f(lo),
                average: f(avg), maximum: f(hi),
                band: HealthEngine.classify(latest, band), inRange: inRange,
                cautionShare: max(0, 1 - inRange - critical), criticalShare: critical
            ))
        }

        // القيم المستحيلة (حرارة ٠ عند عدم القياس) تُستبعد بدل أن تُحسب انخفاضاً حرجاً.
        add(.heartRate, config.heartRate, window.compactMap { HealthEngine.value($0, .heartRate) })
        add(.spo2, config.spo2, window.compactMap { HealthEngine.value($0, .spo2) })
        add(.bodyTemp, config.bodyTemp, window.compactMap { HealthEngine.value($0, .bodyTemp) }, decimals: 1)
        add(.pressure, config.systolic, window.compactMap { HealthEngine.value($0, .pressure) })

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
            let assessment = HealthEngine.assessPeriod(items, from: day, to: endOfDay, config: config)

            let hr = items.compactMap { HealthEngine.value($0, .heartRate) }
            let spo2 = items.compactMap { HealthEngine.value($0, .spo2) }
            let temp = items.compactMap { HealthEngine.value($0, .bodyTemp) }

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
        ReadingLine(
            date: s.sampleDate,
            heartRate: s.vHeartRate.map { "\($0)" } ?? "—",
            spo2: s.vSpo2.map { "\($0)%" } ?? "—",
            pressure: {
                guard let sys = s.systolic else { return "—" }
                guard let dia = s.diastolic else { return "\(sys)" }
                return "\(sys)/\(dia)"
            }(),
            temperature: HealthEngine.value(s, .bodyTemp).map { String(format: "%.1f", $0) } ?? "—",
            band: HealthEngine.quickBand(s, config: config)
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

    public static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM hh:mm a"
        return f
    }()

    public static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f
    }()
}


//
//  HealthReportPDF.swift
//  SecurityPass
//
//  مولّد تقرير PDF متعدد الصفحات — رسم مباشر بـ Core Graphics.
//  النص متجهي قابل للتحديد والبحث والطباعة بوضوح، لا لقطة شاشة.
//  ألوان الطباعة نسخ داكنة من ألوان الشاشة: الأخضر النيون على أبيض غير مقروء.
//

import UIKit

public enum HealthReportPDF {

    // MARK: ألوان الطباعة

    private enum Ink {
        static let text      = UIColor(red: 0.00, green: 0.07, blue: 0.22, alpha: 1)  // #001338
        static let muted     = UIColor(red: 0.35, green: 0.40, blue: 0.51, alpha: 1)  // #5A6682
        static let rule      = UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1)  // #E2E7F0
        static let cardFill  = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)  // #F5F7FB
        static let accent    = UIColor(red: 0.09, green: 0.23, blue: 0.47, alpha: 1)  // #163A77
        static let success   = UIColor(red: 0.05, green: 0.48, blue: 0.27, alpha: 1)  // #0E7A45
        static let caution   = UIColor(red: 0.66, green: 0.36, blue: 0.00, alpha: 1)  // #A85C00
        static let danger    = UIColor(red: 0.75, green: 0.12, blue: 0.16, alpha: 1)  // #C01F28
    }

    private static func color(_ band: VitalBand) -> UIColor {
        switch band {
        case .normal:   return Ink.success
        case .caution:  return Ink.caution
        case .critical: return Ink.danger
        case .unknown:  return Ink.muted
        }
    }

    private static func color(_ band: HealthBand) -> UIColor {
        switch band {
        case .excellent: return Ink.success
        case .good:      return Ink.accent
        case .attention: return Ink.caution
        case .danger:    return Ink.danger
        }
    }

    private static func title(_ band: VitalBand) -> String {
        switch band {
        case .normal:   return "طبيعي"
        case .caution:  return "خارج النطاق"
        case .critical: return "تجاوز الحد"
        case .unknown:  return "—"
        }
    }

    // MARK: قياسات الصفحة

    private static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 18
    private static let rowsPerPage = 36

    private static var contentWidth: CGFloat { page.width - margin * 2 }

    // MARK: الواجهة

    /// ينتج ملف PDF في مجلد مؤقت ويعيد مساره، جاهزاً للمشاركة.
    public static func render(_ report: HealthReport) throws -> URL {
        let readingPages = report.readings.isEmpty
            ? 0
            : Int(ceil(Double(report.readings.count) / Double(rowsPerPage)))
        let totalPages = 2 + readingPages

        let info: [String: Any] = [
            kCGPDFContextTitle as String: "التقرير الصحي — \(report.employeeID)",
            kCGPDFContextCreator as String: "SecurityPass"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = info

        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName(for: report))

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            drawSummaryPage(report)
            drawFooter(page: 1, of: totalPages, report: report)

            ctx.beginPage()
            drawAnalysisPage(report)
            drawFooter(page: 2, of: totalPages, report: report)

            for index in 0..<readingPages {
                ctx.beginPage()
                drawReadingsPage(report, pageIndex: index)
                drawFooter(page: index + 3, of: totalPages, report: report)
            }
        }
        try data.write(to: url)
        return url
    }

    public static func fileName(for report: HealthReport) -> String {
        let stamp = ReportFormat.fileStamp.string(from: report.generatedAt)
        let id = report.employeeID.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return "SecurityPass_Health_\(id)_\(stamp)_\(UUID().uuidString.prefix(4)).pdf"
    }

    // MARK: الصفحة الأولى

    private static func drawSummaryPage(_ report: HealthReport) {
        var y = drawHeader(report)
        y = drawScoreBlock(report, top: y + 18)
        y = drawIndicatorGrid(report, top: y + 18)
        y = drawChart(report, top: y + 18)
        _ = drawDailyTable(report, top: y + 18)
    }

    private static func drawHeader(_ report: HealthReport) -> CGFloat {
        Ink.accent.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: page.width, height: 6)).fill()

        var y: CGFloat = margin + 6
        text("التقرير الصحي", CGRect(x: margin, y: y, width: contentWidth, height: 30),
             font: .systemFont(ofSize: 24, weight: .bold), color: Ink.text)
        y += 30

        text("SecurityPass · المعرف الوظيفي \(report.employeeID)",
             CGRect(x: margin, y: y, width: contentWidth, height: 18),
             font: .systemFont(ofSize: 12), color: Ink.muted)
        y += 18

        let range = "\(ReportFormat.dayMonth.string(from: report.from)) — \(ReportFormat.dayMonth.string(from: report.to))"
        text("\(report.period.title) · \(range) · \(report.assessment.sampleCount) قراءة",
             CGRect(x: margin, y: y, width: contentWidth, height: 18),
             font: .systemFont(ofSize: 12), color: Ink.muted)
        y += 22

        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 1)).fill()

        return y
    }

    private static func drawScoreBlock(_ report: HealthReport, top: CGFloat) -> CGFloat {
        let height: CGFloat = 92
        let rect = CGRect(x: margin, y: top, width: contentWidth, height: height)
        card(rect)

        let a = report.assessment
        let accent = color(a.band)

        // شريط لوني على الحافة اليمنى (اتجاه القراءة)
        accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.maxX - 5, y: rect.minY, width: 5, height: height),
                     cornerRadius: 2.5).fill()

        let pad: CGFloat = 16
        var y = rect.minY + pad
        text("التقييم العام للفترة",
             CGRect(x: rect.minX + pad, y: y, width: rect.width - pad * 2 - 8, height: 14),
             font: .systemFont(ofSize: 11), color: Ink.muted)
        y += 16

        text("\(a.score)", CGRect(x: rect.maxX - 150, y: y, width: 130, height: 34),
             font: .monospacedDigitSystemFont(ofSize: 30, weight: .bold), color: Ink.text)

        text("من ١٠٠ · \(a.band.title)",
             CGRect(x: rect.minX + pad, y: y + 10, width: rect.width - 180, height: 18),
             font: .systemFont(ofSize: 13, weight: .semibold), color: accent)
        y += 38

        text(a.headline,
             CGRect(x: rect.minX + pad, y: y, width: rect.width - pad * 2 - 8, height: 32),
             font: .systemFont(ofSize: 11), color: Ink.text, lines: 2)

        return rect.maxY
    }

    private static func drawIndicatorGrid(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.summary.isEmpty else { return top }

        let columns = 4
        let gap: CGFloat = 8
        let w = (contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let h: CGFloat = 74

        var maxY = top
        for (i, s) in report.summary.enumerated() {
            let row = i / columns
            let col = i % columns

            // RTL: العمود الأول على اليمين
            let x = margin + CGFloat(columns - 1 - col) * (w + gap)
            let y = top + CGFloat(row) * (h + gap)

            let rect = CGRect(x: x, y: y, width: w, height: h)
            card(rect)

            let pad: CGFloat = 9
            let inner = CGRect(x: rect.minX + pad, y: rect.minY + pad,
                               width: rect.width - pad * 2, height: 0)

            text(s.kind.title, inner.offsetBy(dx: 0, dy: 0).with(height: 12),
                 font: .systemFont(ofSize: 9.5), color: Ink.muted)

            text("\(s.latest) \(s.kind.unit)",
                 inner.offsetBy(dx: 0, dy: 13).with(height: 20),
                 font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold), color: Ink.text)

            text(title(s.band),
                 inner.offsetBy(dx: 0, dy: 33).with(height: 12),
                 font: .systemFont(ofSize: 8.5, weight: .semibold), color: color(s.band))

            text("أدنى \(s.minimum) · وسط \(s.average) · أعلى \(s.maximum)",
                 inner.offsetBy(dx: 0, dy: 46).with(height: 11),
                 font: .systemFont(ofSize: 7), color: Ink.muted)

            text("ضمن النطاق \(Int((s.inRange * 100).rounded()))% من الوقت",
                 inner.offsetBy(dx: 0, dy: 56).with(height: 11),
                 font: .systemFont(ofSize: 7), color: Ink.muted)

            maxY = max(maxY, rect.maxY)
        }
        return maxY
    }

    private static func drawChart(_ report: HealthReport, top: CGFloat) -> CGFloat {
        let series = report.heartRateSeries.map { $0.value }
        guard series.count >= 2 else { return top }

        let height: CGFloat = 130
        let rect = CGRect(x: margin, y: top, width: contentWidth, height: height)

        text("مسار نبض القلب خلال الفترة",
             CGRect(x: margin, y: top, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.text)

        let plot = CGRect(x: rect.minX + 34, y: rect.minY + 22,
                          width: rect.width - 34, height: height - 36)

        let hrBand = HealthThresholds.default.heartRate
        let lo = min(series.min() ?? hrBand.normal.lowerBound, hrBand.normal.lowerBound - 5)
        let hi = max(series.max() ?? hrBand.criticalHigh, hrBand.criticalHigh + 5)
        let span = max(hi - lo, 1)

        func yFor(_ v: Double) -> CGFloat {
            plot.maxY - CGFloat((v - lo) / span) * plot.height
        }

        // النطاق الطبيعي
        Ink.success.withAlphaComponent(0.10).setFill()
        let bandRect = CGRect(x: plot.minX, y: yFor(hrBand.normal.upperBound),
                              width: plot.width,
                              height: yFor(hrBand.normal.lowerBound) - yFor(hrBand.normal.upperBound))
        UIBezierPath(rect: bandRect).fill()

        // خط الإنذار
        let alarm = UIBezierPath()
        alarm.move(to: CGPoint(x: plot.minX, y: yFor(hrBand.criticalHigh)))
        alarm.addLine(to: CGPoint(x: plot.maxX, y: yFor(hrBand.criticalHigh)))
        alarm.setLineDash([3, 3], count: 2, phase: 0)
        alarm.lineWidth = 0.8
        Ink.danger.setStroke()
        alarm.stroke()

        for value in [hrBand.criticalHigh, hrBand.normal.upperBound, hrBand.normal.lowerBound] {
            text("\(Int(value))",
                 CGRect(x: rect.minX, y: yFor(value) - 7, width: 28, height: 12),
                 font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                 color: value == hrBand.criticalHigh ? Ink.danger : Ink.muted, align: .left)
        }

        // المنحنى — تخفيف الكثافة ليبقى مقروءاً
        let step = max(1, series.count / 220)
        let points = stride(from: 0, to: series.count, by: step).map { i -> CGPoint in
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(max(series.count - 1, 1))
            return CGPoint(x: x, y: yFor(series[i]))
        }

        let line = UIBezierPath()
        for (i, p) in points.enumerated() {
            if i == 0 {
                line.move(to: p)
            } else {
                line.addLine(to: p)
            }
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        Ink.accent.setStroke()
        line.stroke()

        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 0.7)).fill()

        text(ReportFormat.dayMonth.string(from: report.to),
             CGRect(x: plot.minX, y: plot.maxY + 3, width: 120, height: 11),
             font: .systemFont(ofSize: 8), color: Ink.muted)
        text(ReportFormat.dayMonth.string(from: report.from),
             CGRect(x: plot.maxX - 120, y: plot.maxY + 3, width: 120, height: 11),
             font: .systemFont(ofSize: 8), color: Ink.muted, align: .left)

        return rect.maxY
    }

    private static func drawDailyTable(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.daily.isEmpty else { return top }

        var y = top
        text("ملخص يومي",
             CGRect(x: margin, y: y, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.text)
        y += 20

        let widths: [CGFloat] = [96, 62, 62, 82, 72, 78, 63]
        let headers = ["التاريخ", "القراءات", "التقييم", "متوسط النبض", "أعلى نبض", "أدنى أكسجين", "أعلى حرارة"]
        y = drawTableHeader(headers, widths: widths, top: y)

        let limit = min(report.daily.count, 12)
        for stat in report.daily.prefix(limit) {
            let cells = columns(widths: widths, top: y)
            let font = UIFont.systemFont(ofSize: 9.5)
            let mono = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

            text(ReportFormat.dayMonth.string(from: stat.day), cells[0], font: font, color: Ink.text)
            text("\(stat.count)", cells[1], font: mono, color: Ink.muted)
            text("\(stat.score)", cells[2], font: mono, color: color(stat.band))
            text(stat.avgHeartRate.map { "\(Int($0.rounded()))" } ?? "—", cells[3], font: mono, color: Ink.text)
            text(stat.maxHeartRate.map { "\(Int($0.rounded()))" } ?? "—", cells[4], font: mono, color: Ink.text)
            text(stat.minSpo2.map { "\(Int($0.rounded()))%" } ?? "—", cells[5], font: mono, color: Ink.text)
            text(stat.maxTemp.map { String(format: "%.1f", $0) } ?? "—", cells[6], font: mono, color: Ink.text)

            y += rowHeight
            rule(at: y)
        }

        if report.daily.count > limit {
            text("وأيام أخرى — التفصيل الكامل في سجل القراءات",
                 CGRect(x: margin, y: y + 4, width: contentWidth, height: 12),
                 font: .systemFont(ofSize: 9), color: Ink.muted)
            y += 18
        }
        return y
    }

    // MARK: صفحة التحليل والتوصيات

    /// أسفل المساحة المتاحة قبل التذييل.
    private static var contentBottom: CGFloat { page.height - margin - 34 }

    private static func drawAnalysisPage(_ report: HealthReport) {
        Ink.accent.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: page.width, height: 6)).fill()

        var y: CGFloat = margin + 6
        text("التحليل والتوصيات", CGRect(x: margin, y: y, width: contentWidth, height: 26),
             font: .systemFont(ofSize: 20, weight: .bold), color: Ink.text)
        y += 30

        y = drawFindings(report, top: y)
        y = drawZoneBars(report, top: y + 14)
        y = drawForecastBlock(report, top: y + 14)
        y = drawQuality(report, top: y + 14)
        _ = drawEpisodes(report, top: y + 14)
    }

    private static func sectionTitle(_ title: String, top: CGFloat) -> CGFloat {
        text(title, CGRect(x: margin, y: top, width: contentWidth, height: 16),
             font: .systemFont(ofSize: 12, weight: .semibold), color: Ink.text)
        return top + 20
    }

    private static func drawFindings(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.findings.isEmpty else { return top }
        var y = sectionTitle("أبرز النتائج", top: top)

        for finding in report.findings.prefix(7) {
            let font = UIFont.systemFont(ofSize: 10)
            let width = contentWidth - 14
            let height = min(textHeight(finding, width: width, font: font), 40)
            Ink.accent.setFill()
            UIBezierPath(ovalIn: CGRect(x: page.width - margin - 5, y: y + 5, width: 4, height: 4)).fill()
            text(finding, CGRect(x: margin, y: y, width: width, height: height),
                 font: font, color: Ink.text, lines: 3)
            y += height + 5
        }
        return y
    }

    /// توزيع وقت كل مؤشر على النطاقات: طبيعي / خارج النطاق / حرج.
    private static func drawZoneBars(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.summary.isEmpty else { return top }
        var y = sectionTitle("توزيع الوقت على النطاقات", top: top)

        let labelWidth: CGFloat = 80
        let captionWidth: CGFloat = 170
        let barWidth = contentWidth - labelWidth - captionWidth - 16

        for s in report.summary {
            text(s.kind.title, CGRect(x: page.width - margin - labelWidth, y: y, width: labelWidth, height: 14),
                 font: .systemFont(ofSize: 9.5, weight: .medium), color: Ink.text)

            // الشريط يُملأ من اليمين (اتجاه القراءة).
            var x = page.width - margin - labelWidth - 8
            let parts: [(Double, UIColor)] = [(s.inRange, Ink.success), (s.cautionShare, Ink.caution), (s.criticalShare, Ink.danger)]
            Ink.rule.setFill()
            UIBezierPath(roundedRect: CGRect(x: x - barWidth, y: y + 3, width: barWidth, height: 8), cornerRadius: 4).fill()
            for (share, color) in parts where share > 0 {
                let w = barWidth * CGFloat(share)
                color.setFill()
                UIBezierPath(rect: CGRect(x: x - w, y: y + 3, width: w, height: 8)).fill()
                x -= w
            }

            text("طبيعي \(pct(s.inRange)) · خارج \(pct(s.cautionShare)) · حرج \(pct(s.criticalShare))",
                 CGRect(x: margin, y: y, width: captionWidth, height: 14),
                 font: .systemFont(ofSize: 8.5), color: Ink.muted)
            y += 18
        }
        return y
    }

    private static func drawForecastBlock(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard let f = report.forecast, !f.insufficientCoverage else { return top }
        var y = sectionTitle("تنبؤ الساعة القادمة · الثقة \(pct(f.confidence))\(f.isPreliminary ? " · أولي" : "")", top: top)

        if let projected = f.projectedScore {
            text("الدرجة المتوقعة بعد ساعة: \(projected) من ١٠٠ (الحالية للفترة \(report.assessment.score))",
                 CGRect(x: margin, y: y, width: contentWidth, height: 14),
                 font: .systemFont(ofSize: 10), color: Ink.text)
            y += 16
        }

        let risks = f.risks.filter { $0.level != .low }.prefix(3)
        if risks.isEmpty {
            text("لا يُتوقع تجاوز أي حد حرج خلال الساعة القادمة.",
                 CGRect(x: margin, y: y, width: contentWidth, height: 14),
                 font: .systemFont(ofSize: 10), color: Ink.success)
            return y + 16
        }
        for r in risks {
            let color = r.level == .high ? Ink.danger : Ink.caution
            text("\(r.name) — \(pct(r.probability))",
                 CGRect(x: margin, y: y, width: contentWidth, height: 14),
                 font: .systemFont(ofSize: 10, weight: .semibold), color: color)
            y += 14
            let h = min(textHeight(r.why, width: contentWidth, font: .systemFont(ofSize: 9)), 26)
            text(r.why, CGRect(x: margin, y: y, width: contentWidth, height: h),
                 font: .systemFont(ofSize: 9), color: Ink.muted, lines: 2)
            y += h + 4
        }
        return y
    }

    private static func drawQuality(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard let q = report.quality, q.received > 0 else { return top }
        var y = sectionTitle("جودة البيانات", top: top)
        let line = "وصلت \(q.received) قراءة من \(q.expected) متوقعة (\(pct(q.coverage))) · انقطاعات أطول من ٥ دقائق: \(q.gapCount) · أطول انقطاع: \(q.longestGapMinutes) دقيقة"
        text(line, CGRect(x: margin, y: y, width: contentWidth, height: 26),
             font: .systemFont(ofSize: 9.5), color: Ink.text, lines: 2)
        y += 28
        text("قيم الضغط قد تكون تقديرية محسوبة من النبض وليست قياساً مباشراً.",
             CGRect(x: margin, y: y, width: contentWidth, height: 12),
             font: .systemFont(ofSize: 8.5), color: Ink.muted)
        return y + 14
    }

    private static func drawEpisodes(_ report: HealthReport, top: CGFloat) -> CGFloat {
        var y = sectionTitle("نوبات التجاوز الحرج", top: top)
        guard !report.episodes.isEmpty else {
            text("لا توجد نوبات تجاوز حرج متواصلة خلال الفترة.",
                 CGRect(x: margin, y: y, width: contentWidth, height: 14),
                 font: .systemFont(ofSize: 10), color: Ink.success)
            return y + 16
        }

        let widths: [CGFloat] = [120, 90, 70, 80, 70, 85]
        y = drawTableHeader(["البداية", "المؤشر", "الاتجاه", "أسوأ قيمة", "المدة", "القراءات"], widths: widths, top: y)

        let room = Int((contentBottom - y - 16) / rowHeight)
        let shown = max(0, min(report.episodes.count, room))
        let dateFormat: DateFormatter = report.period == .eightHours || report.period == .today
            ? ReportFormat.time : ReportFormat.dayTime
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

        for e in report.episodes.prefix(shown) {
            let cells = columns(widths: widths, top: y)
            text(dateFormat.string(from: e.start), cells[0], font: mono, color: Ink.text)
            text(e.kind.title, cells[1], font: .systemFont(ofSize: 9.5), color: Ink.text)
            text(e.isHigh ? "ارتفاع" : "انخفاض", cells[2], font: .systemFont(ofSize: 9.5, weight: .medium), color: Ink.danger)
            text("\(HealthEngine.format(e.peak, e.kind)) \(e.kind.unit)", cells[3], font: mono, color: Ink.text)
            text("\(e.durationMinutes) د", cells[4], font: mono, color: Ink.text)
            text("\(e.readings)", cells[5], font: mono, color: Ink.muted)
            y += rowHeight
            rule(at: y)
        }
        if report.episodes.count > shown {
            text("و\(report.episodes.count - shown) نوبة أخرى — راجع سجل القراءات",
                 CGRect(x: margin, y: y + 4, width: contentWidth, height: 12),
                 font: .systemFont(ofSize: 9), color: Ink.muted)
            y += 16
        }
        return y
    }

    private static func pct(_ v: Double) -> String {
        "\(Int((min(max(v, 0), 1) * 100).rounded()))٪"
    }

    private static func textHeight(_ string: String, width: CGFloat, font: UIFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineSpacing = 2
        let rect = (string as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(rect.height) + 2
    }

    // MARK: صفحات سجل القراءات

    private static func drawReadingsPage(_ report: HealthReport, pageIndex: Int) {
        var y: CGFloat = margin
        let start = pageIndex * rowsPerPage
        let end = min(start + rowsPerPage, report.readings.count)

        text("سجل القراءات", CGRect(x: margin, y: y, width: contentWidth, height: 20),
             font: .systemFont(ofSize: 15, weight: .semibold), color: Ink.text)
        y += 20

        var caption = "القراءات \(start + 1)–\(end) من \(report.readings.count) · الأحدث أولاً"
        if report.isTruncated {
            caption += " · أحدث \(report.readings.count) قراءة من أصل \(report.readingsTotal)"
        }
        text(caption, CGRect(x: margin, y: y, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 10), color: Ink.muted)
        y += 22

        let widths: [CGFloat] = [104, 72, 78, 92, 82, 87]
        y = drawTableHeader(["الوقت", "النبض", "الأكسجين", "الضغط", "الحرارة", "الحالة"],
                            widths: widths, top: y)

        for reading in report.readings[start..<end] {
            let cells = columns(widths: widths, top: y)
            let mono = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

            text(ReportFormat.time.string(from: reading.date), cells[0], font: mono, color: Ink.text)
            text(reading.heartRate, cells[1], font: mono, color: Ink.text)
            text(reading.spo2, cells[2], font: mono, color: Ink.text)
            text(reading.pressure, cells[3], font: mono, color: Ink.text)
            text(reading.temperature, cells[4], font: mono, color: Ink.text)
            text(reading.band.title, cells[5],
                 font: .systemFont(ofSize: 9.5, weight: .medium), color: color(reading.band))

            y += rowHeight
            rule(at: y)
        }
    }

    // MARK: التذييل

    private static func drawFooter(page pageNumber: Int, of total: Int, report: HealthReport) {
        let y = page.height - margin - 26
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.7)).fill()

        text("تقرير إرشادي للسلامة، مبني على قراءات السوار. ليس تشخيصاً طبياً.",
             CGRect(x: margin, y: y + 7, width: contentWidth - 90, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted)

        text("صفحة \(pageNumber) من \(total)",
             CGRect(x: page.width - margin - 90, y: y + 7, width: 90, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted, align: .left)

        text("أُنشئ في \(ReportFormat.full.string(from: report.generatedAt))",
             CGRect(x: margin, y: y + 19, width: contentWidth, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted)
    }

    // MARK: أدوات الرسم

    private static func drawTableHeader(_ titles: [String], widths: [CGFloat], top: CGFloat) -> CGFloat {
        let cells = columns(widths: widths, top: top)
        for (i, t) in titles.enumerated() where i < cells.count {
            text(t, cells[i], font: .systemFont(ofSize: 9, weight: .semibold), color: Ink.muted)
        }

        let y = top + 15
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.7)).fill()

        return y + 4
    }

    /// أعمدة من اليمين إلى اليسار.
    private static func columns(widths: [CGFloat], top: CGFloat) -> [CGRect] {
        var x = page.width - margin
        return widths.map { w in
            x -= w
            return CGRect(x: x, y: top, width: w, height: rowHeight - 3)
        }
    }

    private static func rule(at y: CGFloat) {
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y - 3, width: contentWidth, height: 0.5)).fill()
    }

    private static func card(_ rect: CGRect) {
        Ink.cardFill.setFill()
        Ink.rule.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        path.fill()
        path.lineWidth = 0.7
        path.stroke()
    }

    private static func text(_ string: String, _ rect: CGRect,
                             font: UIFont, color: UIColor,
                             align: NSTextAlignment = .right, lines: Int = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        paragraph.lineSpacing = lines == 1 ? 0 : 2

        (string as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

private extension CGRect {
    func with(height newHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: newHeight)
    }
}


//
//  ShareHealthReportView.swift
//  SecurityPass
//
//  شاشة مشاركة الوضع الصحي: اختيار الفترة، معاينة، ثم إنشاء PDF ومشاركته.
//  تحل محل ورقة المشاركة النصية الحالية.
//

import SwiftUI
import UIKit

public struct ShareHealthReportView: View {
    public let samples: [VitalSample]
    public let employeeID: String

    @State private var period: ReportPeriod = .today
    @State private var report: HealthReport?
    @State private var isPreparing = true
    @State private var isBuilding = false
    @State private var payload: SharePayload?
    @State private var failure: String?
    @Environment(\.presentationMode) private var presentation

    public init(samples: [VitalSample], employeeID: String) {
        self.samples = samples
        self.employeeID = employeeID
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    periodPicker

                    Group {
                        if isPreparing {
                            placeholder("جارٍ تجهيز الملخص…")
                                .transition(.opacity)
                        } else if let report = report, !report.isEmpty {
                            VStack(alignment: .leading, spacing: 18) {
                                summaryCard(report)
                                findingsCard(report)
                                contentsCard(report)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            placeholder("لا توجد قراءات في هذه الفترة.")
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: isPreparing)

                    shareButton

                    if let failure = failure {
                        Text(failure)
                            .font(.system(size: 12))
                            .foregroundColor(SP.Color.dangerText)
                    }

                    Text("يُنشأ الملف على جهازك ويُشارك عبر قائمة المشاركة.")
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .foregroundColor(SP.Color.muted)
                }
                .padding(20)
            }
            .background(SP.Color.ground.ignoresSafeArea())
            .navigationBarTitle("مشاركة الوضع الصحي", displayMode: .inline)
            .navigationBarItems(trailing: Button("إغلاق") {
                presentation.wrappedValue.dismiss()
            })
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: rebuild)
        .onChange(of: period) { _ in rebuild() }
        .sheet(item: $payload) { item in
            ActivityView(url: item.url)
        }
    }

    // MARK: الأجزاء

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("الفترة")
                .font(.system(size: 12))
                .foregroundColor(SP.Color.muted)

            Picker("الفترة", selection: $period) {
                ForEach(ReportPeriod.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(SP.Color.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(cardShape)
    }

    private func summaryCard(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(report.assessment.score)")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundColor(SP.Color.text)
                Text("من ١٠٠ · \(report.assessment.band.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SP.Color.accent)
                Spacer(minLength: 0)
            }
            Text(report.assessment.headline)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundColor(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                stat("القراءات", "\(report.readingsTotal)")
                stat("نوبات حرجة", "\(report.episodes.count)")
                if let q = report.quality {
                    stat("اكتمال البيانات", "\(Int((q.coverage * 100).rounded()))٪")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(SP.Color.text)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(SP.Color.muted)
        }
    }

    private func findingsCard(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("أبرز النتائج")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SP.Color.text)
            ForEach(Array(report.findings.prefix(4).enumerated()), id: \.offset) { _, finding in
                bullet(finding)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func contentsCard(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("محتويات التقرير")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SP.Color.text)

            bullet("التقييم العام للفترة كاملة وتفسيره")
            bullet("ملخص كل مؤشر: الأدنى والمتوسط والأعلى ونسبة الوقت ضمن النطاق")
            bullet("مسار نبض القلب خلال الفترة")
            bullet("ملخص يومي لـ \(report.daily.count) يوم")
            bullet("صفحة تحليل: أبرز النتائج والتوصيات، توزيع الوقت على النطاقات، ونوبات التجاوز الحرج")
            if report.forecast != nil {
                bullet("تنبؤ الساعة القادمة مع درجة الثقة")
            }
            bullet("جودة البيانات والانقطاعات")
            bullet(report.isTruncated
                   ? "سجل بأحدث \(report.readings.count) قراءة من أصل \(report.readingsTotal)"
                   : "سجل كامل بـ \(report.readings.count) قراءة")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(SP.Color.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundColor(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var shareButton: some View {
        let ready = !(report?.isEmpty ?? true) && !isPreparing

        return Button(action: build) {
            HStack(spacing: 8) {
                if isBuilding {
                    ProgressView().tint(SP.Color.ground)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isBuilding ? "جارٍ إنشاء الملف…" : "إنشاء PDF ومشاركته")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundColor(SP.Color.ground)
            .background(SP.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isBuilding || !ready)
        .opacity(ready ? 1 : 0.4)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(SP.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SP.Color.raised, lineWidth: 1)
            )
    }

    // MARK: البناء

    /// تقرير شهر قد يحمل عشرات الآلاف من القراءات — التجميع والرسم خارج الخيط الرئيسي.
    private func rebuild() {
        isPreparing = true
        failure = nil
        let snapshot = samples
        let id = employeeID
        let selected = period

        DispatchQueue.global(qos: .userInitiated).async {
            let built = HealthReportBuilder.build(from: snapshot, employeeID: id, period: selected)
            DispatchQueue.main.async {
                guard selected == period else { return }   // تجاهل نتيجة فترة قديمة
                withAnimation(.easeInOut(duration: 0.3)) {
                    report = built
                    isPreparing = false
                }
            }
        }
    }

    private func build() {
        guard let snapshot = report else { return }

        isBuilding = true
        failure = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try HealthReportPDF.render(snapshot)
                DispatchQueue.main.async {
                    isBuilding = false
                    payload = SharePayload(url: url)
                }
            } catch {
                DispatchQueue.main.async {
                    isBuilding = false
                    failure = "تعذّر إنشاء الملف: " + error.localizedDescription
                }
            }
        }
    }
}

private struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - قائمة المشاركة

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // التطبيق يدعم iPad (UIDeviceFamily = 1,2) — بلا مصدر للـ popover ينهار هناك.
        guard let popover = controller.popoverPresentationController, popover.sourceView == nil else { return }
        popover.sourceView = controller.view
        popover.permittedArrowDirections = []
        popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                    y: controller.view.bounds.midY,
                                    width: 1, height: 1)
    }
}


//
//  HealthLiveActivityManager.swift
//  SecurityPass
//
//  يدير الإشعارات التنبيهية المحلية (Local Notifications) والإشعار العريض المستمر (Live Activity)
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
import UserNotifications

// HealthActivityAttributes في ملف مستقل مشترك مع امتداد شاشة القفل.

// MARK: - المدير الرئيسي للإشعارات المستمرة

/// النشاط المباشر على شاشة القفل: النبض والأكسجين والحالة، ومعها البطاقة الطبية.
public final class HealthLiveActivityManager {
    public static let shared = HealthLiveActivityManager()
    private init() {}

    private var lastHeartRate = 0
    private var lastSpo2 = 0
    private var lastMessage = "قيد المراقبة المستمرة"
    private var lastCritical = false

    public func start(employeeID: String, heartRate: Int, spo2: Int) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            // إنهاء النشاطات السابقة فقط — التقاطها قبل الطلب حتى لا يُنهى الجديد معها.
            let previous = Activity<HealthActivityAttributes>.activities
            Task {
                for activity in previous {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }

            lastHeartRate = heartRate
            lastSpo2 = spo2
            do {
                _ = try Activity.request(attributes: HealthActivityAttributes(employeeID: employeeID),
                                         contentState: state(), pushType: nil)
                print("[LiveActivity] Started successfully")
            } catch {
                print("[LiveActivity] Error starting: \(error.localizedDescription)")
            }
        }
        #endif
    }

    public func update(heartRate: Int, spo2: Int, isCritical: Bool, message: String) {
        lastHeartRate = heartRate
        lastSpo2 = spo2
        lastCritical = isCritical
        lastMessage = message
        push()
    }

    /// إعادة نشر البطاقة الطبية بعد تعديلها من شاشة «الهوية».
    public func refreshMedicalCard() {
        push()
    }

    private func push() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            let newState = state()
            Task {
                for activity in Activity<HealthActivityAttributes>.activities {
                    await activity.update(using: newState)
                }
            }
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func state() -> HealthActivityAttributes.ContentState {
        HealthActivityAttributes.ContentState(
            heartRate: lastHeartRate,
            spo2: lastSpo2,
            statusMessage: lastMessage,
            isCritical: lastCritical,
            bloodType: MedicalProfile.bloodType ?? "",
            conditions: VoiceAlertManager.shared.conditionsText ?? "",
            allergies: MedicalProfile.allergies ?? "",
            emergencyPhone: [MedicalProfile.emergencyName, MedicalProfile.emergencyPhone]
                .compactMap { $0 }.joined(separator: " ")
        )
    }
    #endif

    public func endAll() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            Task {
                for activity in Activity<HealthActivityAttributes>.activities {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }
}




import Charts

public struct HealthHistoryView: View {
    @StateObject private var syncManager = GoogleSheetSyncManager.shared
    @AppStorage("daily_steps_history") private var dailyStepsData: Data = Data()
    
    struct DailyStat: Identifiable {
        let id = UUID()
        let dateString: String
        let date: Date
        let avgHr: Int
        let maxHr: Int
        let minHr: Int
        let avgSpo2: Int
        let maxTemp: Double
        let steps: Int
        let calories: Int
        let band: HealthBand
    }
    
    public init() {}
    
    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var dailyStats: [DailyStat] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: syncManager.history) { calendar.startOfDay(for: $0.timestamp) }

        var stepDict: [String: Int] = [:]
        if let decoded = try? JSONDecoder().decode([String: Int].self, from: dailyStepsData) {
            stepDict = decoded
        }

        return grouped.map { day, records -> DailyStat in
            let hrs = records.compactMap { HealthEngine.value($0, .heartRate) }
            let spo2s = records.compactMap { HealthEngine.value($0, .spo2) }
            let dateStr = Self.dayKey.string(from: day)
            let steps = stepDict[dateStr] ?? 0

            // نفس خوارزمية التقارير: متوسط اليوم مع وزن لأسوأ ١٠٪ من الوقت،
            // وأي نوبة تجاوز حرج متواصلة تسقف اليوم في نطاق الخطر.
            let assessment = HealthEngine.assessPeriod(records, from: day,
                                                       to: day.addingTimeInterval(24 * 3600 - 1))

            return DailyStat(
                dateString: dateStr,
                date: day,
                avgHr: hrs.isEmpty ? 0 : Int((hrs.reduce(0, +) / Double(hrs.count)).rounded()),
                maxHr: Int(hrs.max() ?? 0),
                minHr: Int(hrs.min() ?? 0),
                avgSpo2: spo2s.isEmpty ? 0 : Int((spo2s.reduce(0, +) / Double(spo2s.count)).rounded()),
                maxTemp: records.compactMap { HealthEngine.value($0, .bodyTemp) }.max() ?? 0,
                steps: steps,
                calories: Int(Double(steps) * 0.045),
                band: assessment.band
            )
        }
        .sorted { $0.date > $1.date }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if dailyStats.isEmpty {
                    Text("لا توجد بيانات سابقة بعد")
                        .foregroundColor(SP.Color.muted)
                        .padding(.top, 50)
                } else {
                    ForEach(dailyStats) { stat in
                        DailyStatRow(stat: stat)
                    }
                }
            }
            .padding()
        }
        .background(SP.Color.ground.edgesIgnoringSafeArea(.all))
        .navigationTitle("السجل الصحي")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DailyStatRow: View {
    let stat: HealthHistoryView.DailyStat
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(stat.dateString)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(SP.Color.text)
                Spacer()
                StatusPill(text: stat.band.title, color: stat.band.color)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                HistoryCard(title: "متوسط النبض", value: dash(stat.avgHr), unit: "bpm", icon: "heart.fill", color: SP.Color.dangerText)
                HistoryCard(title: "أعلى نبض", value: dash(stat.maxHr), unit: "bpm", icon: "arrow.up.heart", color: SP.Color.dangerText)
                HistoryCard(title: "أقل نبض", value: dash(stat.minHr), unit: "bpm", icon: "arrow.down.heart", color: SP.Color.ok)
                HistoryCard(title: "متوسط الأكسجين", value: dash(stat.avgSpo2), unit: "%", icon: "drop.fill", color: SP.Color.measure)
                HistoryCard(title: "أعلى حرارة", value: stat.maxTemp > 0 ? String(format: "%.1f", stat.maxTemp) : "—", unit: "°C", icon: "thermometer", color: SP.Color.accent)
                HistoryCard(title: "حرق السعرات", value: "\(stat.calories)", unit: "سعرة", icon: "flame.fill", color: .orange)
            }
        }
        .padding()
        .background(SP.Color.card)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func dash(_ v: Int) -> String { v > 0 ? "\(v)" : "—" }
}

struct HistoryCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(SP.Color.muted)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SP.Color.text)
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(SP.Color.muted)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
