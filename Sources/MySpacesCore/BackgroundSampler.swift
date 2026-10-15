import CoreGraphics
import Foundation

public enum PatchStyle: Equatable, Sendable, Codable {
    /// Paint over the caption with the background rebuilt around it, then draw the name.
    case backdrop(PatchBackdrop)
    /// Background too busy to match: use the frosted pill.
    case pill

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> PatchStyle {
        guard case let .backdrop(b) = self else { return self }
        return .backdrop(PatchBackdrop(rect: b.rect.offsetBy(dx: dx, dy: dy), left: b.left, right: b.right))
    }
}

/// The background behind a caption, rebuilt without its glyphs: every pixel row is a blend from
/// the colour just left of the caption to the colour just right of it. A flat patch shows as a
/// box on a gradient wallpaper and paints over a selection frame; this follows both.
public struct PatchBackdrop: Equatable, Sendable, Codable {
    public struct RGB: Equatable, Sendable, Codable {
        public var red, green, blue: CGFloat
        public init(red: CGFloat, green: CGFloat, blue: CGFloat) { (self.red, self.green, self.blue) = (red, green, blue) }
    }

    /// Covered area, in points from the screen's top left; `left`/`right` hold one colour per row, top first.
    public var rect: CGRect
    public var left: [RGB]
    public var right: [RGB]

    public init(rect: CGRect, left: [RGB], right: [RGB]) {
        (self.rect, self.left, self.right) = (rect, left, right)
    }

    /// Colour at a point (points, screen top left). Outside `rect` the nearest edge continues.
    public func colour(at p: CGPoint) -> RGB {
        guard !left.isEmpty, left.count == right.count else { return RGB(red: 0, green: 0, blue: 0) }
        let row = min(left.count - 1, max(0, Int((p.y - rect.minY) / rect.height * CGFloat(left.count))))
        let t = rect.width > 0 ? min(1, max(0, (p.x - rect.minX) / rect.width)) : 0
        let l = left[row], r = right[row]
        return RGB(red: l.red + (r.red - l.red) * t, green: l.green + (r.green - l.green) * t, blue: l.blue + (r.blue - l.blue) * t)
    }
}

public enum BackgroundSampler {
    static let sampleWidth: CGFloat = 4
    /// Patch margin beside the glyphs: room for names trailing a sliding row by a few points
    /// (the thumbnail row re-centres when the pointer leaves), short of the highlight's edge.
    static let gap: CGFloat = 5

    /// Glyph columns are at least this much brighter than the rect's median luminance.
    static let glyphContrast: CGFloat = 0.25

    /// How far past Vision's box glyphs are looked for: its box can also start inside the first glyph.
    static let glyphSearchMargin: CGFloat = 8
    /// Widest gap between letters (and words) that still belongs to the same caption.
    static let maxLetterGap: CGFloat = 4

    /// Vision's per-caption boxes are loose (they reach into the gap before the next caption), and
    /// sometimes too tight (starting inside the first glyph). Returns `rect` narrowed or widened
    /// horizontally to the run of bright caption glyphs that overlaps it.
    public static func textBounds(for rect: CGRect, in image: CGImage, pointsPerPixel ppp: CGFloat) -> CGRect {
        let search = rect.insetBy(dx: -glyphSearchMargin, dy: 0)
        let px = CGRect(x: search.minX / ppp, y: search.minY / ppp, width: search.width / ppp, height: search.height / ppp)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !px.isEmpty, let crop = image.cropping(to: px) else { return rect }
        let w = crop.width
        let lums = rgb(crop).map(luminance)
        guard !lums.isEmpty else { return rect }
        // Background level: glyphs are a minority of a caption box's pixels, but not always under half.
        let background = lums.sorted()[lums.count / 4]
        let isGlyph = (0..<w).map { x in stride(from: x, to: lums.count, by: w).contains { lums[$0] - background > glyphContrast } }
        // Seed with the glyph columns inside Vision's box, then grow across letter gaps.
        let inside = Int((rect.minX / ppp - px.minX).rounded())..<Int((rect.maxX / ppp - px.minX).rounded())
        guard var first = inside.clamped(to: 0..<w).first(where: { isGlyph[$0] }),
              var last = inside.clamped(to: 0..<w).last(where: { isGlyph[$0] }) else { return rect }
        let gap = max(1, Int((maxLetterGap / ppp).rounded()))
        while let next = (max(0, first - gap - 1)..<first).last(where: { isGlyph[$0] }) { first = next }
        while let next = (last + 1..<min(w, last + gap + 2)).first(where: { isGlyph[$0] }) { last = next }
        let minX = (px.minX + CGFloat(first)) * ppp
        let maxX = (px.minX + CGFloat(last + 1)) * ppp
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    /// Room left above and below the caption: the end of Mission Control's slide moves captions a
    /// few points after the names are already drawn at their resting place.
    static let verticalMargin: CGFloat = 7
    /// Per-row noise inside a sample column above this: a busy background, use the pill.
    static let maxRowNoise: CGFloat = 0.06
    /// Left and right sides this far apart in luminance, in more than `maxDifferingRows` of the
    /// rows: the caption sits on a hard edge. (A row or two touching a wallpaper stripe or a
    /// thumbnail's corner is fine: the blend across it is barely visible.)
    static let maxSideDifference: CGFloat = 0.3
    static let maxDifferingRows: CGFloat = 0.25

    /// Samples thin columns just left and right of the caption's glyphs (`rect` in points, top-left origin)
    /// and keeps their colour row by row.
    public static func style(for rect: CGRect, in image: CGImage, pointsPerPixel ppp: CGFloat) -> PatchStyle {
        let glyphs = textBounds(for: rect, in: image, pointsPerPixel: ppp)
        // Top and bottom on whole pixels: each sampled row then maps back onto the pixel row it came
        // from, so edges in the background (the bar's lower edge, a selection frame) line up.
        let top = ((glyphs.minY - verticalMargin) / ppp).rounded(.down) * ppp
        let bottom = ((glyphs.maxY + verticalMargin) / ppp).rounded(.up) * ppp
        let covered = CGRect(x: glyphs.minX - gap, y: top, width: glyphs.width + 2 * gap, height: bottom - top)
        let columns = [
            CGRect(x: covered.minX - sampleWidth, y: covered.minY, width: sampleWidth, height: covered.height),
            CGRect(x: covered.maxX, y: covered.minY, width: sampleWidth, height: covered.height),
        ]
        var sides: [[PatchBackdrop.RGB]] = []
        var noise: [CGFloat] = []
        for column in columns {
            let px = CGRect(x: column.minX / ppp, y: column.minY / ppp,
                            width: column.width / ppp, height: column.height / ppp).integral
            guard px.minX >= 0, px.minY >= 0, px.maxX <= CGFloat(image.width), px.maxY <= CGFloat(image.height),
                  let crop = image.cropping(to: px) else { return .pill }
            let pixels = rgb(crop)
            let w = crop.width
            guard w > 0, !pixels.isEmpty else { return .pill }
            var rows: [PatchBackdrop.RGB] = []
            for start in stride(from: 0, to: pixels.count, by: w) {
                let row = pixels[start..<min(start + w, pixels.count)]
                let n = CGFloat(row.count)
                let sum = row.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
                rows.append(PatchBackdrop.RGB(red: sum.0 / n, green: sum.1 / n, blue: sum.2 / n))
                let lums = row.map(luminance)
                let mean = lums.reduce(0, +) / n
                noise.append((lums.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n).squareRoot())
            }
            sides.append(rows)
        }
        guard sides.count == 2, sides[0].count == sides[1].count, !noise.isEmpty else { return .pill }
        let meanNoise = noise.reduce(0, +) / CGFloat(noise.count)
        let differingRows = zip(sides[0], sides[1]).filter { abs(luminance($0) - luminance($1)) > maxSideDifference }.count
        guard meanNoise <= maxRowNoise, CGFloat(differingRows) <= maxDifferingRows * CGFloat(sides[0].count) else { return .pill }
        return .backdrop(PatchBackdrop(rect: covered, left: sides[0], right: sides[1]))
    }

    static func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
    static func luminance(_ c: PatchBackdrop.RGB) -> CGFloat { luminance((c.red, c.green, c.blue)) }

    static func rgb(_ image: CGImage) -> [(CGFloat, CGFloat, CGFloat)] {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: buffer.count, by: 4).map { i -> (CGFloat, CGFloat, CGFloat) in
            let r = CGFloat(buffer[i]) / 255
            let g = CGFloat(buffer[i + 1]) / 255
            let b = CGFloat(buffer[i + 2]) / 255
            return (r, g, b)
        }
    }
}
