import XCTest
@testable import MySpacesCore

final class ScanSlotTests: XCTestCase {
    func testBusyUntilItsScanEnds() {
        var slot = ScanSlot()
        XCTAssertFalse(slot.isBusy)
        let id = slot.begin()
        XCTAssertTrue(slot.isBusy)
        slot.end(id)
        XCTAssertFalse(slot.isBusy)
    }

    func testAnOlderScanEndingDoesNotFreeANewerOne() {
        // Desktops changed mid-scan: the slot was reset and a new scan began; the old one ends late.
        var slot = ScanSlot()
        let old = slot.begin()
        slot.reset()
        let new = slot.begin()
        slot.end(old)
        XCTAssertTrue(slot.isBusy, "still waiting for the newer scan")
        slot.end(new)
        XCTAssertFalse(slot.isBusy)
    }

    func testAScanThatNeverEndsIsStuckAfterTheTimeout() {
        var slot = ScanSlot()
        let start = Date()
        _ = slot.begin(now: start)
        XCTAssertFalse(slot.isStuck(now: start.addingTimeInterval(1), timeout: 5))
        XCTAssertTrue(slot.isStuck(now: start.addingTimeInterval(6), timeout: 5))
        XCTAssertFalse(ScanSlot().isStuck(now: start.addingTimeInterval(60), timeout: 5), "an idle slot is not stuck")
    }
}
