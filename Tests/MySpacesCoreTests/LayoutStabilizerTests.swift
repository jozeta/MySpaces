import XCTest
@testable import MySpacesCore

final class LayoutStabilizerTests: XCTestCase {
    func placement(y: CGFloat, name: String = "Dev") -> LabelPlacement {
        LabelPlacement(rect: CGRect(x: 940, y: y - 8, width: 60, height: 16), name: name, spaceKey: "A", maxWidth: 80)
    }

    func testStableOnlyAfterTwoMatchingObservations() {
        let s = LayoutStabilizer()
        XCTAssertFalse(s.observe([placement(y: 39)]), "first sighting may be mid-animation")
        XCTAssertFalse(s.observe([placement(y: 60)]), "still sliding in")
        XCTAssertFalse(s.observe([placement(y: 69)]))
        XCTAssertTrue(s.observe([placement(y: 69.5)]), "same position twice = settled")
    }

    func testNameChangeIsNotStable() {
        let s = LayoutStabilizer()
        _ = s.observe([placement(y: 69, name: "A")])
        XCTAssertFalse(s.observe([placement(y: 69, name: "B")]))
    }

    func testResetForgetsHistory() {
        let s = LayoutStabilizer()
        _ = s.observe([placement(y: 69)])
        s.reset()
        XCTAssertFalse(s.observe([placement(y: 69)]))
    }

    func testEmptyLayoutsCanBeStable() {
        let s = LayoutStabilizer()
        XCTAssertFalse(s.observe([]))
        XCTAssertTrue(s.observe([]))
    }

    func testStricterStabilizerNeedsThreeAgreeingReadingsWithinOnePoint() {
        let s = LayoutStabilizer(requiredAgreeing: 3, tolerance: 1)
        XCTAssertFalse(s.observe([placement(y: 69)]))
        XCTAssertFalse(s.observe([placement(y: 69.4)]), "two readings are not enough")
        XCTAssertTrue(s.observe([placement(y: 69.2)]))
        XCTAssertFalse(s.observe([placement(y: 70.6)]), "moved more than 1 pt: start over")
    }

    func testRescanToleratesTextRecognitionJitter() {
        // Vision's caption boxes move a few points between reads of the same, still screen.
        XCTAssertTrue(LayoutStabilizer.same([placement(y: 190)], [placement(y: 193)], tolerance: LayoutStabilizer.rescanTolerance))
        // A desktop added or removed moves captions by a whole slot.
        XCTAssertFalse(LayoutStabilizer.same([placement(y: 190)], [placement(y: 190 + 80)], tolerance: LayoutStabilizer.rescanTolerance))
    }
}
