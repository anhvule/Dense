import SwiftUI
import CompressCore

struct LicenseGateView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var keyInput = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Trial expired").font(.title2).bold()
            Text("Get a license for $29 (launch price $19) — one-time, yours forever.")
            Link("Buy License", destination: URL(string: "https://REPLACE-AT-LAUNCH.lemonsqueezy.com/checkout")!)
                .buttonStyle(.borderedProminent)
            HStack {
                TextField("Paste license key", text: $keyInput).textFieldStyle(.roundedBorder)
                Button(busy ? "Activating…" : "Activate") { activate() }.disabled(busy || keyInput.isEmpty)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func activate() {
        busy = true; error = nil
        Task {
            do {
                let instanceID = try await LicenseClient()
                    .activate(key: keyInput, instanceName: Host.current().localizedName ?? "Mac")
                env.licenseState.recordActivation(key: keyInput, instanceID: instanceID)
                env.refreshLicenseStatus()
            } catch {
                self.error = "Activation failed — check the key and your connection."
            }
            busy = false
        }
    }
}
