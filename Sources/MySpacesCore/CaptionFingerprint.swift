import CoreGraphics
import Foundation

/// A small greyscale snapshot of the pixels under Mission Control's captions. Comparing a fresh
/// capture to the snapshot taken when names were drawn tells, within one frame and without OCR,
/// whether the captions are still there (show / keep names) or have moved or vanished
/// (Mission Control closing, bar sliding or expanding: hide names).
public struct CaptionFingerprint: Equatable, Sendable, Codable {
    /// Worst slice difference (0...1) below which two snapshots show the same captions.
    public static let matchThreshold: Double = 0.04
    /// High enough to tell "Desktop 3" from "Desktop 4" (one digit differs).
    static let sampleWidth = 96, sampleHeight = 24
    /// Slices per caption: a single differing digit dominates its slice instead of being averaged
    /// away over the whole caption.
    static let slices = 12

    let samples: [UInt8]
    let count: Int

    /// `rects` are caption boxes in screen points (top-left origin); the image's top is the screen top.
    public init?(image: CGImage, rects: [CGRect], pointsPerPixel ppp: CGFloat) {
        guard let grey = GreyImage(image) else { return nil }
        self.init(grey: grey, rects: rects, pointsPerPixel: ppp)
    }

    init?(grey: GreyImage, rects: [CGRect], pointsPerPixel ppp: CGFloat) {
        var samples: [UInt8] = []
        samples.reserveCapacity(rects.count * Self.sampleWidth * Self.sampleHeight)
        for rect in rects {
            guard grey.sample(rect: rect, pointsPerPixel: ppp, width: Self.sampleWidth,
                              height: Self.sampleHeight, into: &samples) else { return nil }
        }
        self.samples = samples
        self.count = rects.count
    }

    /// Worst slice difference over all captions, in 0...1 (1 when the caption count differs).
    /// Each caption is compared after removing its own mean brightness, so a slightly brighter or
    /// darker bar (blurred wallpaper behind it changed) does not count as a different caption.
    public func difference(to other: CaptionFingerprint) -> Double {
        captionDifferences(to: other).max() ?? 1
    }

    /// Worst slice difference per caption, in order (all 1 when the caption count differs).
    public func captionDifferences(to other: CaptionFingerprint) -> [Double] {
        guard count == other.count, samples.count == other.samples.count, !samples.isEmpty else {
            return Array(repeating: 1, count: max(count, 1))
        }
        let w = Self.sampleWidth, h = Self.sampleHeight, per = w * h
        let sliceWidth = w / Self.slices
        return (0..<count).map { c in
            let base = c * per
            var sumA = 0, sumB = 0
            for i in base..<(base + per) { sumA += Int(samples[i]); sumB += Int(other.samples[i]) }
            let offset = Double(sumA - sumB) / Double(per)
            var worst = 0.0
            for slice in 0..<Self.slices {
                var total = 0.0
                for y in 0..<h {
                    let row = base + y * w + slice * sliceWidth
                    for i in row..<(row + sliceWidth) {
                        total += abs(Double(samples[i]) - Double(other.samples[i]) - offset)
                    }
                }
                worst = max(worst, total / Double(sliceWidth * h) / 255)
            }
            return worst
        }
    }

    /// Searches whole-point shifts around `expectedAt` for the remembered captions. Mission
    /// Control's animations end with a slow drift of a few points; this finds the captions during
    /// that drift so names can follow them instead of waiting for complete rest.
    /// Returns the best shift (in points) when it matches, nil when the captions are not nearby.
    public static func locate(_ reference: CaptionFingerprint, expectedAt rects: [CGRect], in image: CGImage,
                              pointsPerPixel ppp: CGFloat, maxShift: CGSize) -> (dx: Int, dy: Int)? {
        guard let grey = GreyImage(image) else { return nil }
        var best: (dx: Int, dy: Int, difference: Double)?
        let mx = Int(maxShift.width), my = Int(maxShift.height)
        for dy in -my...my {
            for dx in -mx...mx {
                let shifted = rects.map { $0.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)) }
                guard let candidate = CaptionFingerprint(grey: grey, rects: shifted, pointsPerPixel: ppp) else { continue }
                let d = reference.difference(to: candidate)
                if d < (best?.difference ?? .infinity) { best = (dx, dy, d) }
            }
        }
        guard let best, best.difference < matchThreshold else { return nil }
        return (best.dx, best.dy)
    }

    public func matches(_ other: CaptionFingerprint) -> Bool {
        difference(to: other) < Self.matchThreshold
    }
}

/// An 8-bit greyscale copy of a capture, converted once and then sampled many times.
struct GreyImage {
    let width: Int, height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        pixels = buffer
    }

    /// Bilinear samples of `rect` (points, top-left origin) on a `width` × `height` grid.
    func sample(rect: CGRect, pointsPerPixel ppp: CGFloat, width w: Int, height h: Int, into out: inout [UInt8]) -> Bool {
        let px = CGRect(x: rect.minX / ppp, y: rect.minY / ppp, width: rect.width / ppp, height: rect.height / ppp)
        guard px.minX >= 0, px.minY >= 0, px.maxX <= CGFloat(width), px.maxY <= CGFloat(height),
              px.width > 1, px.height > 1 else { return false }
        let sx = Double(px.width) / Double(w), sy = Double(px.height) / Double(h)
        for gy in 0..<h {
            let fy = Double(px.minY) + (Double(gy) + 0.5) * sy - 0.5
            let y0 = max(0, min(height - 1, Int(fy.rounded(.down)))), y1 = min(height - 1, y0 + 1)
            let ty = max(0, min(1, fy - Double(y0)))
            for gx in 0..<w {
                let fx = Double(px.minX) + (Double(gx) + 0.5) * sx - 0.5
                let x0 = max(0, min(width - 1, Int(fx.rounded(.down)))), x1 = min(width - 1, x0 + 1)
                let tx = max(0, min(1, fx - Double(x0)))
                let a = Double(pixels[y0 * width + x0]), b = Double(pixels[y0 * width + x1])
                let c = Double(pixels[y1 * width + x0]), d = Double(pixels[y1 * width + x1])
                let top = a + (b - a) * tx, bottom = c + (d - c) * tx
                out.append(UInt8(max(0, min(255, (top + (bottom - top) * ty).rounded()))))
            }
        }
        return true
    }
}
