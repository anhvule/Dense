import SwiftUI
import CompressCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Form {
            Picker("Default preset", selection: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) {
                ForEach(Preset.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Use HEVC (smaller, needs newer players)", isOn: $env.useHEVC)
            Text("Output is saved next to the original as *-compressed. Originals are never modified.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
