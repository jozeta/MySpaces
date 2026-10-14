import XCTest
@testable import MySpacesCore

final class LabelMapperTests: XCTestCase {
    func label(_ text: String, x: CGFloat, y: CGFloat = 188) -> RecognizedLabel {
        RecognizedLabel(text: text, rect: CGRect(x: x - 30, y: y - 8, width: 60, height: 16))
    }

    // Expanded bar from the spike: Desktop 1-4, full-screen "validate", Desktop 5.
    let spaces = [desktop(1, ""), desktop(2, "B"), desktop(3, "C"), desktop(4, "D"),
                  fullscreen(5, "F", app: "validate"), desktop(6, "E")]
    var labels: [RecognizedLabel] {
        [label("Desktop 1", x: 720), label("Desktop 2", x: 888), label("Desktop 3", x: 1060),
         label("Desktop 4", x: 1230), label("validate", x: 1400), label("Desktop 5", x: 1570)]
    }

    func testDesktopNumberParsing() {
        XCTAssertEqual(LabelMapper.desktopNumber(in: "Desktop 12"), 12)
        XCTAssertEqual(LabelMapper.desktopNumber(in: " Desktop 3 "), 3)
        XCTAssertNil(LabelMapper.desktopNumber(in: "Deskton 3"))
        XCTAssertNil(LabelMapper.desktopNumber(in: "Desktop"))
        XCTAssertNil(LabelMapper.desktopNumber(in: "My Desktop 3"))
    }

    func testMapsNamedDesktopsSkippingFullscreen() throws {
        let result = try XCTUnwrap(LabelMapper.placements(
            labels: labels, displaySpaces: spaces, names: ["main:Main": "Development", "E": "Music"]))
        XCTAssertEqual(result.map(\.name), ["Development", "Music"])
        XCTAssertEqual(result.map(\.spaceKey), ["main:Main", "E"])
        XCTAssertEqual(result[1].rect.midX, 1570, accuracy: 0.1)
    }

    func testNoNamesGivesEmptyNotNil() {
        XCTAssertEqual(LabelMapper.placements(labels: labels, displaySpaces: spaces, names: [:]), [])
    }

    func testCountMismatchReturnsNil() {
        let missingOne = Array(labels.dropLast())
        XCTAssertNil(LabelMapper.placements(labels: missingOne, displaySpaces: spaces, names: ["B": "x"]))
        let extraSpace = spaces + [desktop(7, "G")]
        XCTAssertNil(LabelMapper.placements(labels: labels, displaySpaces: extraSpace, names: ["B": "x"]))
    }

    func testDuplicateNumberReturnsNil() {
        var dup = labels
        dup[1] = label("Desktop 1", x: 888)
        XCTAssertNil(LabelMapper.placements(labels: dup, displaySpaces: spaces, names: ["B": "x"]))
    }

    func testMaxWidthLimitedByNeighbours() throws {
        // Collapsed bar: captions ~88 pt apart.
        let collapsed = [label("Desktop 1", x: 969, y: 70), label("Desktop 2", x: 1055, y: 70), label("Desktop 3", x: 1143, y: 70)]
        let three = [desktop(1, ""), desktop(2, "B"), desktop(3, "C")]
        let result = try XCTUnwrap(LabelMapper.placements(labels: collapsed, displaySpaces: three, names: ["B": String(repeating: "W", count: 40)]))
        XCTAssertEqual(result[0].maxWidth, 82, accuracy: 0.1) // min(86, 88) - 4
    }

    func testLoneLabelGetsGenerousMaxWidth() throws {
        let result = try XCTUnwrap(LabelMapper.placements(
            labels: [label("Desktop 1", x: 500)], displaySpaces: [desktop(1, "")], names: ["main:Main": "Solo"]))
        XCTAssertEqual(result[0].maxWidth, 240)
    }

    func testCaptionRowUsesDesktopCaptionsOnly() throws {
        let row = try XCTUnwrap(LabelMapper.captionRow(in: labels + [label("Explorer", x: 300, y: 260)]))
        XCTAssertEqual(row.midY, 188, accuracy: 0.1)
        XCTAssertEqual(row.maxY, 196, accuracy: 0.1)
        XCTAssertNil(LabelMapper.captionRow(in: [label("Explorer", x: 300, y: 260)]))
    }
}
