// App/FolderWatcher.swift
import Foundation
import DenseCore

/// Watches a set of user-configured folders and auto-enqueues new files for
/// compression as they arrive.
///
/// Per folder: a `DispatchSourceFileSystemObject` on an `O_EVTONLY` fd fires
/// on `.write` (any change to the directory's contents). Each event
/// restarts a 2s debounce timer (via a generation counter — a later event
/// invalidates any scan already in flight for an earlier one) before the
/// folder is actually rescanned, so a burst of Finder-copy events collapses
/// into one scan.
///
/// This class owns *only* the watcher wiring/timing; the actual
/// accept/reject decision per candidate path is delegated to
/// `WatchEventFilter` (pure, unit-tested in DenseCore). That split is what
/// lets this genuinely hard-to-unit-test AppKit/Dispatch machinery stay thin
/// — there's no decision logic duplicated here to get out of sync.
///
/// Not testable via `swift test` (this file lives in the App target, which
/// isn't part of the SwiftPM `DenseCore` package) — verified by build +
/// launch + a manual scripted watch check instead. See the F6 report for
/// what that check covered.
@MainActor
final class FolderWatcher {
    private struct Target {
        let id: UUID
        let path: String
        var preset: Preset
    }

    /// Called with newly-accepted, size-stable files and the preset
    /// configured for the folder they arrived in. Wired by `AppEnvironment`
    /// to `handleDrop(urls:preset:)`.
    var onNewFiles: (_ urls: [URL], _ preset: Preset) -> Void = { _, _ in }

    /// Kept in sync with the user's current output-suffix setting so the
    /// loop guard (skip our own outputs) always reflects the live suffix,
    /// even if the user changes it after folders are already being watched.
    var outputSuffix: String = "-compressed"

    private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
    private var seenByFolder: [UUID: Set<String>] = [:]
    private var generationByFolder: [UUID: Int] = [:]
    private var targets: [UUID: Target] = [:]

    /// Applies a config edit *differentially* (via the pure, unit-tested
    /// `WatchReconfigurePlan`): watchers whose id/path/enabled state didn't
    /// change are left completely untouched — their DispatchSource, `seen`
    /// snapshot, and debounce generation all survive, so editing folder B's
    /// preset can never drop a file that's mid-arrival in folder A (a full
    /// teardown would re-seed A's `seen` with the half-arrived file in it,
    /// permanently skipping it). Preset-only changes on a kept watcher are
    /// applied in place. Only removed/disabled/path-changed folders are
    /// stopped, and only genuinely new ones are started (and freshly
    /// seeded). Folders that are disabled or whose path no longer resolves
    /// to a directory are silently skipped here (the UI surfaces the
    /// missing-folder case with a warning icon; this layer just never
    /// starts a source for it, no crash).
    func reconfigure(folders: [WatchedFolder]) {
        let plan = WatchReconfigurePlan.plan(current: targets.mapValues(\.path), desired: folders)
        for id in plan.stop { stop(id: id) }
        for id in plan.keep {
            // Preset may have changed even though the watcher survives —
            // update it in place so the next enqueue uses the new value.
            if let folder = folders.first(where: { $0.id == id }),
               let preset = Preset(rawValue: folder.presetRaw) {
                targets[id]?.preset = preset
            }
        }
        for folder in plan.start {
            guard let preset = Preset(rawValue: folder.presetRaw) else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            start(id: folder.id, path: folder.path, preset: preset)
        }
    }

    func stopAll() {
        for id in Array(sources.keys) { stop(id: id) }
    }

    private func stop(id: UUID) {
        sources[id]?.cancel()
        sources[id] = nil
        seenByFolder[id] = nil
        generationByFolder[id] = nil
        targets[id] = nil
    }

    private func start(id: UUID, path: String, preset: Preset) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        targets[id] = Target(id: id, path: path, preset: preset)
        generationByFolder[id] = 0
        // Seed `seen` with everything already in the folder at watch-start
        // so pre-existing files are never mistaken for new arrivals — only
        // files that show up *after* this point get compressed.
        //
        // DESIGNED BEHAVIOR, not a bug: this seeding also runs fresh on
        // every app launch, so files that were added to a watched folder
        // while the app was closed are NOT auto-compressed at launch. That
        // is deliberate — it prevents a surprise mass-compression of a
        // backlog (imagine pointing this at ~/Downloads and coming back
        // from a week off). Only arrivals observed by a live watcher are
        // ever enqueued.
        seenByFolder[id] = Set(currentContents(of: path))

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleScan(id: id)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        sources[id] = source
    }

    private func currentContents(of path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.map { path + "/" + $0 } ?? []
    }

    private func scheduleScan(id: UUID) {
        generationByFolder[id, default: 0] += 1
        let generation = generationByFolder[id]!
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.performScan(id: id, expectedGeneration: generation)
        }
    }

    private func performScan(id: UUID, expectedGeneration: Int) async {
        // A later write event bumped the generation while we were sleeping —
        // that newer task's own debounce will handle the rescan, so bail.
        guard generationByFolder[id] == expectedGeneration else { return }
        guard let target = targets[id] else { return }

        let seen = seenByFolder[id] ?? []
        let contents = currentContents(of: target.path)
        let filter = WatchEventFilter(outputSuffix: outputSuffix)
        let candidates = filter.jobCandidates(from: contents, seen: seen)
        guard !candidates.isEmpty else { return }

        var stable: [URL] = []
        for url in candidates where await isSizeStable(url) {
            stable.append(url)
        }
        guard !stable.isEmpty else { return }

        // Mark stable candidates as seen even if a straggler among the
        // original `candidates` wasn't stable yet — it'll be picked up on
        // whatever future .write event marks its next change (e.g. the copy
        // finishing writes more bytes, which fires another event).
        seenByFolder[id, default: []].formUnion(stable.map(\.path))
        onNewFiles(stable, target.preset)
    }

    /// Heuristic for "has this file finished being written?": stat it, wait
    /// 1s, stat again, and only treat it as ready when the size hasn't
    /// changed. This is a simple, best-effort guard against enqueueing a
    /// half-copied file (e.g. mid Finder-copy or mid-download) — it is not
    /// bulletproof (a copy that stalls for exactly this window would pass
    /// prematurely), but it matches the brief's ask for a "simple heuristic"
    /// and covers the common case without pulling in FSEvents-level APIs.
    private func isSizeStable(_ url: URL) async -> Bool {
        guard let size1 = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 else {
            return false
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let size2 = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 else {
            return false
        }
        return size1 == size2
    }
}
