import XCTest
@testable import DenseCore

final class DiskSpaceTests: XCTestCase {
    func testWarnsWhenFreeSpaceInsideHeadroom() {
        let warning = DiskSpace.warning(estimatedBytes: 1_000_000_000,
                                        freeBytes: 1_200_000_000)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.lowercased().contains("disk"))
    }

    func testSilentWithAmpleSpace() {
        XCTAssertNil(DiskSpace.warning(estimatedBytes: 1_000_000_000,
                                       freeBytes: 2_000_000_000))
    }

    func testFreeBytesReadsRealVolume() throws {
        let free = try XCTUnwrap(DiskSpace.freeBytes(at: FileManager.default.temporaryDirectory))
        XCTAssertGreaterThan(free, 0)
    }
}
