//
//  ContentView.swift
//  SecurityPass — الواجهة الجديدة
//
//  يستبدل هذا الملف ContentView القديم بالكامل. لم يُمسّ أي مدير:
//  IdoSmartManager و LocationManager و GoogleSheetSyncManager و
//  BloodPressureAlgorithm تُستدعى بنفس أسمائها وتواقيعها الحالية.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var ido = IdoSmartManager.shared
    @StateObject private var location = LocationManager.shared

    /// نفس مفتاح التخزين المستخدم في البناء الحالي.
    @AppStorage("WATCH_APP_DEFAULT") private var employeeId: String = "WATCH_001"

    @State private var tab: Tab = .status

    enum Tab: Hashable { case status, devices, sos, identity }

    var body: some View {
        ZStack(alignment: .bottom) {
            SP.Color.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .status:
                    StatusScreen(ido: ido, location: location, employeeId: employeeId) {
                        tab = .devices
                    }
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

// MARK: - شريط التبويب

struct SPTabBar: View {
    @Binding var selection: ContentView.Tab

    var body: some View {
        HStack(spacing: 4) {
            item(.status,   "الحالة",  "shield",            SP.Color.accent)
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
                        Label("البحث عن السوار يدويًا", systemImage: "magnifyingglass")
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
                kicker: "منصة راصد",
                title: "القراءة الصحية",
                trailing: AnyView(
                    SPStatusPill(text: fullyActive ? "متصل ونشِط" : (connected ? "متصل (جاري التنشيط)" : "غير متصل"),
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
                 ? "جارٍ البحث التلقائي لإعادة الاتصال فور رصد السوار المقترن."
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
                Text(connected ? "نبض القلب — مباشر" : "نبض القلب — آخر قراءة")
                    .font(SP.Font.ui(13, .semibold))
                    .foregroundStyle(connected ? SP.Color.text : SP.Color.muted)
                Spacer(minLength: 0)
                if connected {
                    Text("تحديث كل ثانيتين")
                        .font(SP.Font.ui(11))
                        .foregroundStyle(SP.Color.muted)
                } else {
                    Text("قديمة")
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
                Text("هادئ").font(SP.Font.ui(10.5)).foregroundStyle(SP.Color.muted)
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
            Button(syncManager.isSyncing ? "جارٍ الإرسال…" : "إرسال الآن") {
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
        location.latitude == 0 && location.longitude == 0 ? "—" : "مُحدَّد"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "hh:mm a"
        return f
    }()
}
