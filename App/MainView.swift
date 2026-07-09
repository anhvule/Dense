import SwiftUI
import CompressCore
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var dropRejected = false

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
        HStack {
            Text("Compress").font(.headline)
            Spacer()
            if !queue.jobs.isEmpty { Button("Clear") { queue.clearFinished() } }
        }
        .padding(.horizontal, 14)
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
