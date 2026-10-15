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
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> LabelPlacement {
        LabelPlacement(rect: CGRect(x: x, y: y, width: w, height: h), name: "N", spaceKey: "\(x)", maxWidth: 120)
    }

    func testCaptionsOfOneRowShareTheirCentreLine() {
        // Real caption boxes under the thumbnails (macOS 27): heights vary a little, centres don't.
        let row = [box(611, 183, 53, 16), box(781, 183, 56, 17), box(1017, 185, 56, 14), box(1462, 181, 57, 21)]
        XCTAssertTrue(LayoutStabilizer.isOneRow(row))
        XCTAssertTrue(LayoutStabilizer.isOneRow([box(611, 183, 53, 16)]))
        XCTAssertTrue(LayoutStabilizer.isOneRow([]))
    }

    func testCaptionBoxReachingIntoAThumbnailIsNotARow() {
        // Read while a dragged thumbnail crossed the caption row: the box ran up into it.
        let row = [box(611, 183, 53, 16), box(781, 183, 56, 17), box(951, 183, 56, 16), box(1448, 173, 80, 26), box(1634, 183, 56, 19)]
        XCTAssertFalse(LayoutStabilizer.isOneRow(row))
    }

    func testBoxesOffTheRowAreSnappedOntoIt() {
        // Holiday's box took in its thumbnail's white bottom edge (39 pt tall, read at rest).
        let row = [box(611, 183, 53, 16), box(781, 182.5, 56, 19), box(951, 185, 56, 14), box(1440, 168.5, 56, 39), box(1634, 183, 56, 18)]
        let snapped = LayoutStabilizer.snappedToRow(row)
        XCTAssertTrue(LayoutStabilizer.isOneRow(snapped))
        XCTAssertEqual(snapped[3].rect.minX, 1440)
        XCTAssertEqual(snapped[3].rect.width, 56)
        XCTAssertEqual(snapped[3].rect.midY, 192, accuracy: 0.01)
        XCTAssertEqual(snapped[3].rect.height, 18)
        XCTAssertEqual(snapped[0].rect, row[0].rect, "boxes on the row are left as read")
        XCTAssertEqual(snapped[3].name, "N")
    }

    func testTallBoxCentredOnTheRowIsSnappedToo() {
        // Read at rest: stretched over the thumbnail's white edge above and the gap below alike,
        // so its centre is still close to the row's.
        let row = [box(611, 183, 53, 16), box(781, 183, 56, 17), box(951, 183, 56, 16), box(1189, 169, 88, 39.8), box(1375, 182.3, 56, 19.5)]
        XCTAssertFalse(LayoutStabilizer.isOneRow(row))
        let snapped = LayoutStabilizer.snappedToRow(row)
        XCTAssertTrue(LayoutStabilizer.isOneRow(snapped))
        XCTAssertEqual(snapped[3].rect.height, 17)
        XCTAssertEqual(snapped[3].rect.minX, 1189)
    }
}
