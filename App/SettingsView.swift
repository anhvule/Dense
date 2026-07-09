import SwiftUI
import DenseCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Form {
            Picker("Default preset", selection: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) {
                ForEach(Preset.allCases) { Text($0.displayName).tag($0) }
            }
            Text("All encoding options live in the main window's advanced panel.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
