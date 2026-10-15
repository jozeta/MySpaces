import CoreGraphics

/// How wide a name's box is drawn, and whether a name too long for its slot fades out at the
/// end instead of being cut off with "…".
public struct NameFit: Equatable, Sendable {
    /// Default length of the fade at the end of a too-long name, in points (Mission Control's captions).
    public static let fadeLength: CGFloat = 18

    public let width: CGFloat
    public let fades: Bool
    /// Length of the fade, in points (0 when the name fits).
    public let fadeLength: CGFloat
    /// Where the fade starts, as a fraction of the text area's width.
    public let fadeStart: CGFloat

    /// `minimumWidth` covers the caption underneath; `maximumWidth` is the slot before the next one.
    /// `fadeLength` should grow with the text size: a short fade on large text reads as a hard cut.
    public init(textWidth: CGFloat, minimumWidth: CGFloat, maximumWidth: CGFloat, padding: CGFloat,
                fadeLength: CGFloat = NameFit.fadeLength) {
        let wanted = max(minimumWidth, textWidth + padding)
        width = min(wanted, max(minimumWidth, maximumWidth))
        let textArea = width - padding
        fades = textWidth > textArea
        self.fadeLength = fades ? fadeLength : 0
        fadeStart = fades && textArea > 0 ? max(0, (textArea - fadeLength) / textArea) : 1
    }
}
