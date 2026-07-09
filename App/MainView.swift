import SwiftUI
import CompressCore
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var dropRejected = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Preset", selection: Binding(
                    get: { env.defaultPreset },
                    set: { env.defaultPreset = $0 })) {
                    ForEach(Preset.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)
                Toggle("GIF", isOn: $env.gifMode).toggleStyle(.button)
                Spacer()
                if !queue.jobs.isEmpty {
                    Button("Clear") { queue.clearFinished() }
                }
            }
            .padding(12)

            if dropRejected && !queue.jobs.isEmpty {
                Text("Images & PDFs coming soon — v1 is all about video.")
                    .font(.caption).foregroundStyle(.orange).padding(.bottom, 4)
            }

            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 44))
                    Text("Drop videos here").font(.title3)
                    Text(dropRejected ? "Images & PDFs coming soon — v1 is all about video." : "MP4, MOV & more")
                        .foregroundStyle(dropRejected ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.jobs) { QueueRowView(job: $0) }
                    .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await Self.loadURLs(from: providers)
                let accepted = env.handleDrop(urls: urls)
                dropRejected = accepted == 0 && !urls.isEmpty
            }
            return true
        }
    }

    /// Loads dropped file URLs from NSItemProviders. The async bridge for
    /// `NSItemProvider.loadItem` is fiddly to chain through `flatMap` (per the
    /// brief's note), so this uses the classic completion-handler form,
    /// wrapped per-provider in a checked continuation and joined with a
    /// TaskGroup. Runs off the MainActor (item loading is I/O); results are
    /// awaited back on the MainActor in `body` before touching `env`/state.
    private static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
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
