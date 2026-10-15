import XCTest
@testable import MySpacesCore

final class RestingOffsetTests: XCTestCase {
    func testZeroOffsetNeverRebases() {
        var r = RestingOffset(requiredReadings: 3)
        for _ in 0..<10 { XCTAssertFalse(r.observe(dx: 0, dy: 0)) }
    }

    func testStableNonZeroOffsetRebasesOnce() {
        var r = RestingOffset(requiredReadings: 3)
        XCTAssertFalse(r.observe(dx: 0, dy: 5))
        XCTAssertFalse(r.observe(dx: 0, dy: 5))
        XCTAssertTrue(r.observe(dx: 0, dy: 5))
        XCTAssertFalse(r.observe(dx: 0, dy: 5), "after a rebase the caller starts again from zero")
    }

    func testStillMovingDoesNotRebase() {
        // The tail of Mission Control's slide: one point at a time.
        var r = RestingOffset(requiredReadings: 3)
        for dy in [1, 2, 2, 3, 3, 4, 4, 5] { XCTAssertFalse(r.observe(dx: 0, dy: dy)) }
    }

    func testResetForgetsReadings() {
        var r = RestingOffset(requiredReadings: 2)
        XCTAssertFalse(r.observe(dx: 2, dy: 0))
        r.reset()
        XCTAssertFalse(r.observe(dx: 2, dy: 0))
        XCTAssertTrue(r.observe(dx: 2, dy: 0))
    }

    func testSteadyZeroCountsWhenAllowed() {
        // Deciding when a not-yet-shown layout is at rest: in place counts too.
        var r = RestingOffset(requiredReadings: 3, countsZero: true)
        XCTAssertFalse(r.observe(dx: 0, dy: 0))
        XCTAssertFalse(r.observe(dx: 0, dy: 0))
        XCTAssertTrue(r.observe(dx: 0, dy: 0))
    }
}
