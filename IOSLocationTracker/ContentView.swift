import UserNotifications
//
//  ContentView.swift
//  SecurityPass â€” Ø§Ù„ÙˆØ§Ø¬Ù‡Ø© Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø©
//
//  ÙŠØ³ØªØ¨Ø¯Ù„ Ù‡Ø°Ø§ Ø§Ù„Ù…Ù„Ù ContentView Ø§Ù„Ù‚Ø¯ÙŠÙ… Ø¨Ø§Ù„ÙƒØ§Ù…Ù„. Ù„Ù… ÙŠÙÙ…Ø³Ù‘ Ø£ÙŠ Ù…Ø¯ÙŠØ±:
//  IdoSmartManager Ùˆ LocationManager Ùˆ GoogleSheetSyncManager Ùˆ
//  BloodPressureAlgorithm ØªÙØ³ØªØ¯Ø¹Ù‰ Ø¨Ù†ÙØ³ Ø£Ø³Ù…Ø§Ø¦Ù‡Ø§ ÙˆØªÙˆØ§Ù‚ÙŠØ¹Ù‡Ø§ Ø§Ù„Ø­Ø§Ù„ÙŠØ©.
//

import SwiftUI
import MapKit

struct ContentView: View {

    @StateObject private var ido = IdoSmartManager.shared
    @StateObject private var location = LocationManager.shared

    /// Ù†ÙØ³ Ù…ÙØªØ§Ø­ Ø§Ù„ØªØ®Ø²ÙŠÙ† Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… ÙÙŠ Ø§Ù„Ø¨Ù†Ø§Ø¡ Ø§Ù„Ø­Ø§Ù„ÙŠ.
    @AppStorage("WATCH_APP_DEFAULT") private var employeeId: String = "WATCH_001"

    @State private var tab: Tab = .status

    enum Tab: Hashable { case status, history, devices, sos, identity }

    var body: some View {
        ZStack(alignment: .bottom) {
            SP.Color.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .status:
                    StatusScreen(ido: ido, location: location, employeeId: employeeId) {
                        tab = .devices
                    }
                case .history:  HistoryScreen(samples: GoogleSheetSyncManager.shared.history, employeeID: employeeId)
                case .devices:  DevicesScreen(ido: ido)
                case .sos:      SOSScreen(ido: ido, location: location, employeeId: employeeId)
                case .identity: IdentityScreen(ido: ido, location: location, employeeId: $employeeId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 78)

            SPTabBar(selection: $tab)
        }
        .preferredColorScheme(.dark)
        .spArabic()
        .onAppear { location.requestPermissions() }
    }
}

// MARK: - Ø´Ø±ÙŠØ· Ø§Ù„ØªØ¨ÙˆÙŠØ¨

struct SPTabBar: View {
    @Binding var selection: ContentView.Tab

    var body: some View {
                HStack(spacing: 4) {
            item(.status,   "الحالة",  "shield",            SP.Color.accent)
            item(.history,  "السجل",   "clock",             SP.Color.ok)
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
        // SOS ÙŠØ¨Ù‚Ù‰ Ø£Ø­Ù…Ø± Ø­ØªÙ‰ ÙˆÙ‡Ùˆ ØºÙŠØ± Ù†Ø´Ø· â€” Ø¥Ù†Ù‡ ØªØ­Ø°ÙŠØ± Ù„Ø§ Ø¹Ù†ØµØ± ØªÙ†Ù‚Ù‘Ù„ Ø¹Ø§Ø¯ÙŠ.
        let tint: Color = isActive ? activeColor
                        : (tab == .sos ? SP.Color.dangerText : SP.Color.muted)

        return Button { selection = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(SP.Font.ui(10.5, isActive || tab == .sos ? .semibold : .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: SP.Metric.minTarget + 2)
            .background(isActive ? SP.Color.raised : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Ø´Ø§Ø´Ø© Ø§Ù„Ø­Ø§Ù„Ø© (Ù…ØªØµÙ„ / Ù…Ù†Ù‚Ø·Ø¹)

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
                    SPMetricCard(title: "نسبة الأكسجين", value: connected ? text(ido.currentSpo2) : "â€”",
                                 unit: "%", icon: "drop", iconColor: SP.Color.measure,
                                 isStale: !connected)
                    SPMetricCard(title: "ضغط الدم", value: connected ? (ido.currentBloodPressure.isEmpty ? "â€”" : ido.currentBloodPressure) : "â€”",
                                 icon: "gauge.medium", iconColor: SP.Color.accent,
                                 isStale: !connected)
                    SPMetricCard(title: "حرارة الجسم", value: connected ? temperatureText : "â€”",
                                 unit: "°م", icon: "thermometer.medium",
                                 iconColor: SP.Color.dangerText, isStale: !connected)
                    SPMetricCard(title: "الخطوات", value: connected ? text(ido.currentSteps) : "â€”",
                                 icon: "figure.walk", iconColor: SP.Color.ok,
                                 isStale: !connected)
                    SPMetricCard(title: "بطارية السوار", value: connected ? text(ido.currentBattery) : "â€”",
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
                    SPStatusPill(text: fullyActive ? "متصل ونشط" : (connected ? "Ù…ØªØµÙ„ (Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªÙ†Ø´ÙŠØ·)" : "ØºÙŠØ± Ù…ØªØµÙ„"),
                                 color: fullyActive ? SP.Color.ok : (connected ? SP.Color.measure : SP.Color.dangerText))
                )
            )
            .background(SP.Color.ground)
        }
    }

    // MARK: Ø£Ø¬Ø²Ø§Ø¡

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
                Text(connected ? "نبض القلب المباشر" : "Ù†Ø¨Ø¶ Ø§Ù„Ù‚Ù„Ø¨ â€” Ø¢Ø®Ø± Ù‚Ø±Ø§Ø¡Ø©")
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
                    Text(syncManager.isAutoSyncActive ? "إرسال تلقائي (كل دقيقة)" : "Ø¢Ø®Ø± Ø¥Ø±Ø³Ø§Ù„ ÙˆØµÙ„")
                        .font(SP.Font.ui(11.5))
                        .foregroundStyle(SP.Color.muted)
                }
                Text(syncManager.lastSyncTime.map(Self.timeFormatter.string(from:)) ?? "â€”")
                    .font(SP.Font.numeric(13))
                    .foregroundStyle(SP.Color.text)
            }
            Spacer(minLength: 0)
            Button(syncManager.isSyncing ? "جاري الإرسال..." : "Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø¢Ù†") {
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

    // MARK: Ù…Ù†Ø·Ù‚ Ø§Ù„Ø¹Ø±Ø¶ ÙÙ‚Ø· â€” Ø§Ù„Ø¥Ø±Ø³Ø§Ù„ ÙŠÙ…Ø± Ø¨Ù†ÙØ³ Ø§Ù„Ù…Ø¯ÙŠØ± Ø§Ù„Ø­Ø§Ù„ÙŠ

    private func send() {
        syncManager.performAutoSync(force: true)
    }

    private func text(_ value: Int) -> String { value > 0 ? "\(value)" : "â€”" }

    private var temperatureText: String {
        ido.currentTemperature > 0 ? String(format: "%.1f", ido.currentTemperature) : "â€”"
    }

    private var locationText: String {
        location.latitude == 0 && location.longitude == 0 ? "â€”" : "مُحدّث"
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
//  HealthEngine.swift
//  SecurityPass
//
//  محرك التقييم الصحي والتنبؤ — يعمل بالكامل على الجهاز.
//  لا يضيف أي حقل، ولا يغيّر قاعدة البيانات أو بروتوكول الإرسال.
//  كل ما يحتاجه موجود أصلاً في سجلات المزامنة المخزّنة محلياً.
//

import Foundation

// MARK: - مصدر البيانات

/// البروتوكول الوحيد الذي يربط المحرك ببيانات التطبيق الحالية.
/// اجعل `SyncHistoryRecord` يطابقه عبر الامتداد في آخر الملف.
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

    public var heartRate = Band(normal: 60...100, criticalLow: 40, criticalHigh: 120)
    public var spo2      = Band(normal: 95...100, criticalLow: 90, criticalHigh: 100)
    public var bodyTemp  = Band(normal: 36.1...37.2, criticalLow: 35.0, criticalHigh: 38.0)
    public var systolic  = Band(normal: 90...129, criticalLow: 85, criticalHigh: 140)
    /// الانحراف المعياري للنبض داخل النافذة.
    public var stability = Band(normal: 0...8, criticalLow: 0, criticalHigh: 15)

    public var weightHeartRate: Double = 30
    public var weightSpo2: Double      = 25
    public var weightBodyTemp: Double  = 20
    public var weightPressure: Double  = 15
    public var weightStability: Double = 10

    /// نافذة حساب الاتجاه والتنبؤ.
    public var trendWindow: TimeInterval = 40 * 60
    /// أفق الإسقاط.
    public var forecastHorizon: TimeInterval = 60 * 60
    /// نافذة العرض في الشاشة.
    public var displayWindow: TimeInterval = 6 * 3600
    /// الفاصل المتوقع بين قراءتين (الإرسال التلقائي كل دقيقة).
    public var expectedInterval: TimeInterval = 60
    /// تحت هذه التغطية لا يُعرض التنبؤ إطلاقاً.
    public var minimumCoverageForForecast: Double = 0.40
    /// مدة التجاوز المتواصل قبل اعتبار الحالة إنذاراً.
    public var sustainedBreach: TimeInterval = 5 * 60

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

public enum HealthBand: String {
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

    public var title: String {
        switch self {
        case .heartRate: return "نبض القلب"
        case .spo2:      return "الأكسجين"
        case .bodyTemp:  return "حرارة الجسم"
        case .pressure:  return "ضغط الدم"
        case .stability: return "الاستقرار"
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
    public let score: Double      // ٠…١
    public let weight: Double
    public let trend: Trend?
}

public struct Trend {
    /// وحدة المؤشر لكل دقيقة.
    public let slopePerMinute: Double
    /// ثبات الاتجاه ٠…١.
    public let rSquared: Double
    /// القيمة المتوقعة بعد أفق الإسقاط.
    public let projected: Double
    /// الدقائق المتبقية لبلوغ عتبة الإنذار، إن كان الاتجاه يقود إليها.
    public let minutesToThreshold: Double?
}

public struct HealthAssessment {
    public let score: Int
    public let band: HealthBand
    public let headline: String
    public let indicators: [IndicatorReading]
    /// تغطية القراءات ٠…١ — هي «دقة التقييم» المعروضة.
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
    }

    public let id: String
    public let name: String
    public let probability: Double   // ٠…١
    public let level: Level
    public let why: String
    public let tags: [String]
}

public struct ForecastResult {
    public let risks: [RiskForecast]
    public let projectedScore: Int?
    public let coverage: Double
    /// صحيح عندما تكون التغطية أقل من الحد الأدنى — لا يُعرض تنبؤ.
    public let insufficientCoverage: Bool
}

// MARK: - المحرك

public enum HealthEngine {
    // MARK: التقييم العام

    public static func assess(
        _ samples: [VitalSample],
        now: Date = Date(),
        config: HealthThresholds = .default
    ) -> HealthAssessment {
        let window = samples
            .filter { now.timeIntervalSince($0.sampleDate) <= config.displayWindow }
            .sorted { $0.sampleDate < $1.sampleDate }

        let coverage = self.coverage(window, span: config.displayWindow, config: config)

        guard let latest = window.last else {
            return HealthAssessment(
                score: 0, band: .danger,
                headline: "لا توجد قراءات في آخر ٦ ساعات.",
                indicators: [], coverage: 0, sampleCount: 0, updatedAt: nil
            )
        }

        let trendWindow = window.filter { now.timeIntervalSince($0.sampleDate) <= config.trendWindow }

        var indicators: [IndicatorReading] = []

        if let hr = latest.vHeartRate.map(Double.init) {
            indicators.append(reading(
                kind: .heartRate, value: hr, display: "\(Int(hr))",
                band: config.heartRate, weight: config.weightHeartRate,
                trend: trend(of: trendWindow, config: config,
                             threshold: config.heartRate.criticalHigh) { $0.vHeartRate.map(Double.init) }
            ))
        }

        if let spo2 = latest.vSpo2.map(Double.init) {
            indicators.append(reading(
                kind: .spo2, value: spo2, display: "\(Int(spo2))",
                band: config.spo2, weight: config.weightSpo2,
                trend: trend(of: trendWindow, config: config,
                             threshold: config.spo2.criticalLow) { $0.vSpo2.map(Double.init) }
            ))
        }

        if let temp = latest.bodyTemp {
            indicators.append(reading(
                kind: .bodyTemp, value: temp, display: String(format: "%.1f", temp),
                band: config.bodyTemp, weight: config.weightBodyTemp,
                trend: trend(of: trendWindow, config: config,
                             threshold: config.bodyTemp.criticalHigh) { $0.bodyTemp }
            ))
        }

        if let sys = latest.systolic.map(Double.init) {
            let dia = latest.diastolic.map { "/\($0)" } ?? ""
            indicators.append(reading(
                kind: .pressure, value: sys, display: "\(Int(sys))\(dia)",
                band: config.systolic, weight: config.weightPressure,
                trend: trend(of: trendWindow, config: config,
                             threshold: config.systolic.criticalHigh) { $0.systolic.map(Double.init) }
            ))
        }

        let hrSeries = trendWindow.compactMap { $0.vHeartRate.map(Double.init) }
        if hrSeries.count >= 3 {
            let sd = standardDeviation(hrSeries)
            indicators.append(reading(
                kind: .stability, value: sd, display: "±\(Int(sd.rounded()))",
                band: config.stability, weight: config.weightStability, trend: nil
            ))
        }

        // الدرجة = متوسط موزون للمؤشرات المتاحة. التغطية لا تخفض التقييم، بل تخفض الثقة.
        let totalWeight = indicators.reduce(0) { $0 + $1.weight }
        let weighted = indicators.reduce(0) { $0 + $1.score * $1.weight }
        let score = totalWeight > 0 ? Int((weighted / totalWeight * 100).rounded()) : 0
        let band = HealthBand.from(score: score)

        return HealthAssessment(
            score: score,
            band: band,
            headline: headline(for: band, indicators: indicators),
            indicators: indicators,
            coverage: coverage,
            sampleCount: window.count,
            updatedAt: latest.sampleDate
        )
    }

    // MARK: التنبؤ

    public static func forecast(
        _ samples: [VitalSample],
        now: Date = Date(),
        config: HealthThresholds = .default
    ) -> ForecastResult {
        let window = samples
            .filter { now.timeIntervalSince($0.sampleDate) <= config.trendWindow }
            .sorted { $0.sampleDate < $1.sampleDate }

        let coverage = self.coverage(window, span: config.trendWindow, config: config)
        guard coverage >= config.minimumCoverageForForecast, let latest = window.last else {
            return ForecastResult(risks: [], projectedScore: nil,
                                  coverage: coverage, insufficientCoverage: true)
        }

        let hrTrend = trend(of: window, config: config,
                            threshold: config.heartRate.criticalHigh) { $0.vHeartRate.map(Double.init) }
        let tempTrend = trend(of: window, config: config,
                              threshold: config.bodyTemp.criticalHigh) { $0.bodyTemp }
        let spo2Trend = trend(of: window, config: config,
                              threshold: config.spo2.criticalLow) { $0.vSpo2.map(Double.init) }
        let sysTrend = trend(of: window, config: config,
                             threshold: config.systolic.criticalHigh) { $0.systolic.map(Double.init) }

        let stationary = isStationary(window)
        var risks: [RiskForecast] = []

        // نمط ١ — إجهاد قلبي حراري: نبض صاعد + حرارة صاعدة + ثبات الموقع.
        if let hr = hrTrend, let current = latest.vHeartRate.map(Double.init) {
            var p = probability(current: current, threshold: config.heartRate.criticalHigh,
                                normalEdge: config.heartRate.normal.upperBound,
                                trend: hr, coverage: coverage)
            if (tempTrend?.slopePerMinute ?? 0) > 0 { p *= 1.15 }
            if stationary { p *= 1.10 }
            p = min(p, 1)

            if p > 0.02 {
                var tags = ["نبض القلب"]
                if (tempTrend?.slopePerMinute ?? 0) > 0 { tags.append("حرارة الجسم") }
                if stationary { tags.append("ثبات الموقع") }

                risks.append(RiskForecast(
                    id: "cardiac_heat",
                    name: "إجهاد قلبي حراري",
                    probability: p,
                    level: level(p),
                    why: reason(indicator: "النبض", unit: "نبضة/دقيقة", trend: hr,
                                threshold: config.heartRate.criticalHigh),
                    tags: tags
                ))
            }
        }

        // نمط ٢ — ارتفاع ضغط الدم.
        if let sys = sysTrend, let current = latest.systolic.map(Double.init) {
            let p = probability(current: current, threshold: config.systolic.criticalHigh,
                                normalEdge: config.systolic.normal.upperBound,
                                trend: sys, coverage: coverage)
            if p > 0.02 {
                risks.append(RiskForecast(
                    id: "pressure",
                    name: "ارتفاع ضغط الدم",
                    probability: p, level: level(p),
                    why: reason(indicator: "الانقباضي", unit: "", trend: sys,
                                threshold: config.systolic.criticalHigh),
                    tags: ["ضغط الدم"]
                ))
            }
        }

        // نمط ٣ — إجهاد حراري متقدم.
        if let temp = tempTrend, let current = latest.bodyTemp {
            let p = probability(current: current, threshold: config.bodyTemp.criticalHigh,
                                normalEdge: config.bodyTemp.normal.upperBound,
                                trend: temp, coverage: coverage)
            if p > 0.02 {
                risks.append(RiskForecast(
                    id: "heat",
                    name: "إجهاد حراري متقدم",
                    probability: p, level: level(p),
                    why: reason(indicator: "الحرارة", unit: "°", trend: temp,
                                threshold: config.bodyTemp.criticalHigh),
                    tags: ["حرارة الجسم"]
                ))
            }
        }

        // نمط ٤ — نقص أكسجة (اتجاه هابط، فالعتبة من الأسفل).
        if let spo2 = spo2Trend, let current = latest.vSpo2.map(Double.init) {
            let p = probabilityDescending(current: current, threshold: config.spo2.criticalLow,
                                          normalEdge: config.spo2.normal.lowerBound,
                                          trend: spo2, coverage: coverage)
            risks.append(RiskForecast(
                id: "hypoxia",
                name: "نقص أكسجة",
                probability: p, level: level(p),
                why: spo2.slopePerMinute < 0
                    ? reason(indicator: "الأكسجين", unit: "%", trend: spo2, threshold: config.spo2.criticalLow)
                    : "الأكسجين ثابت عند \(Int(current))% بلا اتجاه هابط خلال النافذة.",
                tags: ["الأكسجين"]
            ))
        }

        risks.sort { $0.probability > $1.probability }

        // التقييم المتوقع: نفس دالة التقييم مطبّقة على القيم المسقَطة.
        let projected = projectedScore(latest: latest, hr: hrTrend, temp: tempTrend,
                                       spo2: spo2Trend, sys: sysTrend, config: config)

        return ForecastResult(risks: risks, projectedScore: projected,
                              coverage: coverage, insufficientCoverage: false)
    }

    // MARK: - الحساب الداخلي

    private static func reading(
        kind: VitalKind, value: Double, display: String,
        band: HealthThresholds.Band, weight: Double, trend: Trend?
    ) -> IndicatorReading {
        IndicatorReading(
            kind: kind, value: value, display: display,
            band: classify(value, band),
            score: subScore(value, band),
            weight: weight, trend: trend
        )
    }

    static func classify(_ v: Double, _ b: HealthThresholds.Band) -> VitalBand {
        if b.normal.contains(v) { return .normal }
        if v >= b.criticalHigh || v <= b.criticalLow { return .critical }
        return .caution
    }

    /// درجة المؤشر ٠…١: واحد داخل النطاق، ثم انحدار خطي حتى الصفر عند العتبة الحرجة.
    static func subScore(_ v: Double, _ b: HealthThresholds.Band) -> Double {
        if b.normal.contains(v) { return 1 }
        if v > b.normal.upperBound {
            let span = b.criticalHigh - b.normal.upperBound
            guard span > 0 else { return 0 }
            return max(0, 1 - (v - b.normal.upperBound) / span)
        }
        let span = b.normal.lowerBound - b.criticalLow
        guard span > 0 else { return 0 }
        return max(0, 1 - (b.normal.lowerBound - v) / span)
    }

    /// انحدار خطي بسيط على (الدقائق، القيمة).
    static func trend(
        of samples: [VitalSample],
        config: HealthThresholds,
        threshold: Double,
        value: (VitalSample) -> Double?
    ) -> Trend? {
        let points: [(x: Double, y: Double)] = samples.compactMap { s in
            guard let y = value(s) else { return nil }
            return (s.sampleDate.timeIntervalSince1970 / 60, y)
        }
        guard points.count >= 4, let last = points.last else { return nil }

        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n
        let my = points.reduce(0) { $0 + $1.y } / n

        let sxx = points.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
        guard sxx > 0 else { return nil }

        let sxy = points.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }
        let slope = sxy / sxx
        let syy = points.reduce(0) { $0 + ($1.y - my) * ($1.y - my) }
        let r2 = syy > 0 ? min(1, max(0, (sxy * sxy) / (sxx * syy))) : 0

        let horizon = config.forecastHorizon / 60
        let projected = last.y + slope * horizon
        var minutes: Double?

        if slope != 0 {
            let t = (threshold - last.y) / slope
            if t > 0, t <= horizon * 3 { minutes = t }
        }

        return Trend(slopePerMinute: slope, rSquared: r2, projected: projected, minutesToThreshold: minutes)
    }

    /// الاحتمال = القرب من العتبة × ثبات الاتجاه × التغطية.
    static func probability(current: Double, threshold: Double, normalEdge: Double,
                            trend: Trend, coverage: Double) -> Double {
        guard trend.slopePerMinute > 0 else {
            return max(0, min(1, nearness(current, threshold, normalEdge) * 0.15 * coverage))
        }
        return max(0, min(1, nearness(current, threshold, normalEdge) * trend.rSquared * coverage))
    }

    static func probabilityDescending(current: Double, threshold: Double, normalEdge: Double,
                                      trend: Trend, coverage: Double) -> Double {
        let span = normalEdge - threshold
        guard span > 0 else { return 0 }
        let near = max(0, min(1, 1 - (current - threshold) / span))
        let momentum = trend.slopePerMinute < 0 ? trend.rSquared : 0.10
        return max(0, min(1, near * momentum * coverage))
    }

    private static func nearness(_ current: Double, _ threshold: Double, _ normalEdge: Double) -> Double {
        let span = threshold - normalEdge
        guard span > 0 else { return 0 }
        return max(0, min(1, 1 - (threshold - current) / span))
    }

    static func level(_ p: Double) -> RiskForecast.Level {
        if p > 0.60 { return .high }
        if p >= 0.25 { return .medium }
        return .low
    }

    static func coverage(_ samples: [VitalSample], span: TimeInterval,
                         config: HealthThresholds) -> Double {
        let expected = span / config.expectedInterval
        guard expected > 0 else { return 0 }
        return min(1, Double(samples.count) / expected)
    }

    static func standardDeviation(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return v.squareRoot()
    }

    /// إزاحة الموقع تُحسب من الإحداثيات المخزّنة أصلاً — إشارة حركة بلا حسّاس إضافي.
    static func isStationary(_ samples: [VitalSample], metres: Double = 20) -> Bool {
        let points = samples.compactMap { s -> (Double, Double)? in
            guard let la = s.vLatitude, let lo = s.vLongitude else { return nil }
            return (la, lo)
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return false }
        return distance(first, last) < metres
    }

    static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6_371_000.0
        let dLat = (b.0 - a.0) * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let la1 = a.0 * .pi / 180
        let la2 = b.0 * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(la1) * cos(la2)
        return 2 * r * atan2(h.squareRoot(), (1 - h).squareRoot())
    }

    private static func reason(indicator: String, unit: String, trend: Trend, threshold: Double) -> String {
        let rate = String(format: "%+.2f", trend.slopePerMinute)
        let base = "\(indicator) يتغير بمعدل \(rate) \(unit) في الدقيقة."
        guard let m = trend.minutesToThreshold else { return base }
        return base + " باستمرار الاتجاه يبلغ \(formatted(threshold)) خلال ~\(Int(m.rounded())) دقيقة."
    }

    private static func formatted(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private static func headline(for band: HealthBand, indicators: [IndicatorReading]) -> String {
        let off = indicators.filter { $0.band != .normal }

        switch band {
        case .excellent:
            return "كل المؤشرات ضمن النطاق الآمن."
        case .good:
            let names = off.map { $0.kind.title }.joined(separator: " و")
            return off.isEmpty
                ? "المؤشرات ضمن النطاق الآمن عموماً."
                : "المؤشرات ضمن النطاق الآمن عموماً، مع ارتفاع طفيف في \(names) يستدعي المتابعة."
        case .attention:
            let names = off.map { $0.kind.title }.joined(separator: " و")
            return "\(names) خارج النطاق الطبيعي. يُنصح بالراحة وإعادة القياس."
        case .danger:
            let names = off.filter { $0.band == .critical }.map { $0.kind.title }.joined(separator: " و")
            return "\(names) تجاوز عتبة الإنذار. توقف عن العمل وتواصل مع غرفة العمليات."
        }
    }

    private static func projectedScore(
        latest: VitalSample, hr: Trend?, temp: Trend?, spo2: Trend?, sys: Trend?,
        config: HealthThresholds
    ) -> Int? {
        var weighted = 0.0
        var total = 0.0

        func add(_ projected: Double?, _ band: HealthThresholds.Band, _ weight: Double) {
            guard let v = projected else { return }
            weighted += subScore(v, band) * weight
            total += weight
        }

        add(hr?.projected,   config.heartRate, config.weightHeartRate)
        add(spo2?.projected, config.spo2,      config.weightSpo2)
        add(temp?.projected, config.bodyTemp,  config.weightBodyTemp)
        add(sys?.projected,  config.systolic,  config.weightPressure)

        guard total > 0 else { return nil }
        return Int((weighted / total * 100).rounded())
    }
}

// MARK: - الربط بسجلّك الحالي

extension SyncHistoryRecord: VitalSample {
    public var sampleDate: Date  { timestamp }
    public var vHeartRate: Int?   { self.heartRate > 0 ? self.heartRate : nil }
    public var vSpo2: Int?        { self.spo2 > 0 ? self.spo2 : nil }
    public var systolic: Int?    { 
        let parts = bloodPressure.split(separator: "/")
        guard parts.count == 2, let sys = Int(parts[0]), sys > 0 else { return nil }
        return sys
    }
    public var diastolic: Int?   { 
        let parts = bloodPressure.split(separator: "/")
        guard parts.count == 2, let dia = Int(parts[1]), dia > 0 else { return nil }
        return dia
    }
    public var bodyTemp: Double? { nil } // Not available in SyncHistoryRecord
    public var vLatitude: Double? { self.latitude != 0.0 ? self.latitude : nil }
    public var vLongitude: Double? { self.longitude != 0.0 ? self.longitude : nil }
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

    /// يُستدعى عند وجوب تنبيه العامل على معصمه.
    /// اربطه بأمر الاهتزاز في iDO SDK من مكان واحد عند الإقلاع.
    public var buzzWatch: (() -> Void)?

    private var config = HealthThresholds.default

    /// بداية أول تجاوز متواصل لكل مؤشر.
    private var breachStartedAt: [VitalKind: Date] = [:]

    /// آخر إشعار أُرسل لكل مؤشر — لمنع التكرار.
    private var lastNotified: [VitalKind: Date] = [:]

    private let cooldown: TimeInterval = 15 * 60

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
        for indicator in assessment.indicators {
            switch indicator.band {
            case .critical:
                handleBreach(indicator, now: now)
            case .normal, .caution, .unknown:
                breachStartedAt[indicator.kind] = nil
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

        notify(
            title: "\(indicator.kind.title) تجاوز الحد",
            body: "\(indicator.kind.title) عند \(indicator.display) \(indicator.kind.unit) منذ أكثر من ٥ دقائق. توقف واسترِح، ثم أعد القياس."
        )

        buzzWatch?()
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
        case .low: return SP.Color.ok
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

    public init(samples: [VitalSample],
                employeeID: String,
                onSelect: @escaping (VitalSample) -> Void = { _ in }) {
        self.samples = samples
        self.employeeID = employeeID
        self.onSelect = onSelect
    }

    private var assessment: HealthAssessment { HealthEngine.assess(samples) }
    private var forecast: ForecastResult { HealthEngine.forecast(samples) }

    public var body: some View {
        ZStack {
            SP.Color.ground.ignoresSafeArea()
            
            if let selected = selectedIndicator {
                IndicatorDetailScreen(
                    indicator: selected,
                    samples: samples,
                    config: HealthThresholds.default,
                    onBack: {
                        withAnimation(.spring()) {
                            selectedIndicator = nil
                        }
                    }
                )
                .transition(.move(edge: .leading))
            } else {
                mainContent
                    .transition(.move(edge: .trailing))
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if assessment.isEmpty {
                    emptyState
                } else {
                    ScoreCard(assessment: assessment)
                    ForecastCard(forecast: forecast)
                    sectionTitle("المؤشرات الحيوية", trailing: "مقارنة بآخر ساعة")
                    metricsGrid
                    sectionTitle("سجل القراءات", trailing: nil)
                    readingsList
                }
                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
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
                isSharing = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(SP.Color.accent)
                    .padding(10)
                    .background(SP.Color.card)
                    .clipShape(Circle())
                    .shadow(color: SP.Color.raised.opacity(0.3), radius: 4, x: 0, y: 2)
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

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)], spacing: 14) {
            ForEach(assessment.indicators.filter { $0.kind != .stability }, id: \.kind) { indicator in
                Button {
                    withAnimation(.spring()) {
                        selectedIndicator = indicator
                    }
                } label: {
                    MetricCard(indicator: indicator, series: series(for: indicator.kind))
                }
                .buttonStyle(.plain)
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
        Text("تقييم إرشادي لسلامة العامل الميداني، مبني على قراءات السوار فقط. ليس تشخيصاً طبياً ولا بديلاً عن مراجعة الطبيب.")
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
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text("تنبؤ بالحالة")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SP.Color.text)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundColor(SP.Color.caution)
                }
                Spacer()
            }

            if forecast.insufficientCoverage {
                Text("تغطية القراءات غير كافية لإصدار تنبؤ.")
                    .font(.system(size: 14))
                    .foregroundColor(SP.Color.muted)
            } else if let top = forecast.risks.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        Text(top.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(top.level.color)
                        Spacer()
                        Text("احتمال \(Int(top.probability * 100))%")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(SP.Color.text)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SP.Color.raised)
                            Capsule().fill(LinearGradient(colors: [top.level.color.opacity(0.5), top.level.color], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(min(max(top.probability, 0), 1)))
                        }
                    }
                    .frame(height: 6)

                    Text(top.why)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundColor(SP.Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("جميع المؤشرات مستقرة للساعة القادمة.")
                    .font(.system(size: 14))
                    .foregroundColor(SP.Color.ok)
            }
        }
        .padding(18)
        .background(cardBackground(radius: 20, border: SP.Color.raised))
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
                if let trend = indicator.trend, abs(trend.slopePerMinute) > 0.001 {
                    Text(trend.slopePerMinute > 0 ? "صاعد ↗" : "هابط ↘")
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
                                Text(trend.slopePerMinute > 0 ? "صاعد ↗" : "هابط ↘")
                                    .font(.system(size: 13))
                                    .foregroundColor(SP.Color.muted)
                            }
                        }
                        
                        TrendChart(values: series, color: indicator.band.color)
                            .frame(height: 160)
                    }
                    .padding(20)
                    .background(cardBackground(border: SP.Color.raised))
                    .padding(.horizontal, 20)

                    // Ranges Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("نطاقات المؤشر")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SP.Color.text)
                        
                        RangeBar(kind: indicator.kind, config: config)
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
                                Text("\(indicator.kind.title) أعلى من المعدل الطبيعي. يرجى أخذ قسط من الراحة والتواصل مع غرفة العمليات إذا استمر الارتفاع.")
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

private struct RangeBar: View {
    let kind: VitalKind
    let config: HealthThresholds

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                Rectangle().fill(SP.Color.caution).frame(width: w * 0.25)
                Rectangle().fill(SP.Color.ok).frame(width: w * 0.50)
                Rectangle().fill(SP.Color.caution).frame(width: w * 0.10)
                Rectangle().fill(SP.Color.danger).frame(width: w * 0.15)
            }
            .cornerRadius(6)
        }
        .frame(height: 12)
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
        let single = HealthEngine.assess([sample], now: sample.sampleDate)
        return single.band.color
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
        let totalPages = 1 + readingPages

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

            for index in 0..<readingPages {
                ctx.beginPage()
                drawReadingsPage(report, pageIndex: index)
                drawFooter(page: index + 2, of: totalPages, report: report)
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

        let lo = min(series.min() ?? 60, 55)
        let hi = max(series.max() ?? 120, 125)
        let span = max(hi - lo, 1)

        func yFor(_ v: Double) -> CGFloat {
            plot.maxY - CGFloat((v - lo) / span) * plot.height
        }

        // النطاق الآمن ٦٠–١٠٠
        Ink.success.withAlphaComponent(0.10).setFill()
        let bandRect = CGRect(x: plot.minX, y: yFor(100),
                              width: plot.width, height: yFor(60) - yFor(100))
        UIBezierPath(rect: bandRect).fill()

        // خط الإنذار ١٢٠
        let alarm = UIBezierPath()
        alarm.move(to: CGPoint(x: plot.minX, y: yFor(120)))
        alarm.addLine(to: CGPoint(x: plot.maxX, y: yFor(120)))
        alarm.setLineDash([3, 3], count: 2, phase: 0)
        alarm.lineWidth = 0.8
        Ink.danger.setStroke()
        alarm.stroke()

        for value in [120.0, 100.0, 60.0] {
            text("\(Int(value))",
                 CGRect(x: rect.minX, y: yFor(value) - 7, width: 28, height: 12),
                 font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                 color: value == 120 ? Ink.danger : Ink.muted, align: .left)
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

        text("تقرير إرشادي لسلامة العامل الميداني، مبني على قراءات السوار. ليس تشخيصاً طبياً.",
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

    @State private var period: ReportPeriod = .week
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

                    if isPreparing {
                        placeholder("جارٍ تجهيز الملخص…")
                    } else if let report = report, !report.isEmpty {
                        summaryCard(report)
                        contentsCard(report)
                    } else {
                        placeholder("لا توجد قراءات في هذه الفترة.")
                    }

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

            bullet("التقييم العام وتفسيره")
            bullet("ملخص كل مؤشر: الأدنى والمتوسط والأعلى ونسبة الوقت ضمن النطاق")
            bullet("مسار نبض القلب خلال الفترة")
            bullet("ملخص يومي لـ \(report.daily.count) يوم")
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
                report = built
                isPreparing = false
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
                    failure = "Error: " + error.localizedDescription
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
