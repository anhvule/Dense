import SwiftUI
import CompressCore

@main
struct CompressApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Compress \(CompressCore.version)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
