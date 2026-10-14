import XCTest
@testable import MySpacesCore

func desktop(_ id: Int, _ uuid: String, current: Bool = false, display: String = "Main") -> Space {
    Space(managedID: id, uuid: uuid, displayID: display, kind: .desktop, isCurrent: current)
}

func fullscreen(_ id: Int, _ uuid: String, app: String, current: Bool = false) -> Space {
    Space(managedID: id, uuid: uuid, displayID: "Main", kind: .fullscreen(appName: app), isCurrent: current)
}

final class SpaceRowsTests: XCTestCase {
    let spaces = [desktop(1, "", current: true), desktop(2, "B"), fullscreen(3, "F", app: "Safari"), desktop(4, "D")]

    func testTitlesUseCustomNameOrDefault() {
        let rows = SpaceRowBuilder.rows(for: spaces, names: ["main:Main": "Development", "D": "Research"])
        XCTAssertEqual(rows.map(\.title), ["Development", "Desktop 2", "Safari", "Research"])
        XCTAssertEqual(rows.map(\.hasCustomName), [true, false, false, true])
    }

    func testSubtitlesAndRenamability() {
        let rows = SpaceRowBuilder.rows(for: spaces, names: [:])
        XCTAssertEqual(rows.map(\.subtitle), ["Space 1 · Current desktop", "Space 2", "Full screen", "Space 3"])
        XCTAssertEqual(rows.map(\.isRenamable), [true, true, false, true])
        XCTAssertEqual(rows.map(\.id), ["main:Main", "B", "F", "D"])
    }

    func testCurrentFullscreenSubtitle() {
        let rows = SpaceRowBuilder.rows(for: [desktop(1, ""), fullscreen(3, "F", app: "Safari", current: true)], names: [:])
        XCTAssertEqual(rows[1].subtitle, "Full screen · Current")
    }

    func testRowsOnlyCoverPrimaryDisplay() {
        let rows = SpaceRowBuilder.rows(for: spaces + [desktop(9, "Z", display: "Other")], names: [:])
        XCTAssertEqual(rows.count, 4)
    }

    func testPruneRequiresTwoConsecutiveAbsences() {
        let reconciler = NameReconciler()
        let stored: Set<String> = ["B", "GONE"]
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: spaces), [])
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: spaces), ["GONE"])
    }

    func testReappearingSpaceResetsCounter() {
        let reconciler = NameReconciler()
        let stored: Set<String> = ["X"]
        _ = reconciler.keysToPrune(storedKeys: stored, spaces: spaces)
        _ = reconciler.keysToPrune(storedKeys: stored, spaces: spaces + [desktop(7, "X")])
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: spaces), [])
    }

    func testEmptySpaceListNeverPrunes() {
        let reconciler = NameReconciler()
        let stored: Set<String> = ["B"]
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: []), [])
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: []), [])
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: stored, spaces: []), [])
    }

    func testNamesOnOtherDisplaysAreKept() {
        let reconciler = NameReconciler()
        let all = spaces + [desktop(9, "Z", display: "Other")]
        _ = reconciler.keysToPrune(storedKeys: ["Z"], spaces: all)
        XCTAssertEqual(reconciler.keysToPrune(storedKeys: ["Z"], spaces: all), [])
    }
}
