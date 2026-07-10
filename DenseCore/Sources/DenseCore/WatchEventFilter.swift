import Foundation

/// Pure decision logic for folder-watch auto-compress: given a batch of
/// candidate file paths noticed inside a watched folder, decides which of
/// them should become new compression jobs.
///
/// This type does no filesystem access and no timing — the caller (the
/// App-target `FolderWatcher`) owns directory scanning, debounce, and the
/// `seen` set's lifetime across calls. Keeping the decision logic here, with
/// no dependency on Dispatch/FileManager state, is what makes it unit
/// testable without touching disk.
public struct WatchEventFilter {
    /// The user's currently configured output suffix (e.g. "-compressed").
    /// Used as the infinite-loop guard: files this app itself produced carry
    /// this suffix on their filename stem, so they're never re-enqueued.
    public let outputSuffix: String

    public init(outputSuffix: String) {
        self.outputSuffix = outputSuffix
    }

    /// Filters `paths` down to the ones that should be enqueued as jobs.
    ///
    /// Rules applied per path:
    /// - dotfiles (basename starting with `.`) are ignored
    /// - only `FileKind`-supported types (video/image/gif/pdf) are considered
    /// - our own outputs are ignored: if the filename stem (name minus
    ///   extension) ends with `outputSuffix`, it's skipped — this is the
    ///   guard that stops the watcher from recompressing files it just wrote
    /// - paths already present in `seen` (already enqueued or processed by
    ///   the caller in a prior scan) are skipped
    ///
    /// Order of the input is preserved in the output.
    public func jobCandidates(from paths: [String], seen: Set<String>) -> [URL] {
        var result: [URL] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let filename = url.lastPathComponent
            guard !filename.hasPrefix(".") else { continue }
            guard FileKind.of(url) != .unsupported else { continue }
            guard !seen.contains(path) else { continue }
            if !outputSuffix.isEmpty {
                let stem = url.deletingPathExtension().lastPathComponent
                if stem.hasSuffix(outputSuffix) { continue }
            }
            result.append(url)
        }
        return result
    }
}
