import SwiftUI

struct ContentView: View {
    @StateObject private var watchManager = IdoSmartManager.shared
    @StateObject private var locationManager = LocationManager()

    @State private var empId: String = "WATCH_001"
    @State private var sheetSyncStatusText: String = "المزامنة التلقائية مع Google Sheets: مفعلة"
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""

    // Periodic 30s auto-sync timer
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerSection
                empIdSection
                vitalsGridSection
                actionButtonsSection
                syncStatusSection
                discoveredDevicesSection
            }
            .padding(16)
        }
        .background(Color(hex: "F0F4F8").ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .onReceive(timer) { _ in
            if watchManager.isConnected {
                sendDataToGoogleSheet(isSos: false, isAuto: true)
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("تنبيه"), message: Text(alertMessage), dismissButton: .default(Text("حسناً")))
        }
    }

    // MARK: - Subviews for Clean Type Checking
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("نظام مراقبة السوار الذكي وقوقل شيت")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "1E293B"))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(watchManager.statusMessage)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "64748B"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }

    private var empIdSection: some View {
        HStack {
            Text("المعرف الوظيفي:")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "334155"))

            TextField("مثال: WATCH_001", text: $empId)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1E293B"))
                .padding(8)
                .background(Color(hex: "F8FAFC"))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                )
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var vitalsGridSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(
                    title: "❤️ نبض القلب",
                    value: watchManager.currentHeartRate > 0 ? "\(watchManager.currentHeartRate) bpm" : "-- bpm",
                    color: Color(hex: "DC2626")
                )
                MetricCard(
                    title: "💨 نسبة الأكسجين",
                    value: watchManager.currentSpo2 > 0 ? "\(watchManager.currentSpo2) %" : "-- %",
                    color: Color(hex: "0284C7")
                )
            }

            HStack(spacing: 8) {
                MetricCard(
                    title: "🩺 ضغط الدم (خوارزمية)",
                    value: "\(watchManager.currentBloodPressure) mmHg",
                    color: Color(hex: "7C3AED")
                )
                MetricCard(
                    title: "🌡️ حرارة الجسم",
                    value: String(format: "%.1f °C", watchManager.currentTemperature),
                    color: Color(hex: "EA580C")
                )
            }

            HStack(spacing: 8) {
                MetricCard(
                    title: "👟 الخطوات",
                    value: watchManager.currentSteps > 0 ? "\(watchManager.currentSteps) خطوة" : "-- خطوة",
                    color: Color(hex: "16A34A")
                )
                MetricCard(
                    title: "🔋 البطارية",
                    value: watchManager.currentBattery > 0 ? "\(watchManager.currentBattery) %" : "-- %",
                    color: Color(hex: "D97706")
                )
            }
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                if watchManager.isScanning {
                    watchManager.stopScan()
                } else {
                    watchManager.startScan()
                }
            }) {
                Text(watchManager.isScanning ? "إيقاف البحث" : "البحث عن السوار / الساعة عبر Bluetooth")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "3B82F6"))
                    .cornerRadius(8)
            }

            Button(action: {
                watchManager.activateWatch()
            }) {
                Text("تشغيل / تنشيط شاشة وحساسات الساعة ⚡")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "0284C7"))
                    .cornerRadius(8)
            }

            Button(action: {
                watchManager.forceUnbindAndReset()
            }) {
                Text("إلغاء اقتران الساعة وتصفير الربط 🔄")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "64748B"))
                    .cornerRadius(8)
            }

            Button(action: {
                sendDataToGoogleSheet(isSos: false, isAuto: false)
            }) {
                Text("إرسال البيانات إلى السيرفر و Google Sheets 📊")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "16A34A"))
                    .cornerRadius(8)
            }

            Button(action: {
                sendDataToGoogleSheet(isSos: true, isAuto: false)
            }) {
                Text("🚨 إرسال نداء استغاثة طارئ (SOS) 🚨")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "DC2626"))
                    .cornerRadius(8)
            }
        }
        .padding(.top, 4)
    }

    private var syncStatusSection: some View {
        Text(sheetSyncStatusText)
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "475569"))
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
    }

    private var discoveredDevicesSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("الأجهزة المكتشفة بالقرب منك (انقر للاتصال):")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "334155"))
                Spacer()
            }
            .padding(.top, 4)

            if watchManager.discoveredDevices.isEmpty {
                Text("لم يتم العثور على أجهزة بعد. اضغط على زر البحث أعلاه.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "94A3B8"))
                    .padding(.vertical, 16)
            } else {
                ForEach(watchManager.discoveredDevices) { device in
                    Button(action: {
                        watchManager.connect(device: device)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("⌚ \(device.name)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "1E293B"))
                                Text("MAC: \(device.macAddress) (الإشارة: \(device.rssi) dBm)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "64748B"))
                            }
                            Spacer()
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                    }
                }
            }
        }
    }

    private func sendDataToGoogleSheet(isSos: Bool, isAuto: Bool) {
        if isSos {
            sheetSyncStatusText = "🚨 جارٍ إرسال نداء SOS إلى Google Sheets..."
        } else if !isAuto {
            sheetSyncStatusText = "جارٍ إرسال البيانات إلى Google Sheets..."
        }

        GoogleSheetSyncManager.shared.sendData(
            empId: empId,
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            heartRate: watchManager.currentHeartRate,
            spo2: watchManager.currentSpo2,
            bodyTemp: watchManager.currentTemperature,
            battery: watchManager.currentBattery,
            isSos: isSos,
            deviceIdentifier: watchManager.currentDeviceUUID,
            bloodPressure: watchManager.currentBloodPressure
        ) { result in
            let timeStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            switch result {
            case .success:
                if isSos {
                    sheetSyncStatusText = "🚨 تم إرسال نداء SOS بنجاح! \(timeStr)"
                    alertMessage = "🚨 تم إرسال نداء الاستغاثة SOS إلى لوحة المراقبة بنجاح!"
                    showingAlert = true
                } else {
                    sheetSyncStatusText = "آخر مزامنة ناجحة: \(timeStr) ✅"
                    if !isAuto {
                        alertMessage = "تم إرسال بيانات السوار والضغط إلى Google Sheets بنجاح! 📊"
                        showingAlert = true
                    }
                }
            case .failure(let error):
                sheetSyncStatusText = "فشل الإرسال إلى Google Sheets: \(error.localizedDescription)"
                if !isAuto {
                    alertMessage = "خطأ في الاتصال بقوقل شيت: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - Reusable Metric Card View
struct MetricCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "64748B"))

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
