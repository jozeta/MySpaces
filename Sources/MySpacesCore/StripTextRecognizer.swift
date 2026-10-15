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
            for label in try recognizeRow(image, pixelRect: pixelRect, top: top, pointsPerPixel: pointsPerPixel) {
                merge(label, into: &found)
            }
            top += stripStep
        }
        return found.sorted { $0.rect.minX < $1.rect.minX }
    }

    /// Fast path: one strip centred on each known caption row (~0.06 s per row instead of
    /// scanning the whole band).
    public func recognize(in image: CGImage, pointsPerPixel: CGFloat, rowMidYs: [CGFloat]) throws -> [RecognizedLabel] {
        var found: [RecognizedLabel] = []
        for mid in rowMidYs {
            let top = max(0, mid - stripHeight / 2)
            let pixelRect = CGRect(x: 0, y: (top / pointsPerPixel).rounded(.down),
                                   width: CGFloat(image.width), height: (stripHeight / pointsPerPixel).rounded(.down))
            for label in try recognizeRow(image, pixelRect: pixelRect, top: top, pointsPerPixel: pointsPerPixel) {
                merge(label, into: &found)
            }
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

    /// Vision scales a wide image down before reading it, and small captions get lost: a full-width
    /// strip with six desktops dropped "Desktop 6", ~1300 pt wide was hit and miss, ~1000 pt is
    /// reliable. Strips are read as tiles this wide (points)...
    static let tileWidth: CGFloat = 1000
    /// ...overlapping by more than any caption is wide, so each caption is whole in some tile.
    static let tileOverlap: CGFloat = 300
    /// A label this close to a tile's inner edge was cut by it; a neighbouring tile has it whole.
    static let cutMargin: CGFloat = 2

    /// Start and end (pixels) of the tiles covering a strip `width` pixels wide.
    static func tiles(width: CGFloat, pointsPerPixel ppp: CGFloat) -> [(CGFloat, CGFloat)] {
        let tile = (tileWidth / ppp).rounded(), step = ((tileWidth - tileOverlap) / ppp).rounded()
        guard width > tile else { return [(0, width)] }
        var tiles: [(CGFloat, CGFloat)] = []
        var from: CGFloat = 0
        while true {
            let to = min(width, from + tile)
            tiles.append((from, to))
            if to >= width { return tiles }
            from += step
        }
    }

    private func recognizeRow(_ image: CGImage, pixelRect: CGRect, top: CGFloat, pointsPerPixel ppp: CGFloat) throws -> [RecognizedLabel] {
        let width = pixelRect.width
        var labels: [RecognizedLabel] = []
        for (from, to) in Self.tiles(width: width, pointsPerPixel: ppp) {
            let rect = CGRect(x: pixelRect.minX + from, y: pixelRect.minY, width: to - from, height: pixelRect.height)
            guard let strip = image.cropping(to: rect) else { continue }
            let left = rect.minX * ppp, right = rect.maxX * ppp
            let innerLeft = from > 0, innerRight = to < width
            labels += try recognizeStrip(strip, top: top, pointsPerPixel: ppp).compactMap { label in
                let moved = RecognizedLabel(text: label.text, rect: label.rect.offsetBy(dx: left, dy: 0))
                if innerLeft && moved.rect.minX < left + Self.cutMargin { return nil }
                if innerRight && moved.rect.maxX > right - Self.cutMargin { return nil }
                return moved
            }
        }
        return labels
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
