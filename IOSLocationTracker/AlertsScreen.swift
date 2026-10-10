//
//  AlertsScreen.swift
//  SecurityPass — التنبيهات
//
//  المنبّهات (على السوار + إشعار بالملاحظة)، إعدادات التنبيهات الذكية، وسجل آخر التنبيهات.
//

import SwiftUI

struct AlertsScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @ObservedObject private var store = ReminderStore.shared
    @ObservedObject private var log = AlertLog.shared

    @AppStorage(AlertSettings.outOfRangeKey) private var outOfRange = true
    @AppStorage(AlertSettings.rapidChangeKey) private var rapidChange = true
    @AppStorage(AlertSettings.faintKey) private var faintDetection = true
    @AppStorage(VoiceAlertManager.enabledKey) private var voiceAlert = true

    @State private var editing: Reminder?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                remindersCard
                smartAlertsCard
                logCard
            }
            .padding(.horizontal, SP.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            SPScreenHeader(kicker: "منبّهات وتنبيهات ذكية", title: "التنبيهات")
                .background(SP.Color.ground)
        }
        .sheet(item: $editing) { reminder in
            ReminderEditor(reminder: reminder, isNew: !store.reminders.contains { $0.id == reminder.id })
        }
    }

    // MARK: المنبّهات

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("المنبّهات", systemImage: "alarm")
                    .font(SP.Font.ui(15, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer()
                Button {
                    editing = Reminder(hour: 8, minute: 0, weekdays: Set(1...7), note: "", kind: .medication)
                } label: {
                    Label("إضافة", systemImage: "plus")
                        .font(SP.Font.ui(13, .semibold))
                }
                .disabled(store.reminders.count >= store.maxReminders)
            }

            if store.reminders.isEmpty {
                Text("أضف منبّهاً لموعد دواء أو شرب ماء أو استراحة. يهتز السوار في وقته حتى لو كان الجوال بعيداً، ويظهر إشعار بملاحظتك.")
                    .font(SP.Font.ui(12.5))
                    .lineSpacing(4)
                    .foregroundStyle(SP.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(store.reminders) { r in
                    reminderRow(r)
                    if r.id != store.reminders.last?.id { Divider().overlay(SP.Color.line) }
                }
            }

            let status = ido.isConnected ? store.bandStatus : "السوار غير متصل — تُرسل المنبّهات عند الاتصال."
            if !status.isEmpty {
                Label(status, systemImage: ido.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .font(SP.Font.ui(11.5))
                    .foregroundStyle(SP.Color.muted)
            }
        }
        .spCard(padding: 16, radius: 16)
    }

    private func reminderRow(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.kind.symbol)
                .font(.system(size: 16))
                .foregroundStyle(r.isEnabled ? SP.Color.accent : SP.Color.muted)
                .frame(width: 28)
            Button {
                editing = r
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.timeText)
                        .font(SP.Font.numeric(20, .semibold))
                        .foregroundStyle(r.isEnabled ? SP.Color.text : SP.Color.muted)
                    Text("\(r.displayText) · \(r.daysText)")
                        .font(SP.Font.ui(12))
                        .foregroundStyle(SP.Color.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { r.isEnabled }, set: { store.setEnabled(r, $0) }))
                .labelsHidden()
                .tint(SP.Color.accent)
        }
    }

    // MARK: التنبيهات الذكية

    private var smartAlertsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("التنبيهات الذكية", systemImage: "waveform.path.ecg")
                .font(SP.Font.ui(15, .semibold))
                .foregroundStyle(SP.Color.text)

            settingToggle($outOfRange, "ارتفاع وانخفاض المؤشرات",
                          "إشعار عند خروج النبض أو الأكسجين أو الحرارة عن النطاق الطبيعي.")
            settingToggle($rapidChange, "التغيّر السريع",
                          "إشعار واهتزاز للسوار عند ارتفاع أو هبوط مفاجئ خلال دقائق، حتى ضمن الطبيعي.")
            settingToggle($faintDetection, "كشف الإغماء",
                          "عدم حركة لعشر دقائق مع نبض غير طبيعي أو هبوط مفاجئ يطلق التنبيه الصوتي فوراً.")
            settingToggle($voiceAlert, "التنبيه الصوتي",
                          "رسالة صوتية تطلب المساعدة عند الحالة الحرجة، وتذكر الأمراض المسجّلة في «الهوية».")
        }
        .spCard(padding: 16, radius: 16)
    }

    private func settingToggle(_ value: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SP.Font.ui(13.5, .semibold))
                    .foregroundStyle(SP.Color.text)
                Text(detail)
                    .font(SP.Font.ui(11.5))
                    .lineSpacing(3)
                    .foregroundStyle(SP.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SP.Color.accent)
    }

    // MARK: السجل

    private static let logTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA")
        f.dateFormat = "d MMM · h:mm a"
        return f
    }()

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("آخر التنبيهات", systemImage: "clock.arrow.circlepath")
                    .font(SP.Font.ui(15, .semibold))
                    .foregroundStyle(SP.Color.text)
                Spacer()
                if !log.entries.isEmpty {
                    Button("مسح") { log.clear() }
                        .font(SP.Font.ui(12.5))
                }
            }

            if log.entries.isEmpty {
                Text("لا توجد تنبيهات بعد.")
                    .font(SP.Font.ui(12.5))
                    .foregroundStyle(SP.Color.muted)
            } else {
                ForEach(log.entries.prefix(20)) { e in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(e.kind))
                            .foregroundStyle(color(e.kind))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title)
                                .font(SP.Font.ui(13, .semibold))
                                .foregroundStyle(SP.Color.text)
                            Text(e.body)
                                .font(SP.Font.ui(11.5))
                                .lineSpacing(3)
                                .foregroundStyle(SP.Color.muted)
                                .lineLimit(3)
                            Text(Self.logTime.string(from: e.date))
                                .font(SP.Font.ui(10.5))
                                .foregroundStyle(SP.Color.muted)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .spCard(padding: 16, radius: 16)
    }

    private func icon(_ k: AlertLogEntry.Kind) -> String {
        switch k {
        case .critical:   return "exclamationmark.octagon.fill"
        case .outOfRange: return "arrow.up.arrow.down"
        case .rapid:      return "bolt.heart.fill"
        case .faint:      return "figure.fall"
        case .predictive: return "sparkles"
        case .sleep:      return "moon.zzz.fill"
        case .other:      return "bell.fill"
        }
    }

    private func color(_ k: AlertLogEntry.Kind) -> Color {
        switch k {
        case .critical, .faint: return SP.Color.dangerText
        case .rapid, .outOfRange, .predictive: return SP.Color.caution
        case .sleep, .other: return SP.Color.measure
        }
    }
}

// MARK: - محرر المنبّه

private struct ReminderEditor: View {
    @State var reminder: Reminder
    let isNew: Bool
    @Environment(\.presentationMode) private var presentation

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date() },
            set: {
                reminder.hour = Calendar.current.component(.hour, from: $0)
                reminder.minute = Calendar.current.component(.minute, from: $0)
            }
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("الوقت", selection: time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section(header: Text("النوع")) {
                    Picker("النوع", selection: $reminder.kind) {
                        ForEach(ReminderKind.allCases) { k in
                            Text("\(k.emoji) \(k.title)").tag(k)
                        }
                    }
                }

                Section(header: Text("الملاحظة"), footer: Text("تظهر في الإشعار وقت المنبّه، مثل: تناول دواء الضغط.")) {
                    TextField("مثال: تناول دواء الضغط", text: $reminder.note)
                }

                Section(header: Text("التكرار"), footer: Text("بدون اختيار أيام = مرة واحدة.")) {
                    HStack(spacing: 6) {
                        ForEach(Reminder.weekdayOrder, id: \.self) { d in
                            let on = reminder.weekdays.contains(d)
                            Button {
                                if on { reminder.weekdays.remove(d) } else { reminder.weekdays.insert(d) }
                            } label: {
                                Text(Reminder.shortDayNames[d] ?? "")
                                    .font(.system(size: 11, weight: on ? .bold : .regular))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(on ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle("اهتزاز السوار", isOn: $reminder.vibrateBand)
                }

                if !isNew {
                    Section {
                        Button("حذف المنبّه", role: .destructive) {
                            ReminderStore.shared.delete(reminder)
                            presentation.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationBarTitle(isNew ? "منبّه جديد" : "تعديل المنبّه", displayMode: .inline)
            .navigationBarItems(
                leading: Button("إلغاء") { presentation.wrappedValue.dismiss() },
                trailing: Button("حفظ") {
                    reminder.isEnabled = true
                    ReminderStore.shared.save(reminder)
                    presentation.wrappedValue.dismiss()
                }
            )
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
