import ImageIO
import XCTest
@testable import MySpacesCore

final class CaptionFingerprintTests: XCTestCase {
    func fixture(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil))
    }

    // "Desktop 1" and "Desktop 2" caption boxes in the collapsed fixture (points = pixels).
    let collapsedRects = [CGRect(x: 934, y: 60, width: 70, height: 19), CGRect(x: 1022, y: 60, width: 68, height: 19)]

    func testIdenticalCaptionsMatch() throws {
        let img = try fixture("mc-collapsed")
        let a = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        let b = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        XCTAssertEqual(a.difference(to: b), 0, accuracy: 0.001)
        XCTAssertTrue(a.matches(b))
    }

    func testCaptionsGoneOrMovedDoNotMatch() throws {
        let reference = try XCTUnwrap(CaptionFingerprint(image: fixture("mc-collapsed"), rects: collapsedRects, pointsPerPixel: 1))
        // Same screen region, but the bar has expanded: captions are no longer there.
        let expanded = try XCTUnwrap(CaptionFingerprint(image: fixture("mc-expanded-fullscreen"), rects: collapsedRects, pointsPerPixel: 1))
        XCTAssertFalse(reference.matches(expanded))
        // Captions shifted by 6 pt (bar still sliding in).
        let shifted = collapsedRects.map { $0.offsetBy(dx: 0, dy: -6) }
        let moved = try XCTUnwrap(CaptionFingerprint(image: fixture("mc-collapsed"), rects: shifted, pointsPerPixel: 1))
        XCTAssertFalse(reference.matches(moved))
    }

    func testSmallBrightnessChangeStillMatches() throws {
        let img = try fixture("mc-collapsed")
        let reference = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        // Blurred-wallpaper bar shifts slightly when windows behind it change: tolerate it.
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.setFillColor(gray: 1, alpha: 0.02)
        ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let brighter = try XCTUnwrap(CaptionFingerprint(image: ctx.makeImage()!, rects: collapsedRects, pointsPerPixel: 1))
        XCTAssertTrue(reference.matches(brighter))
    }

    func testDifferentRectCountNeverMatches() throws {
        let img = try fixture("mc-collapsed")
        let a = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        let b = try XCTUnwrap(CaptionFingerprint(image: img, rects: [collapsedRects[0]], pointsPerPixel: 1))
        XCTAssertFalse(a.matches(b))
    }

    func testNeighbouringCaptionsAreDistinguished() throws {
        // "Desktop 3" and "Desktop 4" boxes (same size, no highlight): a layout shifted by one slot
        // must not pass as a match.
        let img = try fixture("mc-collapsed")
        let d3 = try XCTUnwrap(CaptionFingerprint(image: img, rects: [CGRect(x: 1111, y: 60, width: 64, height: 20)], pointsPerPixel: 1))
        let d4 = try XCTUnwrap(CaptionFingerprint(image: img, rects: [CGRect(x: 1201, y: 60, width: 64, height: 20)], pointsPerPixel: 1))
        XCTAssertFalse(d3.matches(d4))
    }

    func testOneChangedCaptionAmongSeveralIsDetected() throws {
        let img = try fixture("mc-collapsed")
        let rects = [CGRect(x: 934, y: 60, width: 70, height: 19), CGRect(x: 1111, y: 60, width: 64, height: 20)]
        let a = try XCTUnwrap(CaptionFingerprint(image: img, rects: rects, pointsPerPixel: 1))
        let b = try XCTUnwrap(CaptionFingerprint(image: img, rects: [rects[0], CGRect(x: 1201, y: 60, width: 64, height: 20)], pointsPerPixel: 1))
        XCTAssertFalse(a.matches(b), "a mean over all captions would dilute one wrong caption")
    }

    func testCaptionDifferencesTellWhichCaptionChanged() throws {
        // Adding a desktop moves only the last caption: the others' names can stay.
        let img = try fixture("mc-collapsed")
        let rects = [CGRect(x: 934, y: 60, width: 70, height: 19), CGRect(x: 1111, y: 60, width: 64, height: 20)]
        let a = try XCTUnwrap(CaptionFingerprint(image: img, rects: rects, pointsPerPixel: 1))
        let b = try XCTUnwrap(CaptionFingerprint(image: img, rects: [rects[0], CGRect(x: 1201, y: 60, width: 64, height: 20)], pointsPerPixel: 1))
        let d = a.captionDifferences(to: b)
        XCTAssertEqual(d.count, 2)
        XCTAssertLessThan(d[0], CaptionFingerprint.matchThreshold)
        XCTAssertGreaterThan(d[1], CaptionFingerprint.matchThreshold)
        XCTAssertEqual(a.difference(to: b), d.max()!, accuracy: 0.0001)
    }

    func testHalfPointShiftIsStillFollowedButGoneCaptionsAreNot() throws {
        // Mid-slide frames put captions at fractional positions: slightly off, still there.
        let img = try fixture("mc-collapsed")
        let reference = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        let half = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects.map { $0.offsetBy(dx: 0.5, dy: 0.5) }, pointsPerPixel: 1))
        XCTAssertLessThan(reference.difference(to: half), CaptionFingerprint.followThreshold)
        // Bar expanded: the captions are gone from there.
        let gone = try XCTUnwrap(CaptionFingerprint(image: fixture("mc-expanded-fullscreen"), rects: collapsedRects, pointsPerPixel: 1))
        XCTAssertGreaterThan(reference.difference(to: gone), CaptionFingerprint.followThreshold)
    }

    func testContentTellsCaptionsFromEmptyBar() throws {
        let img = try fixture("mc-collapsed")
        let captions = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        XCTAssertTrue(captions.hasContent, "every rect holds caption text")
        // The same rects moved into the empty bar to the left of the captions.
        let empty = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects.map { $0.offsetBy(dx: -500, dy: 0) }, pointsPerPixel: 1))
        XCTAssertFalse(empty.hasContent)
    }

    func testLocateFindsCaptionsThatDriftedAFewPoints() throws {
        let img = try fixture("mc-collapsed")
        let reference = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        // The captions now sit 3 pt left and 1 pt up of where they were remembered.
        let remembered = collapsedRects.map { $0.offsetBy(dx: 3, dy: 1) }
        let found = try XCTUnwrap(CaptionFingerprint.locate(reference, expectedAt: remembered, in: img, pointsPerPixel: 1,
                                                            maxShift: CGSize(width: 6, height: 3)))
        XCTAssertEqual(found.dx, -3)
        XCTAssertEqual(found.dy, -1)
    }

    func testLocateRejectsCaptionsOutsideTheSearchRange() throws {
        let img = try fixture("mc-collapsed")
        let reference = try XCTUnwrap(CaptionFingerprint(image: img, rects: collapsedRects, pointsPerPixel: 1))
        let farAway = collapsedRects.map { $0.offsetBy(dx: 40, dy: 0) }
        XCTAssertNil(CaptionFingerprint.locate(reference, expectedAt: farAway, in: img, pointsPerPixel: 1,
                                               maxShift: CGSize(width: 6, height: 3)))
    }
}
