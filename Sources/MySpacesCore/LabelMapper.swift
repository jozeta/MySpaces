import CoreGraphics
import Foundation

public struct RecognizedLabel: Equatable, Sendable {
    public let text: String
    /// Screen points, top-left origin.
    public let rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

public struct LabelPlacement: Equatable, Sendable {
    public let rect: CGRect
    public let name: String
    public let spaceKey: String
    /// Widest the overlay may be without reaching a neighbouring caption.
    public let maxWidth: CGFloat

    public init(rect: CGRect, name: String, spaceKey: String, maxWidth: CGFloat) {
        self.rect = rect
        self.name = name
        self.spaceKey = spaceKey
        self.maxWidth = maxWidth
    }
}

public enum LabelMapper {
    static let soloMaxWidth: CGFloat = 240
    static let neighbourMargin: CGFloat = 4
    static let sameRowTolerance: CGFloat = 12

    public static func desktopNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: #/Desktop (\d{1,2})/#) else { return nil }
        return Int(match.1)
    }

    /// Maps "Desktop N" captions to named desktops. Returns nil when the captions do not
    /// match the display's desktops exactly (count or numbering), so nothing is drawn.
    public static func placements(labels: [RecognizedLabel], displaySpaces: [Space], names: [String: String]) -> [LabelPlacement]? {
        let desktops = displaySpaces.filter(\.isDesktop)
        var byNumber: [Int: RecognizedLabel] = [:]
        for label in labels {
            guard let n = desktopNumber(in: label.text) else { continue }
            if byNumber[n] != nil { return nil }
            byNumber[n] = label
        }
        guard byNumber.count == desktops.count,
              Set(byNumber.keys) == Set(1...max(desktops.count, 1)) || desktops.isEmpty else { return nil }

        return desktops.enumerated().compactMap { index, space in
            guard let name = names[space.key], let label = byNumber[index + 1] else { return nil }
            return LabelPlacement(rect: label.rect, name: name, spaceKey: space.key,
                                  maxWidth: maxWidth(for: label, among: labels))
        }
    }

    static func maxWidth(for label: RecognizedLabel, among labels: [RecognizedLabel]) -> CGFloat {
        let distances = labels
            .filter { $0 != label && abs($0.rect.midY - label.rect.midY) < sameRowTolerance }
            .map { abs($0.rect.midX - label.rect.midX) }
        guard let nearest = distances.min() else { return soloMaxWidth }
        return min(soloMaxWidth, nearest - neighbourMargin)
    }
}
