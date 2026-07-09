import XCTest
@testable import DenseCore

final class WatchEventFilterTests: XCTestCase {
    func testSuffixLoopGuardSkipsOwnOutputs() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch/movie-compressed.mp4", "/tmp/watch/movie.mp4"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(result.map(\.lastPathComponent), ["movie.mp4"])
    }

    func testSuffixCheckOnlyLooksAtFilenameStem() {
        // Confirms the guard checks the filename stem, not the whole path —
        // a directory named "-compressed" shouldn't affect a file that
        // doesn't itself carry the suffix.
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch-compressed/movie.mp4"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(result.map(\.lastPathComponent), ["movie.mp4"])
    }

    func testDotfilesAreIgnored() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch/.DS_Store", "/tmp/watch/.hidden.mp4", "/tmp/watch/visible.mp4"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(result.map(\.lastPathComponent), ["visible.mp4"])
    }

    func testUnsupportedTypesAreIgnored() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch/notes.txt", "/tmp/watch/archive.zip", "/tmp/watch/clip.mov"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(result.map(\.lastPathComponent), ["clip.mov"])
    }

    func testSeenSetDedupesAlreadyProcessedPaths() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch/a.mp4", "/tmp/watch/b.mp4"]
        let result = filter.jobCandidates(from: paths, seen: ["/tmp/watch/a.mp4"])
        XCTAssertEqual(result.map(\.lastPathComponent), ["b.mp4"])
    }

    func testMixedBatchAppliesAllRulesTogether() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = [
            "/tmp/watch/.DS_Store",               // dotfile
            "/tmp/watch/readme.txt",               // unsupported
            "/tmp/watch/output-compressed.mp4",    // our own output
            "/tmp/watch/already-seen.png",         // in seen set
            "/tmp/watch/new-video.mov",            // accepted
            "/tmp/watch/new-image.jpg",            // accepted
        ]
        let result = filter.jobCandidates(from: paths, seen: ["/tmp/watch/already-seen.png"])
        XCTAssertEqual(result.map(\.lastPathComponent), ["new-video.mov", "new-image.jpg"])
    }

    func testEmptyOutputSuffixDoesNotMatchEverything() {
        // Guards against a degenerate `hasSuffix("")` == true for every
        // string, which would silently drop all files if outputSuffix were
        // ever configured empty.
        let filter = WatchEventFilter(outputSuffix: "")
        let paths = ["/tmp/watch/movie.mp4"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(result.map(\.lastPathComponent), ["movie.mp4"])
    }

    func testGifPdfAndImageExtensionsAreAllAccepted() {
        let filter = WatchEventFilter(outputSuffix: "-compressed")
        let paths = ["/tmp/watch/a.gif", "/tmp/watch/b.pdf", "/tmp/watch/c.png", "/tmp/watch/d.heic"]
        let result = filter.jobCandidates(from: paths, seen: [])
        XCTAssertEqual(Set(result.map(\.lastPathComponent)), Set(paths.map { URL(fileURLWithPath: $0).lastPathComponent }))
    }
}
