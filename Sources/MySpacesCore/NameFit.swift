import CoreGraphics

/// How wide a name's box is drawn, and whether a name too long for its slot fades out at the
/// end instead of being cut off with "…".
public struct NameFit: Equatable, Sendable {
    /// Length of the fade at the end of a too-long name, in points.
    public static let fadeLength: CGFloat = 18

    public let width: CGFloat
    public let fades: Bool
    public var fadeLength: CGFloat { fades ? Self.fadeLength : 0 }
    /// Where the fade starts, as a fraction of the text area's width.
    public let fadeStart: CGFloat

    /// `minimumWidth` covers the caption underneath; `maximumWidth` is the slot before the next one.
    public init(textWidth: CGFloat, minimumWidth: CGFloat, maximumWidth: CGFloat, padding: CGFloat) {
        let wanted = max(minimumWidth, textWidth + padding)
        width = min(wanted, max(minimumWidth, maximumWidth))
        let textArea = width - padding
        fades = textWidth > textArea
        fadeStart = fades && textArea > 0 ? max(0, (textArea - Self.fadeLength) / textArea) : 1
    }
}
