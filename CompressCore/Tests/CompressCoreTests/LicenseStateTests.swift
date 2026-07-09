import XCTest
@testable import CompressCore

final class DictStore: KeyValueStore {
    var dict: [String: String] = [:]
    func string(forKey key: String) -> String? { dict[key] }
    func set(_ value: String, forKey key: String) { dict[key] = value }
}

final class LicenseStateTests: XCTestCase {
    func testFreshInstallStartsTrialWith7Days() {
        let state = LicenseState(store: DictStore())
        XCTAssertEqual(state.status(), .trial(daysLeft: 7))
    }

    func testDay6Shows1DayLeft() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status() // seeds trialStart
        fakeNow = fakeNow.addingTimeInterval(6 * 86400 + 3600)
        XCTAssertEqual(state.status(), .trial(daysLeft: 1))
    }

    func testDay8IsExpired() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status()
        fakeNow = fakeNow.addingTimeInterval(8 * 86400)
        XCTAssertEqual(state.status(), .trialExpired)
    }

    func testClockRollbackDoesNotExtendTrial() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status()
        fakeNow = fakeNow.addingTimeInterval(-30 * 86400) // user sets clock back
        XCTAssertEqual(state.status(), .trialExpired)
    }

    func testActivationLicenses() {
        let state = LicenseState(store: DictStore())
        state.recordActivation(key: "KEY-123", instanceID: "inst-1")
        XCTAssertEqual(state.status(), .licensed)
    }

    func testOfflineGraceKeepsLicenseFor14Days() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        state.recordActivation(key: "KEY-123", instanceID: "inst-1")
        state.recordValidation(succeeded: true)
        fakeNow = fakeNow.addingTimeInterval(13 * 86400)
        state.recordValidation(succeeded: false) // network down; inside grace
        XCTAssertEqual(state.status(), .licensed)
        fakeNow = fakeNow.addingTimeInterval(2 * 86400) // 15 days since last success
        state.recordValidation(succeeded: false)
        XCTAssertEqual(state.status(), .trialExpired)
    }
}
