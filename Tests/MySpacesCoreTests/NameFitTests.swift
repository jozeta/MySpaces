import XCTest
@testable import MySpacesCore

final class NameFitTests: XCTestCase {
    func testShortNameFitsWithoutFade() {
        let fit = NameFit(textWidth: 40, minimumWidth: 60, maximumWidth: 90, padding: 8)
        XCTAssertEqual(fit.width, 60)
        XCTAssertFalse(fit.fades)
    }

    func testNameGrowsTheBoxUpToTheMaximum() {
        let fit = NameFit(textWidth: 70, minimumWidth: 60, maximumWidth: 90, padding: 8)
        XCTAssertEqual(fit.width, 78)
        XCTAssertFalse(fit.fades)
    }

    func testTooLongNameFadesAtTheMaximum() {
        let fit = NameFit(textWidth: 140, minimumWidth: 60, maximumWidth: 90, padding: 8)
        XCTAssertEqual(fit.width, 90)
        XCTAssertTrue(fit.fades)
        XCTAssertEqual(fit.fadeLength, NameFit.fadeLength)
    }

    func testFadeStartsWhereTheTextIsCutOff() {
        let fit = NameFit(textWidth: 140, minimumWidth: 60, maximumWidth: 90, padding: 8)
        // Text area is 90 - 8 = 82 wide; the fade covers its last `fadeLength` points.
        XCTAssertEqual(fit.fadeStart, (82 - NameFit.fadeLength) / 82, accuracy: 0.001)
    }

    func testFadeLengthCanScaleWithTheText() {
        // Large text (the switch panel) needs a longer fade, or it reads as a hard cut.
        let fit = NameFit(textWidth: 2000, minimumWidth: 400, maximumWidth: 1000, padding: 100, fadeLength: 72)
        XCTAssertEqual(fit.fadeLength, 72)
        XCTAssertEqual(fit.fadeStart, (900 - 72) / 900, accuracy: 0.001)
    }
}
