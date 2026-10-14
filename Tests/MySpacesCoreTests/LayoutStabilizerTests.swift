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
}
