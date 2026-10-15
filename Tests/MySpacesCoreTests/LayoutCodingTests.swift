import ImageIO
import XCTest
@testable import MySpacesCore

final class LayoutCodingTests: XCTestCase {
    func testPlacementAndStyleRoundTrip() throws {
        let p = LabelPlacement(rect: CGRect(x: 936, y: 59, width: 64, height: 20), name: "first 🧪", spaceKey: "main:X", maxWidth: 82)
        let backdrop = PatchBackdrop(rect: CGRect(x: 920, y: 50, width: 90, height: 2),
                                     left: [.init(red: 0.2, green: 0.3, blue: 0.5), .init(red: 0.1, green: 0.1, blue: 0.1)],
                                     right: [.init(red: 0.2, green: 0.3, blue: 0.5), .init(red: 0.9, green: 0.9, blue: 0.9)])
        let styles: [PatchStyle] = [.backdrop(backdrop), .pill]
        XCTAssertEqual(try JSONDecoder().decode(LabelPlacement.self, from: JSONEncoder().encode(p)), p)
        XCTAssertEqual(try JSONDecoder().decode([PatchStyle].self, from: JSONEncoder().encode(styles)), styles)
    }

    func testFingerprintRoundTripStillMatches() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mc-collapsed", withExtension: "png", subdirectory: "Fixtures"))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil))
        let fp = try XCTUnwrap(CaptionFingerprint(image: img, rects: [CGRect(x: 934, y: 60, width: 70, height: 19)], pointsPerPixel: 1))
        let decoded = try JSONDecoder().decode(CaptionFingerprint.self, from: JSONEncoder().encode(fp))
        XCTAssertEqual(decoded, fp)
        XCTAssertTrue(decoded.matches(fp))
    }
}
