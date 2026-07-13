import SwiftUI
import DenseCore

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            QueuePaneView(queue: queue)
        }
        .inspector(isPresented: $env.inspectorPresented) {
            PreviewInspectorView()
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .background(GlassBackground().ignoresSafeArea())
        .frame(minWidth: 760, minHeight: 480)
        .overlay(ConfettiView(trigger: env.confettiTrigger).allowsHitTesting(false))
    }
}
