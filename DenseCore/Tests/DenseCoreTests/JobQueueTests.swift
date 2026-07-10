import XCTest
import CoreGraphics
import ImageIO
@testable import DenseCore

@MainActor
final class JobQueueTests: XCTestCase {
    func makeQueue() throws -> JobQueue {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let ffprobe = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe"))
        return JobQueue(compressor: VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                        gifConverter: GIFConverter(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                        imageCompressor: ImageCompressor(ffmpegURL: ffmpeg),
                        audioExtractor: AudioExtractor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe))
    }
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }
    /// 3 pages of the 1600x1200 photo.jpg fixture drawn full-page — an
    /// image-heavy PDF that exercises the .pdf job kind end to end.
    func makeImageHeavyPDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-queue-image-heavy-\(UUID().uuidString).pdf")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fixtureURL("photo.jpg") as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<3 {
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    func waitUntilIdle(_ queue: JobQueue, timeout: TimeInterval = 120) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let busy = queue.jobs.contains { if case .queued = $0.status { return true }
                                             if case .running = $0.status { return true }
                                             return false }
            if !busy { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("queue did not become idle")
    }

    func testBatchRunsAllAndBadFileDoesNotAbort() async throws {
        let queue = try makeQueue()
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad.mp4")
        try Data("junk".utf8).write(to: bad)
        queue.add(urls: [fixtureURL("clip-2s.mp4"), bad, fixtureURL("clip-8s-1080p.mp4")],
                  kind: .compress, options: .init(preset: .small),
                  outputDir: FileManager.default.temporaryDirectory)
        XCTAssertEqual(queue.jobs.count, 3)
        await waitUntilIdle(queue)
        let done = queue.jobs.filter { if case .done = $0.status { return true }; return false }
        let failed = queue.jobs.filter { if case .failed = $0.status { return true }; return false }
        XCTAssertEqual(done.count, 2)
        XCTAssertEqual(failed.count, 1)
    }

    func testAlreadyOptimizedIsSkippedNotFailed() async throws {
        let queue = try makeQueue()
        // compress once, then re-compress the tiny output with a high-bitrate preset → not smaller
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let ffprobe = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe"))
        let first = try await VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
            .compress(input: fixtureURL("clip-2s.mp4"), options: .init(preset: .small),
                      outputDir: FileManager.default.temporaryDirectory) { _ in }
        queue.add(urls: [first.outputURL], kind: .compress, options: .init(preset: .high),
                  outputDir: FileManager.default.temporaryDirectory)
        await waitUntilIdle(queue)
        if case .skippedAlreadyOptimized = queue.jobs[0].status {} else {
            XCTFail("expected skippedAlreadyOptimized, got \(queue.jobs[0].status)")
        }
    }

    func testErrorMessages() {
        XCTAssertEqual(JobQueue.message(for: CompressError.outputNotSmaller), "Already optimized")
        XCTAssertTrue(JobQueue.message(for: CompressError.unreachableTarget(closestMB: 125.1))
            .contains("125"))
        XCTAssertEqual(JobQueue.message(for: CompressError.probeFailed("Password-protected PDF")),
                       "Password-protected PDF — remove the password first")
        XCTAssertEqual(JobQueue.message(for: CompressError.probeFailed("no audio stream")),
                       "No audio track in this file")
        XCTAssertEqual(JobQueue.message(for: CompressError.probeFailed("ffprobe exit 1")),
                       "Not a readable video file")
    }

    func testCancelAllNeverShowsRawFfmpegFailureMessage() async throws {
        let queue = try makeQueue()
        queue.maxConcurrent = 2
        // Three real-encode jobs: two start running immediately (maxConcurrent
        // = 2), one stays queued. cancelAll() is called synchronously right
        // after add(), before this MainActor test body ever suspends, so the
        // still-queued job is guaranteed to be cancelled pre-start; the two
        // running ones get SIGTERMed mid-encode (FFmpegRunner's cancellation
        // handler races that exactly, either surfacing as a thrown
        // CancellationError or as ffmpeg exiting non-zero from the signal —
        // either way Task.isCancelled stays true for the whole execute() call,
        // which is what JobQueue.execute's catch now keys off).
        queue.add(urls: [fixtureURL("clip-8s-1080p.mp4"), fixtureURL("clip-8s-1080p.mp4"),
                         fixtureURL("clip-8s-1080p.mp4")],
                  kind: .compress, options: .init(preset: .small),
                  outputDir: FileManager.default.temporaryDirectory)
        queue.cancelAll()
        await waitUntilIdle(queue)
        for job in queue.jobs {
            if case .failed(let message) = job.status {
                XCTAssertFalse(message.hasPrefix("Compression failed:"),
                                "cancelled job leaked a raw ffmpeg message: \(message)")
            }
        }
        // The job that never left `pending` is cancelled synchronously and
        // deterministically shows "Cancelled".
        if case .failed(let message) = queue.jobs[2].status {
            XCTAssertEqual(message, "Cancelled")
        } else {
            XCTFail("expected the still-queued job to be cancelled, got \(queue.jobs[2].status)")
        }
    }

    @MainActor
    func testTrashOriginalOnSuccess() async throws {
        let queue = try makeQueue()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-me-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: fixtureURL("clip-8s-1080p.mp4"), to: tmp)
        queue.add(urls: [tmp], kind: .compress, options: .init(preset: .small),
                  outputDir: FileManager.default.temporaryDirectory, trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else { XCTFail("expected done") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "original should be in Trash")
    }

    /// Images are replacement-type outputs like compressed videos, so
    /// trash-on-success applies to them too (GIF conversions stay excluded
    /// as derivatives of a kept source).
    @MainActor
    func testTrashOriginalOnSuccessForImageJob() async throws {
        let queue = try makeQueue()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-me-\(UUID().uuidString).jpg")
        try FileManager.default.copyItem(at: fixtureURL("photo.jpg"), to: tmp)
        queue.add(urls: [tmp], kind: .image, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory,
                  imageOptions: ImageOptions(quality: 0.6), trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else {
            XCTFail("expected done, got \(queue.jobs[0].status)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "original should be in Trash")
    }

    func testOptimizeGifJobRunsThroughQueue() async throws {
        let queue = try makeQueue()
        queue.add(urls: [fixtureURL("anim-960x720.gif")], kind: .optimizeGif, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory)
        await waitUntilIdle(queue)
        guard case .done(let result) = queue.jobs[0].status else {
            XCTFail("expected done, got \(queue.jobs[0].status)"); return
        }
        XCTAssertEqual(result.outputURL.pathExtension, "gif")
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
    }

    func testPDFJobRunsThroughQueue() async throws {
        let queue = try makeQueue()
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        queue.add(urls: [input], kind: .pdf, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory, pdfQuality: .balanced)
        await waitUntilIdle(queue)
        guard case .done(let result) = queue.jobs[0].status else {
            XCTFail("expected done, got \(queue.jobs[0].status)"); return
        }
        XCTAssertEqual(result.outputURL.pathExtension, "pdf")
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
    }

    /// PDFs are replacement-type outputs too — trash-on-success applies.
    @MainActor
    func testTrashOriginalOnSuccessForPDFJob() async throws {
        let queue = try makeQueue()
        let source = try makeImageHeavyPDF()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trash-me-\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: source, to: tmp)
        try? FileManager.default.removeItem(at: source)
        queue.add(urls: [tmp], kind: .pdf, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory, pdfQuality: .balanced, trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else {
            XCTFail("expected done, got \(queue.jobs[0].status)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "original should be in Trash")
    }

    /// `addFailed` is for jobs that are already known to have failed before
    /// any compression work is attempted (e.g. a deep-link path that doesn't
    /// exist) — it must append a `.failed` row synchronously, without ever
    /// touching `pending`/`pump()`.
    func testAddFailedAppendsFailedJobSynchronously() throws {
        let queue = try makeQueue()
        let missing = URL(fileURLWithPath: "/nonexistent/path/clip.mp4")
        queue.addFailed(url: missing, message: "File not found")
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs[0].input, missing)
        guard case .failed(let message) = queue.jobs[0].status else {
            XCTFail("expected failed, got \(queue.jobs[0].status)"); return
        }
        XCTAssertEqual(message, "File not found")
    }

    func testExtractAudioJobRunsThroughQueue() async throws {
        let queue = try makeQueue()
        queue.add(urls: [fixtureURL("clip-2s.mp4")], kind: .extractAudio, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory)
        await waitUntilIdle(queue)
        guard case .done(let result) = queue.jobs[0].status else {
            XCTFail("expected done, got \(queue.jobs[0].status)"); return
        }
        XCTAssertTrue(["mp3", "m4a"].contains(result.outputURL.pathExtension))
    }

    /// Extracted audio is a derivative of a kept source (like a video→GIF
    /// conversion), not a replacement output, so trash-on-success must NOT
    /// apply to it.
    @MainActor
    func testTrashOriginalOnSuccessDoesNotApplyToExtractAudioJob() async throws {
        let queue = try makeQueue()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-me-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: fixtureURL("clip-2s.mp4"), to: tmp)
        queue.add(urls: [tmp], kind: .extractAudio, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory, trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else {
            XCTFail("expected done, got \(queue.jobs[0].status)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path), "original must be kept, not trashed")
    }

    /// Optimized gifs are a replacement-type output (the optimized gif
    /// stands in for the original, same as a compressed image), so
    /// trash-on-success applies to them too.
    @MainActor
    func testTrashOriginalOnSuccessForOptimizeGifJob() async throws {
        let queue = try makeQueue()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-me-\(UUID().uuidString).gif")
        try FileManager.default.copyItem(at: fixtureURL("anim-960x720.gif"), to: tmp)
        queue.add(urls: [tmp], kind: .optimizeGif, options: .init(preset: .balanced),
                  outputDir: FileManager.default.temporaryDirectory, trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else {
            XCTFail("expected done, got \(queue.jobs[0].status)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "original should be in Trash")
    }
}
