import SwiftUI
import CompressCore

@main
struct CompressApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MainView(queue: env.queue).environmentObject(env)
        }
        Settings { SettingsView().environmentObject(env) }
    }
}
