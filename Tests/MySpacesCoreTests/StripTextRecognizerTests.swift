import ImageIO
import XCTest
@testable import MySpacesCore

final class StripTextRecognizerTests: XCTestCase {
    func fixture(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func assertLabels(_ labels: [RecognizedLabel], _ expected: [(String, CGFloat, CGFloat)],
                      file: StaticString = #filePath, line: UInt = #line) {
        for (text, x, y) in expected {
            let hit = labels.first { $0.text == text }
            XCTAssertNotNil(hit, "missing \(text) in \(labels.map(\.text))", file: file, line: line)
            if let hit {
                XCTAssertEqual(hit.rect.midX, x, accuracy: 12, "\(text) x", file: file, line: line)
                XCTAssertEqual(hit.rect.midY, y, accuracy: 12, "\(text) y", file: file, line: line)
            }
        }
    }

    func assertNoOverlaps(_ labels: [RecognizedLabel], file: StaticString = #filePath, line: UInt = #line) {
        for (i, a) in labels.enumerated() {
            for b in labels[(i + 1)...] where abs(a.rect.midX - b.rect.midX) < 12 && abs(a.rect.midY - b.rect.midY) < 12 {
                XCTFail("overlapping labels \(a.text) / \(b.text)", file: file, line: line)
            }
        }
    }

    func testCollapsedBar() throws {
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-collapsed"), pointsPerPixel: 1)
        assertLabels(labels, [("Desktop 1", 969, 70), ("Desktop 2", 1055, 70), ("Desktop 3", 1143, 70),
                              ("Desktop 4", 1233, 70), ("Desktop 5", 1322, 70)])
        assertNoOverlaps(labels)
        XCTAssertEqual(labels.filter { LabelMapper.desktopNumber(in: $0.text) != nil }.count, 5, "no duplicates")
    }

    func testExpandedBarWithFullscreenSpace() throws {
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-expanded-fullscreen"), pointsPerPixel: 1)
        assertLabels(labels, [("Desktop 1", 720, 188), ("Desktop 2", 888, 188), ("Desktop 3", 1060, 188),
                              ("Desktop 4", 1230, 188), ("validate", 1400, 188), ("Desktop 5", 1570, 188)])
        assertNoOverlaps(labels)
        XCTAssertEqual(labels.filter { LabelMapper.desktopNumber(in: $0.text) != nil }.count, 5, "no duplicates")
    }

    func testRetinaScaleConvertsToPoints() throws {
        // Same image treated as 2x: points are half the pixel coordinates.
        let labels = try StripTextRecognizer(bandHeight: 60, stripHeight: 18, stripStep: 9)
            .recognize(in: fixture("mc-collapsed"), pointsPerPixel: 0.5)
        let d1 = try XCTUnwrap(labels.first { $0.text == "Desktop 1" })
        XCTAssertEqual(d1.rect.midX, 969 / 2, accuracy: 8)
        XCTAssertEqual(d1.rect.midY, 70 / 2, accuracy: 8)
    }

    func testTargetedRowReadsCollapsedCaptions() throws {
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-collapsed"), pointsPerPixel: 1, rowMidYs: [70])
        XCTAssertEqual(labels.compactMap { LabelMapper.desktopNumber(in: $0.text) }.sorted(), [1, 2, 3, 4, 5])
    }

    func testTargetedRowReadsExpandedCaptions() throws {
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-expanded-fullscreen"), pointsPerPixel: 1, rowMidYs: [70, 188])
        XCTAssertEqual(labels.compactMap { LabelMapper.desktopNumber(in: $0.text) }.sorted(), [1, 2, 3, 4, 5])
        XCTAssertTrue(labels.contains { $0.text == "validate" })
    }

    func testTargetedRowReadsAllSixThumbnailCaptions() throws {
        // Six desktops with the first one current: Vision dropped "Desktop 6" in a full-width strip.
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-expanded-six"), pointsPerPixel: 1, rowMidYs: [23])
        assertLabels(labels, [("Desktop 1", 640, 23), ("Desktop 2", 808, 23), ("Desktop 3", 980, 23),
                              ("Desktop 4", 1150, 23), ("Desktop 5", 1320, 23), ("Desktop 6", 1490, 23)])
    }

    func testTargetedRowWithNoCaptionsFindsNothing() throws {
        let labels = try StripTextRecognizer().recognize(in: fixture("mc-collapsed"), pointsPerPixel: 1, rowMidYs: [20])
        XCTAssertTrue(labels.compactMap { LabelMapper.desktopNumber(in: $0.text) }.isEmpty)
    }
}
