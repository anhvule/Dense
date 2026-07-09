import SwiftUI
import DenseCore
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var dropRejected = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 12) {
            header
            DestinationDockView(selected: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) { preset, providers in
                Task {
                    let urls = await loadURLs(from: providers)
                    let accepted = env.handleDrop(urls: urls, preset: preset)
                    dropRejected = accepted == 0 && !urls.isEmpty
                }
            }
            if showAdvanced { AdvancedPanelView().environmentObject(env) }
            if dropRejected {
                Text("Images & PDFs coming soon — v1 is all about video.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Drop videos anywhere — or onto a destination").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.jobs) { FileRowView(job: $0) }.listStyle(.inset)
            }
        }
        .padding(.top, 12)
        .frame(minWidth: 640, minHeight: 460)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await loadURLs(from: providers)
                let accepted = env.handleDrop(urls: urls)
                dropRejected = accepted == 0 && !urls.isEmpty
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dense").font(.headline)
                if !queue.jobs.isEmpty { Text(batchSummary).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !queue.jobs.isEmpty {
                Button("Cancel all") { queue.cancelAll() }
                Button("Clear") { queue.clearFinished() }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                Image(systemName: showAdvanced ? "chevron.up" : "slider.horizontal.3")
            }
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

    /// Loads dropped file URLs from NSItemProviders. The async bridge for
    /// `NSItemProvider.loadItem` is fiddly to chain through `flatMap` (per the
    /// brief's note), so this uses the classic completion-handler form,
    /// wrapped per-provider in a checked continuation and joined with a
    /// TaskGroup. Runs off the MainActor (item loading is I/O); results are
    /// awaited back on the MainActor before touching `env`/state.
    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
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
}
