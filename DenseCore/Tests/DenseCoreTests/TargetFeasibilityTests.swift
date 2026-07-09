// DenseCore/Tests/DenseCoreTests/TargetFeasibilityTests.swift
import XCTest
@testable import DenseCore

final class TargetFeasibilityTests: XCTestCase {
    func testFeasibleTargetReturnsNil() {
        let info = MediaInfo(duration: 60, width: 1920, height: 1080, sizeBytes: 200_000_000)
        XCTAssertNil(TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .discord)))
    }

    func testHourLongClipTo25MBIsUnreachable() {
        let info = MediaInfo(duration: 3600, width: 1920, height: 1080, sizeBytes: 2_000_000_000)
        let closest = TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .discord))
        // (150k + 128k) bps * 3600s / 8 / 1e6 = 125.1 MB
        XCTAssertEqual(try XCTUnwrap(closest), 125.1, accuracy: 1.0)
    }

    func testQualityPresetIsAlwaysFeasible() {
        let info = MediaInfo(duration: 3600, width: 1920, height: 1080, sizeBytes: 2_000_000_000)
        XCTAssertNil(TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .balanced)))
    }
}
