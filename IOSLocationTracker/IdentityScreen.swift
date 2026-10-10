//
//  IdentityScreen.swift
//  SecurityPass — هويتك والمزامنة
//
//  الوجهة (رابط Apps Script) لا تظهر هنا ولا تُعدَّل من الواجهة؛
//  تبقى داخل GoogleSheetSyncManager كما هي.
//

import SwiftUI
import MapKit

struct IdentityScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @ObservedObject var location: LocationManager
    @Binding var employeeId: String

    @ObservedObject private var syncManager = GoogleSheetSyncManager.shared
    @State private var showUnbindConfirm = false
    @FocusState private var idFieldFocused: Bool

    @AppStorage(VoiceAlertManager.conditionsKey) private var conditionsMask: Int = 0
    @AppStorage(VoiceAlertManager.otherKey) private var otherConditions: String = ""
    @AppStorage(VoiceAlertManager.enabledKey) private var voiceAlertEnabled: Bool = true
    @AppStorage(MedicalProfile.bloodTypeKey) private var bloodType: String = MedicalProfile.unknownBloodType
    @AppStorage(MedicalProfile.allergiesKey) private var allergies: String = ""
    @AppStorage(MedicalProfile.emergencyNameKey) private var emergencyName: String = ""
    @AppStorage(MedicalProfile.emergencyPhoneKey) private var emergencyPhone: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                VStack(alignment: .leading, spacing: 9) {
                    Text("المعرف الوظيفي")
                        .font(SP.Font.ui(12, .semibold))
                        .foregroundStyle(SP.Color.muted)

                    TextField("مثال: WATCH_001", text: $employeeId)
                        .font(SP.Font.numeric(16))
                        .foregroundStyle(SP.Color.text)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .focused($idFieldFocused)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(SP.Color.ground)
                        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous)
                                .stroke(idFieldFocused ? SP.Color.accent : SP.Color.lineStrong, lineWidth: 1)
                        )

                    Text("هذا الرقم هو ما يعرّفك في غرفة العمليات. تأكد أنه رقمك قبل البدء.")
                        .font(SP.Font.ui(11.5))
                        .lineSpacing(4)
                        .foregroundStyle(SP.Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .spCard(padding: 16, radius: 16)

                healthProfileCard

                // MARK: - Map View
                VStack(alignment: .leading, spacing: 9) {
                    Text("موقعك الحالي")
                        .font(SP.Font.ui(13, .semibold))
                        .foregroundStyle(SP.Color.text)

                    let coord = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                    if true {
                        Map(coordinateRegion: .constant(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))), interactionModes: .all, annotationItems: [MapLocation(coord: coord)]) { place in
                            MapMarker(coordinate: place.coord, tint: SP.Color.danger)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SP.Color.lineStrong, lineWidth: 1)
                        )
                    } else {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("جاري تحديد الموقع...")
                                .font(SP.Font.ui(12))
                                .foregroundStyle(SP.Color.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(SP.Color.ground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .spCard(padding: 16, radius: 16)


                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncManager.isAutoSyncActive ? SP.Color.ok : SP.Color.muted)
                            .frame(width: 7, height: 7)
                        Text(syncManager.isAutoSyncActive ? "إرسال تلقائي (كل دقيقة)" : "آخر إرسال وصل")
                            .font(SP.Font.ui(13, .semibold))
                            .foregroundStyle(SP.Color.text)
                    }
                    Spacer()
                    Text(syncManager.lastSyncTime.map(Self.timeFormatter.string(from:)) ?? "—")
                        .font(SP.Font.numeric(13))
                        .foregroundStyle(SP.Color.text)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .spCard(padding: 0, radius: 16)

                Button {
                    send()
                } label: {
                    Label(syncManager.isSyncing ? "جارٍ الإرسال…" : "أرسل قراءاتي الآن",
                          systemImage: "arrow.up.to.line")
                }
                .buttonStyle(SPPrimaryButton())
                .disabled(syncManager.isSyncing)

                Button {
                    ido.requestLiveMetrics()
                } label: {
                    Label("اقرأ نبضي الآن", systemImage: "heart")
                }
                .buttonStyle(SPSecondaryButton())

                Button {
                    ido.activateWatch(force: true)
                } label: {
                    Label("أيقظ الساعة وحسّاساتها", systemImage: "rays")
                }
                .buttonStyle(SPSecondaryButton())

                Button {
                    showUnbindConfirm = true
                } label: {
                    Label("فكّ ارتباط الساعة", systemImage: "trash")
                }
                .buttonStyle(SPDestructiveButton())
                .padding(.top, 6)
            }
            .padding(.horizontal, SP.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .spScrollDismissesKeyboard()
        .safeAreaInset(edge: .top) {
            SPScreenHeader(kicker: "تعريفك في غرفة العمليات", title: "هويتك والمزامنة")
                .background(SP.Color.ground)
        }
        .confirmationDialog("فكّ ارتباط الساعة؟",
                            isPresented: $showUnbindConfirm, titleVisibility: .visible) {
            Button("فكّ الارتباط", role: .destructive) { ido.forceUnbindAndReset() }
            Button("إلغاء", role: .cancel) { }
        } message: {
            Text("ستحتاج إلى إعادة الاقتران من جديد قبل أن تستأنف القراءة.")
        }
    }

    private func send() {
        syncManager.performAutoSync(force: true)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "hh:mm a"
        return f
    }()
}

// MARK: - الحالة الصحية والتنبيه الصوتي

extension IdentityScreen {
    var healthProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("البطاقة الطبية", systemImage: "cross.case.fill")
                .font(SP.Font.ui(15, .semibold))
                .foregroundStyle(SP.Color.text)

            HStack {
                Text("فصيلة الدم")
                    .font(SP.Font.ui(13, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer()
                Picker("فصيلة الدم", selection: $bloodType) {
                    ForEach(MedicalProfile.bloodTypes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(SP.Color.accent)
            }

            medicalField("الحساسية (أدوية، أطعمة…)", text: $allergies)
            medicalField("اسم جهة الاتصال للطوارئ", text: $emergencyName)
            medicalField("رقم الطوارئ", text: $emergencyPhone, phone: true)

            Divider().overlay(SP.Color.line)

            Text("الأمراض المزمنة")
                .font(SP.Font.ui(13, .semibold))
                .foregroundStyle(SP.Color.text)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ChronicCondition.allCases) { condition in
                    conditionChip(condition)
                }
            }

            TextField("أخرى (اختياري)", text: $otherConditions)
                .font(SP.Font.ui(14))
                .foregroundStyle(SP.Color.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(SP.Color.ground)
                .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous)
                        .stroke(SP.Color.lineStrong, lineWidth: 1)
                )

            Text("تظهر البطاقة في إشعارات الحالة الحرجة على شاشة القفل ليراها المسعف دون فتح الجوال، والأمراض تُذكر في التنبيه الصوتي. «أخرى» تظهر في الإشعار فقط.")
                .font(SP.Font.ui(11.5))
                .lineSpacing(4)
                .foregroundStyle(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(SP.Color.line)

            Toggle(isOn: $voiceAlertEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("التنبيه الصوتي عند الحالة الحرجة")
                        .font(SP.Font.ui(13, .semibold))
                        .foregroundStyle(SP.Color.text)
                    Text("يعمل حتى مع الوضع الصامت. ارفع مستوى الصوت ليكون مسموعاً.")
                        .font(SP.Font.ui(11.5))
                        .foregroundStyle(SP.Color.muted)
                }
            }
            .tint(SP.Color.accent)

            Button {
                VoiceAlertManager.shared.test()
            } label: {
                Label("تجربة الصوت", systemImage: "speaker.wave.2")
            }
            .buttonStyle(SPSecondaryButton())
        }
        .spCard(padding: 16, radius: 16)
    }

    private func medicalField(_ placeholder: String, text: Binding<String>, phone: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .font(SP.Font.ui(14))
            .foregroundStyle(SP.Color.text)
            .keyboardType(phone ? .phonePad : .default)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(SP.Color.ground)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous)
                    .stroke(SP.Color.lineStrong, lineWidth: 1)
            )
    }

    private func conditionChip(_ condition: ChronicCondition) -> some View {
        let selected = conditionsMask & condition.bit != 0
        return Button {
            conditionsMask ^= condition.bit
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(condition.title)
                    .font(SP.Font.ui(13, selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? SP.Color.accent : SP.Color.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(selected ? SP.Color.accent.opacity(0.12) : SP.Color.ground)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.controlRadius, style: .continuous)
                    .stroke(selected ? SP.Color.accent : SP.Color.lineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MapLocation: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}
