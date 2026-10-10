//
//  SecurityPassWidget.swift
//  SecurityPassWidget — امتداد شاشة القفل
//
//  النشاط المباشر: النبض والأكسجين والحالة، والبطاقة الطبية ليراها المسعف دون فتح الجوال.
//

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct SecurityPassWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthLiveActivityWidget()
    }
}

struct HealthLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HealthActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.0, green: 0.07, blue: 0.22))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.heartRate)", systemImage: "heart.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("\(context.state.spo2)%", systemImage: "lungs.fill")
                        .foregroundColor(.cyan)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.statusMessage)
                            .font(.caption)
                            .foregroundColor(context.state.isCritical ? .red : .primary)
                            .lineLimit(2)
                        if !context.state.bloodType.isEmpty || !context.state.emergencyPhone.isEmpty {
                            Text(medicalLine(context.state))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundColor(.red)
            } compactTrailing: {
                Text("\(context.state.heartRate)")
            } minimal: {
                Image(systemName: context.state.isCritical ? "exclamationmark.triangle.fill" : "heart.fill")
                    .foregroundColor(.red)
            }
        }
    }

    private func medicalLine(_ s: HealthActivityAttributes.ContentState) -> String {
        [s.bloodType.isEmpty ? nil : "فصيلة \(s.bloodType)",
         s.emergencyPhone.isEmpty ? nil : "طوارئ \(s.emergencyPhone)"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - شاشة القفل

private struct LockScreenView: View {
    let state: HealthActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: state.isCritical ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                    .foregroundColor(state.isCritical ? .red : .green)
                Text(state.statusMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(state.isCritical ? .red : .white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Label("\(state.heartRate)", systemImage: "heart.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Label("\(state.spo2)%", systemImage: "lungs.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }

            if state.hasMedicalCard {
                Divider().background(Color.white.opacity(0.3))
                HStack(spacing: 6) {
                    Image(systemName: "cross.case.fill").foregroundColor(.red)
                    Text("بطاقة طوارئ طبية")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    row("فصيلة الدم", state.bloodType)
                    row("الأمراض", state.conditions)
                    row("الحساسية", state.allergies)
                    row("رقم الطوارئ", state.emergencyPhone)
                }
            }
        }
        .padding(14)
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title + ":")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
    }
}
