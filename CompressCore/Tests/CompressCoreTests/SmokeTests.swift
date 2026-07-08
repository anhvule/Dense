import XCTest
@testable import CompressCore

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(CompressCore.version, "0.1.0")
    }
}
