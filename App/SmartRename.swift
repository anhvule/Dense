// App/SmartRename.swift
import Foundation
import Vision

/// On-device image classification for suggesting clearer output filenames —
/// e.g. `beach-dog-2026-07-09.jpg` instead of `IMG_4821-compressed.jpg`.
///
/// Runs entirely locally via Vision's `VNClassifyImageRequest`
/// (available macOS 10.15+, well under Dense's 13.0 deployment target — no
/// availability guard needed). No network calls, nothing leaves the Mac.
///
/// Applies ONLY to the OUTPUT file of a successful `.image` compression job
/// (wired in `AppEnvironment`, never in `DenseCore`/`JobQueue` — see that
/// file's `wireBatchCompletionTracking` for why this is an App-level,
/// post-completion hook rather than a `JobQueue` callback: the queue already
/// exposes `Job.$status` as a Combine publisher, and `AppEnvironment`
/// already subscribes to every job's status transitions for the confetti
/// feature, so piggybacking a second observation there is simpler than
/// adding a new hook type to a DenseCore class that has no Vision/App
/// dependency today). Never touches the original input file.
///
/// Failure is always silent: a classification below confidence threshold, a
/// Vision error, or a filesystem rename failure all just leave the original
/// output filename in place — this is a cosmetic nicety, never something
/// that should surface as a job error.
enum SmartRename {
    /// Labels at or below this confidence are ignored.
    static let confidenceThreshold: Float = 0.3
    /// At most this many labels are used to build the filename stem.
    static let maxLabels = 2

    /// Classifies `outputURL` and renames it in place (same directory) to
    /// `<label1>-<label2>-<yyyy-MM-dd>.<ext>`, resolving collisions by
    /// appending `-2`, `-3`, etc. Returns the resulting URL — `outputURL`
    /// itself, unchanged, if classification found nothing above threshold,
    /// Vision failed, or the rename failed for any reason.
    static func renameIfPossible(outputURL: URL, date: Date = Date()) async -> URL {
        guard let newStem = await classify(imageURL: outputURL, date: date) else { return outputURL }
        return applyRename(outputURL: outputURL, newStem: newStem)
    }

    /// Pure label→filename-stem formatting: lowercases, strips anything
    /// that isn't a letter/digit into a hyphen, collapses repeats, dedupes
    /// case-insensitively, keeps the top `maxLabels`, and appends a
    /// `yyyy-MM-dd` date component. Returns `nil` if no label survives
    /// sanitization (e.g. every label was empty/punctuation-only).
    static func stem(fromLabels labels: [String], date: Date) -> String? {
        var seen = Set<String>()
        var parts: [String] = []
        for raw in labels {
            let cleaned = sanitize(raw)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            parts.append(cleaned)
            if parts.count == maxLabels { break }
        }
        guard !parts.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        parts.append(formatter.string(from: date))
        return parts.joined(separator: "-")
    }

    private static func sanitize(_ label: String) -> String {
        let lowered = label.lowercased()
        let hyphenated = String(lowered.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return hyphenated
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    /// Runs `VNClassifyImageRequest` off the main actor (Vision's `perform`
    /// is synchronous/CPU-bound) and returns the top labels above
    /// `confidenceThreshold`, highest confidence first, formatted into a
    /// filename stem. `VNImageRequestHandler` is created fresh per call, so
    /// this is safe to run detached.
    private static func classify(imageURL: URL, date: Date) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            guard let observations = request.results else { return nil }
            let labels = observations
                .filter { $0.confidence > confidenceThreshold }
                .sorted { $0.confidence > $1.confidence }
                .map(\.identifier)
            return stem(fromLabels: labels, date: date)
        }.value
    }

    /// Renames `outputURL` to `<newStem>.<ext>` in the same directory,
    /// appending `-2`, `-3`, … on collision with an existing, *different*
    /// file. Returns `outputURL` unchanged (no-op) if the computed name
    /// already matches it, or if the actual filesystem move fails.
    private static func applyRename(outputURL: URL, newStem: String) -> URL {
        let ext = outputURL.pathExtension
        let dir = outputURL.deletingLastPathComponent()
        func named(_ stem: String) -> URL {
            dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
        }
        var candidate = named(newStem)
        var suffix = 2
        while candidate != outputURL, FileManager.default.fileExists(atPath: candidate.path) {
            candidate = named("\(newStem)-\(suffix)")
            suffix += 1
        }
        guard candidate != outputURL else { return outputURL }
        do {
            try FileManager.default.moveItem(at: outputURL, to: candidate)
            return candidate
        } catch {
            return outputURL
        }
    }
}
