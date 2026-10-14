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
}
