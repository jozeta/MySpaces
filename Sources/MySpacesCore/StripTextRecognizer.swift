import CoreGraphics
import Foundation
import Vision

/// Runs Vision text recognition over overlapping horizontal strips of a screen capture.
public struct StripTextRecognizer: Sendable {
    public var bandHeight: CGFloat
    public var stripHeight: CGFloat
    public var stripStep: CGFloat

    public init(bandHeight: CGFloat = 300, stripHeight: CGFloat = 32, stripStep: CGFloat = 10) {
        self.bandHeight = bandHeight
        self.stripHeight = stripHeight
        self.stripStep = stripStep
    }

    /// `image` is a capture whose top edge is the top of the screen.
    /// `pointsPerPixel` is 1 / backingScaleFactor. Returned rects are screen points, top-left origin.
    public func recognize(in image: CGImage, pointsPerPixel: CGFloat) throws -> [RecognizedLabel] {
        let limit = min(bandHeight, CGFloat(image.height) * pointsPerPixel)
        var found: [RecognizedLabel] = []
        var top: CGFloat = 0
        while top + stripHeight <= limit + 0.5 {
            let pixelRect = CGRect(x: 0, y: (top / pointsPerPixel).rounded(.down),
                                   width: CGFloat(image.width), height: (stripHeight / pointsPerPixel).rounded(.down))
            if let strip = image.cropping(to: pixelRect) {
                for label in try recognizeStrip(strip, top: top, pointsPerPixel: pointsPerPixel) {
                    merge(label, into: &found)
                }
            }
            top += stripStep
        }
        return found.sorted { $0.rect.minX < $1.rect.minX }
    }

    /// Loads the Vision model (~24 s cold on first use) so later scans are fast.
    public static func prewarm() {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size * 4, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size * 4, height: size))
        guard let image = ctx.makeImage() else { return }
        _ = try? StripTextRecognizer(bandHeight: CGFloat(size), stripHeight: CGFloat(size), stripStep: CGFloat(size))
            .recognize(in: image, pointsPerPixel: 1)
    }

    private func recognizeStrip(_ strip: CGImage, top: CGFloat, pointsPerPixel: CGFloat) throws -> [RecognizedLabel] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.customWords = ["Desktop"]
        try VNImageRequestHandler(cgImage: strip, options: [:]).perform([request])
        let width = CGFloat(strip.width) * pointsPerPixel
        let height = CGFloat(strip.height) * pointsPerPixel
        return (request.results ?? []).flatMap { observation -> [RecognizedLabel] in
            // Prefer a candidate that reads as a "Desktop N" caption (e.g. over "Deskton 5").
            let candidates = observation.topCandidates(3)
            guard let candidate = candidates.first(where: { $0.string.contains(Self.captionPattern) }) ?? candidates.first
            else { return [] }
            return Self.segments(of: candidate.string).compactMap { range in
                let text = candidate.string[range].trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
                // `box` is normalised with a bottom-left origin.
                return RecognizedLabel(text: text, rect: CGRect(
                    x: box.minX * width, y: top + (1 - box.maxY) * height,
                    width: box.width * width, height: box.height * height))
            }
        }
    }

    nonisolated(unsafe) static let captionPattern = #/Desktop \d{1,2}/#

    /// Vision often returns a whole caption row as one line ("Desktop 1 Desktop 2 ...").
    /// Split it into each "Desktop N" match plus the text between matches.
    static func segments(of string: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = string.startIndex
        for match in string.matches(of: captionPattern) {
            if cursor < match.range.lowerBound { ranges.append(cursor..<match.range.lowerBound) }
            ranges.append(match.range)
            cursor = match.range.upperBound
        }
        if cursor < string.endIndex { ranges.append(cursor..<string.endIndex) }
        return ranges
    }

    /// Overlapping strips see the same caption several times, sometimes misread. Labels at the
    /// same position are one caption: prefer a "Desktop N" reading, then the taller (unclipped) box.
    private func merge(_ label: RecognizedLabel, into found: inout [RecognizedLabel]) {
        guard let i = found.firstIndex(where: {
            abs($0.rect.midX - label.rect.midX) < 12 && abs($0.rect.midY - label.rect.midY) < 12
        }) else {
            found.append(label)
            return
        }
        if Self.rank(label) > Self.rank(found[i]) { found[i] = label }
    }

    private static func rank(_ label: RecognizedLabel) -> (Int, CGFloat) {
        (label.text.wholeMatch(of: captionPattern) != nil ? 1 : 0, label.rect.height)
    }
}
