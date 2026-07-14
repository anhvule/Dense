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

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dense bundles FFmpeg 7.1, licensed under the GPL v2 or later, and runs it as a separate process.")
                    Link("See licenses and source links", destination: URL(string: "https://REPLACE-AT-LAUNCH.example/licenses.html")!)
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
