import CoreGraphics
import Foundation

/// A tiny greyscale snapshot of the pixels under Mission Control's captions. Comparing a fresh
/// capture to the snapshot taken when names were drawn tells, within one frame and without OCR,
/// whether the captions are still exactly there (show / keep names) or have moved or vanished
/// (Mission Control closing, bar sliding or expanding: hide names).
public struct CaptionFingerprint: Equatable, Sendable, Codable {
    /// Mean absolute grey difference (0...1) below which two snapshots are the same captions.
    public static let matchThreshold: Double = 0.04
    static let sampleWidth = 48, sampleHeight = 12

    let samples: [UInt8]
    let count: Int

    /// `rects` are caption boxes in screen points (top-left origin); the image's top is the screen top.
    public init?(image: CGImage, rects: [CGRect], pointsPerPixel ppp: CGFloat) {
        var samples: [UInt8] = []
        let w = Self.sampleWidth, h = Self.sampleHeight
        for rect in rects {
            let px = CGRect(x: rect.minX / ppp, y: rect.minY / ppp, width: rect.width / ppp, height: rect.height / ppp).integral
            guard px.minX >= 0, px.minY >= 0, px.maxX <= CGFloat(image.width), px.maxY <= CGFloat(image.height),
                  let crop = image.cropping(to: px) else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h)
            let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            samples += buffer
        }
        self.samples = samples
        self.count = rects.count
    }

    /// Mean absolute difference in 0...1; 1 when the snapshots cover a different number of captions.
    public func difference(to other: CaptionFingerprint) -> Double {
        guard count == other.count, samples.count == other.samples.count, !samples.isEmpty else { return 1 }
        var total = 0
        for i in samples.indices { total += abs(Int(samples[i]) - Int(other.samples[i])) }
        return Double(total) / Double(samples.count) / 255
    }

    public func matches(_ other: CaptionFingerprint) -> Bool {
        difference(to: other) < Self.matchThreshold
    }
}
