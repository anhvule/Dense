import SwiftUI
import DenseCore
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 12) {
            header
            DestinationDockView(selected: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) { preset, providers in
                Task {
                    let urls = await loadDroppedURLs(from: providers)
                    let accepted = env.handleDrop(urls: urls, preset: preset)
                    env.rejectionBanner = (accepted == 0 && !urls.isEmpty) ? "That file type isn't supported yet." : nil
                }
            }
            if showAdvanced {
                AdvancedPanelView().environmentObject(env)
                WatchedFoldersView().environmentObject(env)
            }
            if let rejectionBanner = env.rejectionBanner {
                Text(rejectionBanner)
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }
            if queue.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 40, weight: .light))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(Theme.accent)
                    Text("Drop videos anywhere — or onto a destination")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Color.primary.opacity(0.15)))
                .padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queue.jobs) { FileRowView(job: $0) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.jobs.count)
                }
            }
        }
        .padding(.top, 6)
        .background(GlassBackground().ignoresSafeArea())
        .frame(minWidth: 640, minHeight: 460)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await loadDroppedURLs(from: providers)
                let accepted = env.handleDrop(urls: urls)
                env.rejectionBanner = (accepted == 0 && !urls.isEmpty) ? "That file type isn't supported yet." : nil
            }
            return true
        }
        .overlay(ConfettiView(trigger: env.confettiTrigger).allowsHitTesting(false))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dense").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                if !queue.jobs.isEmpty {
                    Text(batchSummary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            if !queue.jobs.isEmpty {
                Button("Cancel all") { queue.cancelAll() }.buttonStyle(.borderless)
                Button("Clear") { queue.clearFinished() }.buttonStyle(.borderless)
            }
            Button {
                env.setDropZoneEnabled(!env.dropZoneEnabled)
            } label: {
                Image(systemName: "circle.dashed.inset.filled")
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .foregroundStyle(env.dropZoneEnabled ? Theme.accent : .secondary)
            .help(env.dropZoneEnabled ? "Hide floating drop zone" : "Show floating drop zone")
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                Image(systemName: showAdvanced ? "chevron.up" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .help("Advanced options")
        }
        .padding(.horizontal, 14)
    }

    private var batchSummary: String {
        let done = queue.jobs.compactMap { if case .done(let r) = $0.status { return r } else { return nil } }
        let inB = done.reduce(Int64(0)) { $0 + $1.inputBytes }
        let outB = done.reduce(Int64(0)) { $0 + $1.outputBytes }
        let saved = inB - outB
        guard inB > 0, saved > 0 else { return "\(queue.jobs.count) file\(queue.jobs.count == 1 ? "" : "s")" }
        let pct = Int((1 - Double(outB) / Double(inB)) * 100)
        return "\(queue.jobs.count) files · saved \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) (−\(pct)%)"
    }

}

/// Loads dropped file URLs from NSItemProviders. The async bridge for
/// `NSItemProvider.loadItem` is fiddly to chain through `flatMap` (per the
/// brief's note), so this uses the classic completion-handler form, wrapped
/// per-provider in a checked continuation and joined with a TaskGroup. Runs
/// off the MainActor (item loading is I/O); results are awaited back on the
/// MainActor before touching `env`/state.
///
/// Shared by every drop target that routes into `AppEnvironment.handleDrop`
/// — the main window's background drop (`MainView`), the destination dock
/// (`DestinationDockView`), and the floating `DropZonePanel` — so all three
/// resolve dropped items identically.
func loadDroppedURLs(from providers: [NSItemProvider]) async -> [URL] {
    let typeIdentifier = UTType.fileURL.identifier
    return await withTaskGroup(of: URL?.self) { group in
        for provider in providers {
            group.addTask {
                guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
                return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            continuation.resume(returning: url)
                        } else if let url = item as? URL {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
        var results: [URL] = []
        for await url in group {
            if let url { results.append(url) }
        }
        return results
    }
}
