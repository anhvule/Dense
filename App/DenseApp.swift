import SwiftUI
import DenseCore
import Sparkle

@main
struct DenseApp: App {
    @StateObject private var env = AppEnvironment()
    /// Guards against a real, previously-hit hang: with a placeholder
    /// `SUFeedURL` (and the matching placeholder `SUPublicEDKey`, both
    /// swapped together for the real values at launch time — see
    /// `Scripts/release.sh`), Sparkle's `startUpdater:` fails
    /// `checkIfConfiguredProperlyAndRequireFeedURL:` (invalid EdDSA public
    /// key) and `SPUStandardUpdaterController` responds by scheduling a
    /// `NSAlert.runModal()` ~1s later — a synchronous, blocking modal that
    /// hung multiple F6/F8/F9 verification runs on a dev build that never
    /// had real Sparkle keys configured. Passing `startingUpdater: false`
    /// still constructs the `SPUUpdater` (so `checkForUpdates(_:)` below
    /// stays safe to call — Sparkle logs "hasn't been started yet" and
    /// returns, it does not crash or block) but skips the config check that
    /// triggers the alert. This is a permanent guard, not a debug
    /// workaround: it also correctly disables auto-updates for anyone who
    /// somehow ships a build before real Sparkle keys are in place, rather
    /// than the app silently pretending updates work.
    ///
    /// Note for the launch-day "grep for the placeholder sentinel returns
    /// nothing" check (see the launch playbook): the string literal below is
    /// a permanent runtime detection value, not a placeholder awaiting
    /// replacement — it will always match that grep and is expected to.
    private static let launchPlaceholderSentinel = "REPLACE-AT-LAUNCH"
    private static let updaterShouldStart: Bool = {
        guard let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              !feedURL.contains(launchPlaceholderSentinel) else {
            NSLog("Dense: Sparkle auto-updates disabled — SUFeedURL still has its pre-launch " +
                  "placeholder domain. Auto-updates activate once a real feed URL (and matching " +
                  "EdDSA key) replace it at launch.")
            return false
        }
        return true
    }()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: DenseApp.updaterShouldStart, updaterDelegate: nil, userDriverDelegate: nil)

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
                // `checkForUpdates(_:)` is safe to call even when the
                // updater was never started (Sparkle logs and no-ops rather
                // than crashing/blocking — see `updaterShouldStart` above);
                // `.disabled` here is purely so a placeholder-feed build
                // doesn't present a menu item that silently does nothing.
                Button("Check for Updates…") { updaterController.checkForUpdates(nil) }
                    .disabled(!Self.updaterShouldStart)
            }
        }
        .windowStyle(.hiddenTitleBar)
        Settings { SettingsView().environmentObject(env) }
    }
}
