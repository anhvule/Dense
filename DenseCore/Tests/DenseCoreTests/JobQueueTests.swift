import XCTest
@testable import DenseCore

@MainActor
final class JobQueueTests: XCTestCase {
    func makeQueue() throws -> JobQueue {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let ffprobe = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe"))
        return JobQueue(compressor: VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                        gifConverter: GIFConverter(ffmpegURL: ffmpeg, ffprobeURL: ffprobe))
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
}
