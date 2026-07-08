import XCTest
@testable import CompressCore

final class ProgressParserTests: XCTestCase {
    func testParsesTimeLine() {
        let line = "frame=  120 fps= 60 q=-0.0 size=     512KiB time=00:00:01.00 bitrate=4194.3kbits/s speed=2.1x"
        XCTAssertEqual(ProgressParser.fraction(fromLine: line, duration: 2.0), 0.5)
    }
    func testReturnsNilWithoutTime() {
        XCTAssertNil(ProgressParser.fraction(fromLine: "ffmpeg version 7.1", duration: 2.0))
    }
    func testClampsToOne() {
        let line = "time=00:00:05.00 bitrate=1k"
        XCTAssertEqual(ProgressParser.fraction(fromLine: line, duration: 2.0), 1.0)
    }
    func testZeroDurationReturnsNil() {
        XCTAssertNil(ProgressParser.fraction(fromLine: "time=00:00:01.00", duration: 0))
    }
}
