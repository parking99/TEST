import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = LocationManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let message = tracker.alarmMessage {
                    VStack(spacing: 8) {
                        Text("🚨 ALARM!").font(.headline)
                        Text(message)
                        Button("Dismiss") { tracker.stopAlarm() }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity).padding().background(.red)
                    .foregroundStyle(.white).clipShape(.rect(cornerRadius: 12))
                }

                TextField("Google Apps Script URL", text: $tracker.scriptURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                VStack(alignment: .leading, spacing: 12) {
                    StatusRow(label: "Status", value: tracker.isTracking ? "Active" : "Stopped", color: tracker.isTracking ? .green : .secondary)
                    StatusRow(label: "Latitude", value: String(format: "%.6f", tracker.latitude))
                    StatusRow(label: "Longitude", value: String(format: "%.6f", tracker.longitude))
                    StatusRow(label: "Last Sync", value: tracker.lastSync)
                }
                .padding().frame(maxWidth: .infinity).background(Color(.systemGray6))
                .clipShape(.rect(cornerRadius: 15))

                if let error = tracker.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(tracker.isTracking ? "Stop Tracking" : "Start Tracking") {
                    tracker.toggleTracking()
                }
                .buttonStyle(.borderedProminent).tint(tracker.isTracking ? .red : .blue)
                .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding().navigationTitle("Location Sync")
            .onAppear { tracker.requestPermissions() }
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    var body: some View {
        HStack { Text("\(label):").bold(); Spacer(); Text(value).foregroundStyle(color).monospacedDigit() }
    }
}

#Preview { ContentView() }
