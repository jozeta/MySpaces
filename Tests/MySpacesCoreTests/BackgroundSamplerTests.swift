import ImageIO
import XCTest
@testable import MySpacesCore

final class BackgroundSamplerTests: XCTestCase {
    func image(width: Int = 200, height: Int = 40, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    let caption = CGRect(x: 70, y: 12, width: 60, height: 16)

    func testUniformBackgroundGivesNativeColour() {
        let img = image { ctx in
            ctx.setFillColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40))
        }
        guard case let .native(r, g, b) = BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1) else {
            return XCTFail("expected native")
        }
        XCTAssertEqual(r, 0.2, accuracy: 0.02)
        XCTAssertEqual(g, 0.3, accuracy: 0.02)
        XCTAssertEqual(b, 0.5, accuracy: 0.02)
    }

    func testStripedBackgroundFallsBackToPill() {
        let img = image { ctx in
            for x in stride(from: 0, to: 200, by: 2) {
                ctx.setFillColor(gray: x % 4 == 0 ? 0 : 1, alpha: 1)
                ctx.fill(CGRect(x: x, y: 0, width: 2, height: 40))
            }
        }
        XCTAssertEqual(BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1), .pill)
    }

    func testDifferentLeftAndRightFallsBackToPill() {
        let img = image { ctx in
            ctx.setFillColor(gray: 0.1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
            ctx.setFillColor(gray: 0.9, alpha: 1); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 40))
        }
        XCTAssertEqual(BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1), .pill)
    }

    func testCaptionAtImageEdgeFallsBackToPill() {
        let img = image { ctx in ctx.setFillColor(gray: 0.5, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40)) }
        XCTAssertEqual(BackgroundSampler.style(for: CGRect(x: 2, y: 12, width: 60, height: 16), in: img, pointsPerPixel: 1), .pill)
    }

    func testTextBoundsTightenToBrightGlyphs() {
        // Dark background with a white "glyph" block at x 80..<120, y 14..<26.
        let img = image { ctx in
            ctx.setFillColor(gray: 0.15, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40))
            ctx.setFillColor(gray: 0.95, alpha: 1); ctx.fill(CGRect(x: 80, y: 14, width: 40, height: 12))
        }
        let loose = CGRect(x: 60, y: 10, width: 80, height: 20)
        let tight = BackgroundSampler.textBounds(for: loose, in: img, pointsPerPixel: 1)
        XCTAssertEqual(tight.minX, 80, accuracy: 1)
        XCTAssertEqual(tight.maxX, 120, accuracy: 1)
        XCTAssertEqual(tight.minY, loose.minY)
        XCTAssertEqual(tight.height, loose.height)
    }

    func testTextBoundsWithoutGlyphsKeepsRect() {
        let img = image { ctx in ctx.setFillColor(gray: 0.3, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40)) }
        XCTAssertEqual(BackgroundSampler.textBounds(for: caption, in: img, pointsPerPixel: 1), caption)
    }

    func testCollapsedCurrentDesktopCaptionIsHandled() throws {
        // "Desktop 2" in the collapsed fixture sits on a lighter capsule. Whatever the sampler
        // decides, a native patch must be close to the capsule's own colour (no dark block).
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mc-collapsed", withExtension: "png", subdirectory: "Fixtures"))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil))
        let labels = try StripTextRecognizer().recognize(in: img, pointsPerPixel: 1)
        let d2 = try XCTUnwrap(labels.first { $0.text == "Desktop 2" })
        let d1 = try XCTUnwrap(labels.first { $0.text == "Desktop 1" })
        let style2 = BackgroundSampler.style(for: d2.rect, in: img, pointsPerPixel: 1)
        let style1 = BackgroundSampler.style(for: d1.rect, in: img, pointsPerPixel: 1)
        if case let .native(r2, g2, b2) = style2, case let .native(r1, g1, b1) = style1 {
            XCTAssertGreaterThan(r2 + g2 + b2, r1 + g1 + b1, "capsule patch must be lighter than plain bar patch")
        }
        // .pill for Desktop 2 is also acceptable.
    }
}
