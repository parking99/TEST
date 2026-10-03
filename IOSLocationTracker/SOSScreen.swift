//
//  SOSScreen.swift
//  SecurityPass — نداء SOS
//
//  يرسل عبر GoogleSheetSyncManager.shared.sendData(... isSos: true ...)
//  بنفس التوقيع الموجود في البناء الحالي. لا تغيير في الحمولة ولا في الوجهة.
//

import SwiftUI

struct SOSScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @ObservedObject var location: LocationManager
    let employeeId: String

    enum Stage { case idle, sending, sent, failed }
    @State private var stage: Stage = .idle
    @State private var sentAt: Date?
    @State private var reference: String = ""

    var body: some View {
        VStack(spacing: SP.Metric.gap) {
            switch stage {
            case .idle:    idleView
            case .sending: sendingView
            case .sent:    sentView
            case .failed:  failedView
            }
        }
        .padding(.horizontal, SP.Metric.screenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top) {
            SPScreenHeader(kicker: "إلى غرفة العمليات مباشرة", title: "SOS")
                .background(SP.Color.ground)
        }
    }

    // MARK: قبل الإرسال

    private var idleView: some View {
        VStack(spacing: SP.Metric.gap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SP.Color.dangerText)
                    Text("إرسال نداء SOS طارئ")
                        .font(SP.Font.ui(16, .semibold))
                        .foregroundStyle(SP.Color.text)
                    Spacer(minLength: 0)
                }
                Text("يُرسل فورًا إلى لوحة المراقبة مع موقعك ومؤشراتك الحيوية الحالية. لا ترسله إلا في حالة طارئة.")
                    .font(SP.Font.ui(13))
                    .lineSpacing(5)
                    .foregroundStyle(Color(hex: 0xFFB8B4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SP.Color.dangerSurf)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous)
                    .stroke(SP.Color.dangerLine, lineWidth: 1)
            )

            payloadCard

            Spacer(minLength: 0)

            Button {
                send()
            } label: {
                Label("إرسال النداء الآن", systemImage: "power")
            }
            .buttonStyle(SPEmergencyButton())
        }
    }

    /// ما سيُرسل فعلًا — نفس الحقول العشرة التي يأخذها sendData.
    private var payloadCard: some View {
        VStack(spacing: 0) {
            SPInfoRow(label: "المعرف الوظيفي", value: employeeId)
            divider
            SPInfoRow(label: "نبض القلب", value: "\(ido.currentHeartRate) bpm")
            divider
            SPInfoRow(label: "الأكسجين · ضغط الدم",
                      value: "\(ido.currentSpo2)% · \(ido.currentBloodPressure)")
            divider
            SPInfoRow(label: "حرارة الجسم", value: String(format: "%.1f °م", ido.currentTemperature))
            divider
            SPInfoRow(label: "الإحداثيات",
                      value: String(format: "%.4f, %.4f", location.latitude, location.longitude))
        }
        .padding(.horizontal, 16)
        .background(SP.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SP.Color.line, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(SP.Color.line).frame(height: 1)
    }

    // MARK: أثناء الإرسال

    private var sendingView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(SP.Color.danger, lineWidth: 3)
                    .frame(width: 118, height: 118)
                    .background(Circle().fill(SP.Color.dangerSurf))
                Image(systemName: "power")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(SP.Color.dangerText)
            }
            VStack(spacing: 9) {
                Text("جارٍ إرسال نداء SOS")
                    .font(SP.Font.ui(18, .semibold))
                    .foregroundStyle(SP.Color.text)
                Text("إلى لوحة المراقبة…")
                    .font(SP.Font.ui(13))
                    .foregroundStyle(SP.Color.muted)
            }
            ProgressView()
                .tint(SP.Color.danger)
            Spacer()
            Spacer()
        }
    }

    // MARK: بعد الاستلام

    private var sentView: some View {
        VStack(spacing: 18) {
            VStack(spacing: 13) {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(SP.Color.onAccent)
                    .frame(width: 56, height: 56)
                    .background(SP.Color.ok)
                    .clipShape(Circle())
                Text("تم إرسال طلب الطوارئ")
                    .font(SP.Font.ui(17, .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SP.Color.text)
                Text(stamp)
                    .font(SP.Font.numeric(12.5, .regular))
                    .foregroundStyle(Color(hex: 0x7FFFC2))
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(SP.Color.okSurface)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.heroRadius, style: .continuous)
                    .stroke(SP.Color.okDeep, lineWidth: 1)
            )

            payloadCard
            Spacer(minLength: 0)

            Button("إعادة الشاشة للبداية") { stage = .idle }
                .buttonStyle(SPSecondaryButton())
        }
    }

    // MARK: فشل

    private var failedView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SP.Color.dangerText)
                    Text("فشل الإرسال")
                        .font(SP.Font.ui(15, .semibold))
                        .foregroundStyle(SP.Color.text)
                    Spacer(minLength: 0)
                }
                Text("تعذّر الاتصال — حاول مرة أخرى، أو اتصل بغرفة العمليات مباشرة.")
                    .font(SP.Font.ui(12.5))
                    .lineSpacing(4)
                    .foregroundStyle(Color(hex: 0xFFB8B4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SP.Color.dangerSurf)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SP.Color.dangerLine, lineWidth: 1)
            )

            Spacer(minLength: 0)

            Button { send() } label: {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SPEmergencyButton())
        }
    }

    // MARK: الإرسال

    private func send() {
        stage = .sending
        GoogleSheetSyncManager.shared.sendData(
            empId: employeeId,
            latitude: location.latitude,
            longitude: location.longitude,
            heartRate: ido.currentHeartRate,
            spo2: ido.currentSpo2,
            bodyTemp: ido.currentTemperature,
            battery: ido.currentBattery,
            isSos: true,
            deviceIdentifier: ido.currentDeviceUUID,
            bloodPressure: ido.currentBloodPressure
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    sentAt = Date()
                    reference = String(format: "SOS-%04d", Int.random(in: 1...9999))
                    stage = .sent
                case .failure:
                    stage = .failed
                }
            }
        }
    }

    private var stamp: String {
        guard let sentAt else { return reference }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return "\(f.string(from: sentAt)) · \(reference)"
    }
}
