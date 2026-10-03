//
//  IdentityScreen.swift
//  SecurityPass — هويتك والمزامنة
//
//  الوجهة (رابط Apps Script) لا تظهر هنا ولا تُعدَّل من الواجهة؛
//  تبقى داخل GoogleSheetSyncManager كما هي.
//

import SwiftUI

struct IdentityScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @ObservedObject var location: LocationManager
    @Binding var employeeId: String

    @ObservedObject private var syncManager = GoogleSheetSyncManager.shared
    @State private var showUnbindConfirm = false
    @FocusState private var idFieldFocused: Bool

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

                    Text("هذا الرقم هو ما يعرّفك في غرفة العمليات. تأكد أنه رقمك قبل بدء الوردية.")
                        .font(SP.Font.ui(11.5))
                        .lineSpacing(4)
                        .foregroundStyle(SP.Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
                    ido.activateWatch()
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
