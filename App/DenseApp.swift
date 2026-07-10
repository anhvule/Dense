import SwiftUI
import DenseCore
import Sparkle

@main
struct DenseApp: App {
    @StateObject private var env = AppEnvironment()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            Group {
                if case .trialExpired = env.licenseStatus {
                    LicenseGateView().environmentObject(env)
                        .background(GlassBackground().ignoresSafeArea())
                } else {
                    MainView(queue: env.queue).environmentObject(env)
                        .overlay(alignment: .bottom) {
                            if case .trial(let days) = env.licenseStatus {
                                Text("Trial — \(days) day\(days == 1 ? "" : "s") left")
                                    .font(.caption).padding(6)
                            }
                        }
                }
            }
            // Attached above the gate/main branch so dense:// links always
            // reach the handler regardless of which branch is showing
            // (handleDeepLink itself ignores links while the trial is
            // expired). Assigned unconditionally: a successful link returns
            // nil, which clears any stale rejection banner.
            .onOpenURL { url in
                env.rejectionBanner = env.handleDeepLink(url: url)
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updaterController.checkForUpdates(nil) }
            }
        }
        .windowStyle(.hiddenTitleBar)
        Settings { SettingsView().environmentObject(env) }
    }
}
