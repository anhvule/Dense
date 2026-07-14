// App/QueuePaneView.swift
import SwiftUI
import DenseCore
import UniformTypeIdentifiers

/// The detail pane of the split view: native toolbar (via `.toolbar`),
/// advanced panel, rejection banner, job list (or destination-aware empty
/// state), and the whole-pane file drop target. Destination selection lives
/// in `SidebarView`; this pane reacts to whatever `env.destination` currently
/// is, and tapping a row selects it (`env.selectedJobID`) and opens the
/// inspector (`env.inspectorPresented`) — the inspector view itself ships in
/// Task 7.
struct QueuePaneView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var showAdvanced = false

    var body: some View {
        Group {
            if queue.jobs.isEmpty { emptyState } else { jobList }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                if showAdvanced {
                    AdvancedPanelView().environmentObject(env)
                    WatchedFoldersView().environmentObject(env)
                }
                if let banner = env.rejectionBanner {
                    Text(banner)
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(Capsule().fill(.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
        }
        .navigationTitle(env.destination.title)
        .navigationSubtitle(batchSummary)
        .toolbar { toolbarContent }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await loadDroppedURLs(from: providers)
                env.handleGUIDrop(urls: urls)
            }
            return true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
            Text("Drop videos or PDFs")
                .font(.title3.weight(.semibold))
            Text("They'll be sized for \(env.destination.title) — \(env.destination.subtitle)")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(Color.primary.opacity(0.15)))
        .padding(14)
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(queue.jobs) { job in
                    FileRowView(job: job, isSelected: env.selectedJobID == job.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            env.selectedJobID = job.id
                            env.inspectorPresented = true
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.jobs.count)
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if !queue.jobs.isEmpty {
                Button("Cancel All") { queue.cancelAll() }
                Button("Clear") { queue.clearFinished() }
            }
            Button {
                env.setDropZoneEnabled(!env.dropZoneEnabled)
            } label: { Image(systemName: "circle.dashed.inset.filled") }
                .foregroundStyle(env.dropZoneEnabled ? Theme.accent : .secondary)
                .help(env.dropZoneEnabled ? "Hide floating drop zone" : "Show floating drop zone")
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: { Image(systemName: "slider.horizontal.3") }
                .help("Advanced options")
            Button { env.inspectorPresented.toggle() } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Show preview inspector")
        }
    }

    private var batchSummary: String {
        guard !queue.jobs.isEmpty else { return "" }
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
/// — the queue pane's whole-pane drop, `SidebarView`'s per-destination drop,
/// and the floating `DropZonePanel` — so all three resolve dropped items
/// identically.
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
