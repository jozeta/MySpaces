import CoreGraphics
import Foundation

public enum PatchStyle: Equatable, Sendable, Codable {
    /// Paint over the caption with this sRGB colour, then draw the name.
    case native(red: CGFloat, green: CGFloat, blue: CGFloat)
    /// Background too busy to match: use the frosted pill.
    case pill
}

public enum BackgroundSampler {
    public static let maxLuminanceStdDev: CGFloat = 0.08
    static let sampleWidth: CGFloat = 4
    static let gap: CGFloat = 3

    /// Glyph columns are at least this much brighter than the rect's median luminance.
    static let glyphContrast: CGFloat = 0.25

    /// Vision's per-caption boxes are loose (they reach into the gap before the next caption).
    /// Narrows `rect` horizontally to the columns containing bright caption glyphs.
    public static func textBounds(for rect: CGRect, in image: CGImage, pointsPerPixel ppp: CGFloat) -> CGRect {
        let px = CGRect(x: rect.minX / ppp, y: rect.minY / ppp, width: rect.width / ppp, height: rect.height / ppp)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !px.isEmpty, let crop = image.cropping(to: px) else { return rect }
        let w = crop.width
        let lums = rgb(crop).map { 0.2126 * $0.0 + 0.7152 * $0.1 + 0.0722 * $0.2 }
        guard !lums.isEmpty else { return rect }
        let median = lums.sorted()[lums.count / 2]
        var glyphColumns: [Int] = []
        for x in 0..<w where stride(from: x, to: lums.count, by: w).contains(where: { lums[$0] - median > glyphContrast }) {
            glyphColumns.append(x)
        }
        guard let first = glyphColumns.first, let last = glyphColumns.last else { return rect }
        let minX = (px.minX + CGFloat(first)) * ppp
        let maxX = (px.minX + CGFloat(last + 1)) * ppp
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    /// Samples thin columns just left and right of the caption's glyphs (`rect` in points, top-left origin).
    public static func style(for rect: CGRect, in image: CGImage, pointsPerPixel ppp: CGFloat) -> PatchStyle {
        let rect = textBounds(for: rect, in: image, pointsPerPixel: ppp)
        let columns = [
            CGRect(x: rect.minX - gap - sampleWidth, y: rect.minY, width: sampleWidth, height: rect.height),
            CGRect(x: rect.maxX + gap, y: rect.minY, width: sampleWidth, height: rect.height),
        ]
        var pixels: [(CGFloat, CGFloat, CGFloat)] = []
        for column in columns {
            let px = CGRect(x: column.minX / ppp, y: column.minY / ppp,
                            width: column.width / ppp, height: column.height / ppp).integral
            guard px.minX >= 0, px.minY >= 0, px.maxX <= CGFloat(image.width), px.maxY <= CGFloat(image.height),
                  let crop = image.cropping(to: px) else { return .pill }
            pixels += rgb(crop)
        }
        guard !pixels.isEmpty else { return .pill }
        let n = CGFloat(pixels.count)
        let mean = pixels.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        let (r, g, b) = (mean.0 / n, mean.1 / n, mean.2 / n)
        let lums = pixels.map { 0.2126 * $0.0 + 0.7152 * $0.1 + 0.0722 * $0.2 }
        let lumMean = lums.reduce(0, +) / n
        let std = (lums.map { ($0 - lumMean) * ($0 - lumMean) }.reduce(0, +) / n).squareRoot()
        return std > maxLuminanceStdDev ? .pill : .native(red: r, green: g, blue: b)
    }

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
