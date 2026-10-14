import CoreGraphics
import Foundation

/// Mission Control's Spaces bar slides in and animates when it expands, so a single scan can
/// catch captions mid-motion. A layout counts as settled once two consecutive scans agree.
public final class LayoutStabilizer {
    static let tolerance: CGFloat = 2
    private var previous: [LabelPlacement]?

    public init() {}

    public func reset() { previous = nil }

    /// Returns true when `layout` matches the previous observation.
    public func observe(_ layout: [LabelPlacement]) -> Bool {
        defer { previous = layout }
        guard let previous else { return false }
        return Self.same(previous, layout)
    }

    public static func same(_ a: [LabelPlacement], _ b: [LabelPlacement]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.name == y.name && abs(x.rect.midX - y.rect.midX) < tolerance && abs(x.rect.midY - y.rect.midY) < tolerance
        }
    }
}
