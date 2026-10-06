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
            item(.status,   "Ø§Ù„Ø­Ø§Ù„Ø©",  "shield",            SP.Color.accent)
            item(.history,  "Ø§Ù„Ø³Ø¬Ù„",   "clock",             SP.Color.ok)
            item(.devices,  "Ø§Ù„Ø£Ø¬Ù‡Ø²Ø©", "dot.radiowaves.left.and.right", SP.Color.measure)
            item(.sos,      "SOS",     "exclamationmark.triangle", SP.Color.dangerText)
            item(.identity, "Ø§Ù„Ù‡ÙˆÙŠØ©",  "person.text.rectangle", SP.Color.accent)
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
                    SPMetricCard(title: "Ù†Ø³Ø¨Ø© Ø§Ù„Ø£ÙƒØ³Ø¬ÙŠÙ†", value: connected ? text(ido.currentSpo2) : "â€”",
                                 unit: "%", icon: "drop", iconColor: SP.Color.measure,
                                 isStale: !connected)
                    SPMetricCard(title: "Ø¶ØºØ· Ø§Ù„Ø¯Ù…", value: connected ? (ido.currentBloodPressure.isEmpty ? "â€”" : ido.currentBloodPressure) : "â€”",
                                 icon: "gauge.medium", iconColor: SP.Color.accent,
                                 isStale: !connected)
                    SPMetricCard(title: "Ø­Ø±Ø§Ø±Ø© Ø§Ù„Ø¬Ø³Ù…", value: connected ? temperatureText : "â€”",
                                 unit: "Â°Ù…", icon: "thermometer.medium",
                                 iconColor: SP.Color.dangerText, isStale: !connected)
                    SPMetricCard(title: "Ø§Ù„Ø®Ø·ÙˆØ§Øª", value: connected ? text(ido.currentSteps) : "â€”",
                                 icon: "figure.walk", iconColor: SP.Color.ok,
                                 isStale: !connected)
                    SPMetricCard(title: "Ø¨Ø·Ø§Ø±ÙŠØ© Ø§Ù„Ø³ÙˆØ§Ø±", value: connected ? text(ido.currentBattery) : "â€”",
                                 unit: "%", icon: "battery.75", iconColor: SP.Color.muted,
                                 isStale: !connected)
                    SPMetricCard(title: "Ø§Ù„Ù…ÙˆÙ‚Ø¹", value: locationText,
                                 icon: "location", iconColor: SP.Color.measure)
                }

                syncStrip

                if !connected {
                    Button {
                        onNavigateToDevices?()
                    } label: {
                        Label("Ø§Ù„Ø¨Ø­Ø« Ø¹Ù† Ø§Ù„Ø³ÙˆØ§Ø± ÙŠØ¯ÙˆÙŠÙ‹Ø§", systemImage: "magnifyingglass")
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
                kicker: "Ù…Ù†ØµØ© Ø±Ø§ØµØ¯",
                title: "Ø§Ù„Ù‚Ø±Ø§Ø¡Ø© Ø§Ù„ØµØ­ÙŠØ©",
                trailing: AnyView(
                    SPStatusPill(text: fullyActive ? "Ù…ØªØµÙ„ ÙˆÙ†Ø´ÙØ·" : (connected ? "Ù…ØªØµÙ„ (Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªÙ†Ø´ÙŠØ·)" : "ØºÙŠØ± Ù…ØªØµÙ„"),
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
                Text("ØªÙ… Ù‚Ø·Ø¹ Ø§Ù„Ø§ØªØµØ§Ù„ Ø¨Ø§Ù„Ø³ÙˆØ§Ø±")
                    .font(SP.Font.ui(14, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer(minLength: 0)
            }
            Text(ido.statusMessage.isEmpty
                 ? "Ø¬Ø§Ø±Ù Ø§Ù„Ø¨Ø­Ø« Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠ Ù„Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ø§ØªØµØ§Ù„ ÙÙˆØ± Ø±ØµØ¯ Ø§Ù„Ø³ÙˆØ§Ø± Ø§Ù„Ù…Ù‚ØªØ±Ù†."
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
                Text(connected ? "Ù†Ø¨Ø¶ Ø§Ù„Ù‚Ù„Ø¨ â€” Ù…Ø¨Ø§Ø´Ø±" : "Ù†Ø¨Ø¶ Ø§Ù„Ù‚Ù„Ø¨ â€” Ø¢Ø®Ø± Ù‚Ø±Ø§Ø¡Ø©")
                    .font(SP.Font.ui(13, .semibold))
                    .foregroundStyle(connected ? SP.Color.text : SP.Color.muted)
                Spacer(minLength: 0)
                if connected {
                    Text("ØªØ­Ø¯ÙŠØ« ÙƒÙ„ Ø«Ø§Ù†ÙŠØªÙŠÙ†")
                        .font(SP.Font.ui(11))
                        .foregroundStyle(SP.Color.muted)
                } else {
                    Text("Ù‚Ø¯ÙŠÙ…Ø©")
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
                Text("Ù†Ø¨Ø¶Ø©/Ø¯Ù‚ÙŠÙ‚Ø©")
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
                Text("Ù‡Ø§Ø¯Ø¦").font(SP.Font.ui(10.5)).foregroundStyle(SP.Color.muted)
                Spacer()
                Text("Ø§Ù„Ù†Ø·Ø§Ù‚ Ø§Ù„Ø¢Ù…Ù†").font(SP.Font.ui(10.5, .semibold)).foregroundStyle(SP.Color.ok)
                Spacer()
                Text("Ù…Ø±ØªÙØ¹").font(SP.Font.ui(10.5)).foregroundStyle(SP.Color.muted)
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
                    Text(syncManager.isAutoSyncActive ? "Ø¥Ø±Ø³Ø§Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠ (ÙƒÙ„ Ø¯Ù‚ÙŠÙ‚Ø©)" : "Ø¢Ø®Ø± Ø¥Ø±Ø³Ø§Ù„ ÙˆØµÙ„")
                        .font(SP.Font.ui(11.5))
                        .foregroundStyle(SP.Color.muted)
                }
                Text(syncManager.lastSyncTime.map(Self.timeFormatter.string(from:)) ?? "â€”")
                    .font(SP.Font.numeric(13))
                    .foregroundStyle(SP.Color.text)
            }
            Spacer(minLength: 0)
            Button(syncManager.isSyncing ? "Ø¬Ø§Ø±Ù Ø§Ù„Ø¥Ø±Ø³Ø§Ù„â€¦" : "Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø¢Ù†") {
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
        location.latitude == 0 && location.longitude == 0 ? "â€”" : "Ù…ÙØ­Ø¯ÙŽÙ‘Ø¯"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "hh:mm a"
        return f
    }()
}

import SwiftUI

struct HistoryScreen: View {
    @ObservedObject var syncManager = GoogleSheetSyncManager.shared
    @ObservedObject var location = LocationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            SPScreenHeader(kicker: "Ø§Ù„Ø³Ø¬Ù„", title: "Ø³Ø¬Ù„ Ø§Ù„Ù‚Ø±Ø§Ø¡Ø§Øª ÙˆØ§Ù„Ù…ÙˆÙ‚Ø¹")
                .background(SP.Color.ground)
            
            // Map View for the Current Location
            Map(coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude == 0 ? 24.7136 : location.latitude, longitude: location.longitude == 0 ? 46.6753 : location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )), annotationItems: [LocationAnnotation(latitude: location.latitude, longitude: location.longitude)]) { item in
                MapMarker(coordinate: item.coordinate, tint: SP.Color.accent)
            }
            .frame(height: 250)
            .cornerRadius(SP.Metric.controlRadius)
            .padding()
            
            if syncManager.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(SP.Color.muted)
                    Text("Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ø³Ø¬Ù„ Ø­ØªÙ‰ Ø§Ù„Ø¢Ù†")
                        .font(SP.Font.ui(14, .medium))
                        .foregroundStyle(SP.Color.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(syncManager.history) { record in
                    HistoryRow(record: record)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .background(SP.Color.ground.ignoresSafeArea())
    }
}

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
                    Text("Ø­Ø§Ù„Ø© Ø·ÙˆØ§Ø±Ø¦")
                        .font(SP.Font.ui(10, .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SP.Color.dangerText.opacity(0.2))
                        .foregroundStyle(SP.Color.dangerText)
                        .cornerRadius(4)
                } else {
                    Text("Ù…Ø²Ø§Ù…Ù†Ø© Ø¯ÙˆØ±ÙŠØ©")
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
                MetricMini(icon: "location.fill", value: "Ù…ÙØ­ÙŽØ¯Ù‘ÙŽØ«", color: SP.Color.accent)
            }
        }
        .padding()
        .background(SP.Color.surface)
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


