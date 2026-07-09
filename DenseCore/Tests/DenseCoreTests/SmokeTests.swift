import XCTest
@testable import DenseCore

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(DenseCore.version, "0.1.0")
    }
}
