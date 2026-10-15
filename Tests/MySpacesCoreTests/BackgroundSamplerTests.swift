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

    func backdrop(_ style: PatchStyle, file: StaticString = #filePath, line: UInt = #line) -> PatchBackdrop? {
        guard case let .backdrop(b) = style else { XCTFail("expected backdrop, got \(style)", file: file, line: line); return nil }
        return b
    }

    func testUniformBackgroundGivesItsColourEverywhere() throws {
        let img = image { ctx in
            ctx.setFillColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40))
        }
        let b = try XCTUnwrap(backdrop(BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1)))
        for point in [CGPoint(x: b.rect.minX, y: b.rect.minY), CGPoint(x: b.rect.midX, y: b.rect.midY), CGPoint(x: b.rect.maxX, y: b.rect.maxY)] {
            let c = b.colour(at: point)
            XCTAssertEqual(c.red, 0.2, accuracy: 0.02)
            XCTAssertEqual(c.green, 0.3, accuracy: 0.02)
            XCTAssertEqual(c.blue, 0.5, accuracy: 0.02)
        }
    }

    func testBackdropCoversCaptionWithRoomAbove() throws {
        let img = image(height: 60) { ctx in ctx.setFillColor(gray: 0.3, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 60)) }
        let c = CGRect(x: 70, y: 22, width: 60, height: 16)
        let b = try XCTUnwrap(backdrop(BackgroundSampler.style(for: c, in: img, pointsPerPixel: 1)))
        XCTAssertTrue(b.rect.contains(c.insetBy(dx: -2, dy: -6)), "\(b.rect) must cover \(c) and its last few points of travel")
    }

    func testVerticalGradientIsReproducedRowByRow() throws {
        // Like the thumbnail row: a lighter band (a selection frame) a few points above the caption.
        let img = image(height: 60) { ctx in
            ctx.setFillColor(gray: 0.2, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            ctx.setFillColor(gray: 0.8, alpha: 1); ctx.fill(CGRect(x: 0, y: 60 - 20, width: 200, height: 3)) // y 17..<20 top-left
        }
        let c = CGRect(x: 70, y: 22, width: 60, height: 16)
        let b = try XCTUnwrap(backdrop(BackgroundSampler.style(for: c, in: img, pointsPerPixel: 1)))
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 18.5)).green, 0.8, accuracy: 0.03)
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 30)).green, 0.2, accuracy: 0.03)
    }

    func testRowsLineUpWithPixelsForFractionalCaptionBox() throws {
        // Vision's boxes are fractional; a sampled row must land on the pixel row it came from,
        // or edges in the background (the bar's lower edge, a selection frame) show as stripes.
        let img = image(height: 60) { ctx in
            ctx.setFillColor(gray: 0.2, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            ctx.setFillColor(gray: 0.8, alpha: 1); ctx.fill(CGRect(x: 0, y: 60 - 45, width: 200, height: 1)) // row 44 top-left
        }
        let b = try XCTUnwrap(backdrop(BackgroundSampler.style(for: CGRect(x: 70, y: 22.4, width: 60, height: 16), in: img, pointsPerPixel: 1)))
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 44.5)).green, 0.8, accuracy: 0.03)
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 43.5)).green, 0.2, accuracy: 0.03)
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 45.5)).green, 0.2, accuracy: 0.03)
    }

    func testSmoothHorizontalGradientIsInterpolated() throws {
        let img = image { ctx in
            for x in 0..<200 {
                ctx.setFillColor(gray: 0.2 + 0.3 * CGFloat(x) / 200, alpha: 1)
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: 40))
            }
        }
        let b = try XCTUnwrap(backdrop(BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1)))
        XCTAssertEqual(b.colour(at: CGPoint(x: 100, y: 20)).red, 0.35, accuracy: 0.02)
        XCTAssertLessThan(b.colour(at: CGPoint(x: b.rect.minX, y: 20)).red, b.colour(at: CGPoint(x: b.rect.maxX, y: 20)).red)
    }

    func testBackdropMovesWithOffset() throws {
        let img = image { ctx in ctx.setFillColor(gray: 0.3, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40)) }
        let style = BackgroundSampler.style(for: caption, in: img, pointsPerPixel: 1)
        let b = try XCTUnwrap(backdrop(style)), moved = try XCTUnwrap(backdrop(style.offsetBy(dx: 3, dy: 5)))
        XCTAssertEqual(moved.rect, b.rect.offsetBy(dx: 3, dy: 5))
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

    func testOneRowTouchingAStripeStillGivesBackdrop() throws {
        // "Desktop 1" in the thumbnail row: the bottom row on one side touches a light wallpaper stripe.
        let img = image(height: 60) { ctx in
            ctx.setFillColor(gray: 0.15, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            ctx.setFillColor(gray: 0.6, alpha: 1); ctx.fill(CGRect(x: 0, y: 60 - 46, width: 66, height: 2)) // y 44..<46 top-left
        }
        XCTAssertNotNil(backdrop(BackgroundSampler.style(for: CGRect(x: 70, y: 22, width: 60, height: 16), in: img, pointsPerPixel: 1)))
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

    func testTextBoundsGrowPastATightVisionBox() {
        // Vision's box can start inside the first glyph ("Desktop 1" in the thumbnail row).
        let img = image { ctx in
            ctx.setFillColor(gray: 0.15, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 40))
            ctx.setFillColor(gray: 0.95, alpha: 1)
            ctx.fill(CGRect(x: 80, y: 14, width: 6, height: 12))   // the cut-off "D"
            ctx.fill(CGRect(x: 88, y: 14, width: 30, height: 12))  // the rest, 2 pt letter gap
            ctx.fill(CGRect(x: 150, y: 14, width: 10, height: 12)) // a neighbour, well apart
        }
        let tooTight = CGRect(x: 84, y: 10, width: 36, height: 20)
        let tight = BackgroundSampler.textBounds(for: tooTight, in: img, pointsPerPixel: 1)
        XCTAssertEqual(tight.minX, 80, accuracy: 1)
        XCTAssertEqual(tight.maxX, 118, accuracy: 1)
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
        if case let .backdrop(b2) = style2, case let .backdrop(b1) = style1 {
            let c2 = b2.colour(at: CGPoint(x: d2.rect.midX, y: d2.rect.midY)), c1 = b1.colour(at: CGPoint(x: d1.rect.midX, y: d1.rect.midY))
            XCTAssertGreaterThan(c2.red + c2.green + c2.blue, c1.red + c1.green + c1.blue, "capsule patch must be lighter than plain bar patch")
        }
        // .pill for Desktop 2 is also acceptable.
    }
}
