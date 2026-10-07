import WidgetKit
import SwiftUI
import ActivityKit

// انسخ هذا الملف وضعه داخل الـ Widget Extension الجديد الذي ستنشئه من Xcode
// File -> New -> Target -> Widget Extension (مع تفعيل خيار Include Live Activity)

@available(iOS 16.1, *)
struct HealthLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HealthActivityAttributes.self) { context in
            // Lock screen / Banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(context.state.isCritical ? .red : .green)
                    Text("المراقبة الميدانية - \(context.attributes.employeeID)")
                        .font(.headline)
                    Spacer()
                    Text("النبض: \(context.state.heartRate)")
                        .font(.subheadline.bold())
                }
                
                HStack {
                    Text("الحالة: \(context.state.statusMessage)")
                        .font(.caption)
                        .foregroundColor(context.state.isCritical ? .red : .secondary)
                    Spacer()
                    Text("O₂: \(context.state.spo2)%")
                        .font(.subheadline.bold())
                }
            }
            .padding()
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.heartRate)", systemImage: "heart.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("\(context.state.spo2)%", systemImage: "lungs.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusMessage)
                        .font(.caption)
                        .foregroundColor(context.state.isCritical ? .red : .primary)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundColor(.red)
            } compactTrailing: {
                Text("\(context.state.heartRate)")
            } minimal: {
                Image(systemName: "heart.fill").foregroundColor(.red)
            }
        }
    }
}
