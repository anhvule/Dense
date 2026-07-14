import XCTest
@testable import DenseCore

final class PresetCatalogTests: XCTestCase {
    func testSlackPresetBudget() {
        XCTAssertEqual(Preset.slack.targetSizeMB, 50)
        XCTAssertEqual(Preset.slack.displayName, "Slack (50 MB)")
    }

    func testEmailSmallPresetBudget() {
        XCTAssertEqual(Preset.emailSmall.targetSizeMB, 10)
        XCTAssertEqual(Preset.emailSmall.displayName, "Email (10 MB)")
    }

    func testNewPresetsCapAt1080p() {
        // 4K input must scale down for size-targeted sends
        XCTAssertEqual(Preset.slack.maxHeight, 1080)
        XCTAssertEqual(Preset.emailSmall.maxHeight, 1080)
    }

    func testStoredPreferenceDecodingUnaffected() throws {
        // Old users have "discord"/"balanced" etc. persisted — raw-value decode must still work
        let decoded = try JSONDecoder().decode(Preset.self, from: Data("\"discord\"".utf8))
        XCTAssertEqual(decoded, .discord)
        let new = try JSONDecoder().decode(Preset.self, from: Data("\"emailSmall\"".utf8))
        XCTAssertEqual(new, .emailSmall)
    }
}
