import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = LocationManager()
    @State private var showAdvancedSettings = false

    // Color definitions matching the Android GBS theme
    private let darkNavy = Color(red: 13/255, green: 27/255, blue: 42/255)
    private let cardNavy = Color(red: 27/255, green: 38/255, blue: 59/255)
    private let accentBlue = Color(red: 65/255, green: 90/255, blue: 119/255)
    private let textGray = Color(red: 119/255, green: 141/255, blue: 169/255)

    var body: some View {
        ZStack {
            // Background
            darkNavy.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer().frame(height: 10)

                // Header
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(tracker.isAlarmActive ? .red : accentBlue)
                        .font(.title2)
                    
                    Text("GBS SYSTEM")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                // Status Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(tracker.isTracking ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(tracker.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(tracker.isAlarmActive ? .red : .white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(tracker.isAlarmActive ? Color.red.opacity(0.2) : cardNavy)
                .cornerRadius(20)

                // Device Identity TextField
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device Identity")
                        .font(.footnote)
                        .foregroundColor(textGray)
                    
                    TextField("", text: $tracker.deviceId)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .padding(12)
                        .background(cardNavy)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accentBlue, lineWidth: 1)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)

                // Monitoring Card
                VStack(spacing: 12) {
                    InfoRow(label: "Current Lat", value: String(format: "%.5f", tracker.latitude))
                    InfoRow(label: "Current Lng", value: String(format: "%.5f", tracker.longitude))
                    InfoRow(label: "Current Speed", value: String(format: "%.1f km/h", tracker.speed))
                    
                    Divider().background(accentBlue)
                    
                    InfoRow(label: "Last Sync", value: tracker.lastSync)
                }
                .padding(20)
                .background(cardNavy)
                .cornerRadius(16)
                .padding(.horizontal)

                if let error = tracker.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                // Collapsible Advanced Settings (URL)
                VStack {
                    Button(action: {
                        withAnimation {
                            showAdvancedSettings.toggle()
                        }
                    }) {
                        HStack {
                            Text("Advanced Settings")
                                .font(.footnote)
                                .foregroundColor(textGray)
                            Image(systemName: showAdvancedSettings ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(textGray)
                        }
                    }
                    
                    if showAdvancedSettings {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Google Apps Script URL")
                                .font(.caption2)
                                .foregroundColor(textGray)
                            
                            TextField("", text: $tracker.scriptURL)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                                .padding(10)
                                .background(cardNavy)
                                .cornerRadius(8)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        .padding()
                        .background(cardNavy.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Large Action Toggle Button
                Button(action: {
                    tracker.toggleTracking()
                }) {
                    Text(tracker.isTracking ? "STOP MONITORING" : "START TRACKING")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(tracker.isTracking ? Color.red : accentBlue)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            tracker.requestPermissions()
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(Color(red: 119/255, green: 141/255, blue: 169/255))
                .font(.subheadline)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

#Preview {
    ContentView()
}
