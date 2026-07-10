import XCTest
@testable import DenseCore

final class WatchReconfigurePlanTests: XCTestCase {
    let idA = UUID()
    let idB = UUID()

    func testPresetOnlyChangeKeepsWatcher() {
        // Preset isn't part of the keep/start/stop decision — a preset-only
        // edit must not tear down the watcher (that would re-seed `seen`
        // and could drop a file mid-arrival).
        let current = [idA: "/watch/a"]
        let desired = [WatchedFolder(id: idA, path: "/watch/a", presetRaw: "small", enabled: true)]
        let plan = WatchReconfigurePlan.plan(current: current, desired: desired)
        XCTAssertEqual(plan.keep, [idA])
        XCTAssertTrue(plan.start.isEmpty)
        XCTAssertTrue(plan.stop.isEmpty)
    }

    func testPathChangeStopsOldAndStartsNew() {
        let current = [idA: "/watch/old"]
        let desired = [WatchedFolder(id: idA, path: "/watch/new", presetRaw: "balanced", enabled: true)]
        let plan = WatchReconfigurePlan.plan(current: current, desired: desired)
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertEqual(plan.start.map(\.id), [idA])
        XCTAssertEqual(plan.stop, [idA])
    }

    func testToggleOffStopsWatcher() {
        let current = [idA: "/watch/a"]
        let desired = [WatchedFolder(id: idA, path: "/watch/a", presetRaw: "balanced", enabled: false)]
        let plan = WatchReconfigurePlan.plan(current: current, desired: desired)
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertTrue(plan.start.isEmpty)
        XCTAssertEqual(plan.stop, [idA])
    }

    func testRemovedFolderStopsWatcher() {
        let current = [idA: "/watch/a"]
        let plan = WatchReconfigurePlan.plan(current: current, desired: [])
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertTrue(plan.start.isEmpty)
        XCTAssertEqual(plan.stop, [idA])
    }

    func testNewEnabledFolderStarts() {
        let desired = [WatchedFolder(id: idA, path: "/watch/a", presetRaw: "balanced", enabled: true)]
        let plan = WatchReconfigurePlan.plan(current: [:], desired: desired)
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertEqual(plan.start.map(\.id), [idA])
        XCTAssertTrue(plan.stop.isEmpty)
    }

    func testNewDisabledFolderDoesNothing() {
        let desired = [WatchedFolder(id: idA, path: "/watch/a", presetRaw: "balanced", enabled: false)]
        let plan = WatchReconfigurePlan.plan(current: [:], desired: desired)
        XCTAssertEqual(plan, WatchReconfigurePlan(keep: [], start: [], stop: []))
    }

    func testMixedEditOnlyTouchesChangedFolders() {
        // The Important-review scenario: editing folder B must leave folder
        // A's watcher (and therefore its seen/generation state) untouched.
        let current = [idA: "/watch/a", idB: "/watch/b"]
        let desired = [
            WatchedFolder(id: idA, path: "/watch/a", presetRaw: "balanced", enabled: true),
            WatchedFolder(id: idB, path: "/watch/b", presetRaw: "discord", enabled: false),
        ]
        let plan = WatchReconfigurePlan.plan(current: current, desired: desired)
        XCTAssertEqual(plan.keep, [idA])
        XCTAssertTrue(plan.start.isEmpty)
        XCTAssertEqual(plan.stop, [idB])
    }
}
