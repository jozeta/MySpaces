import CoreGraphics
import Foundation

/// Mission Control's Spaces bar slides in and animates when it expands, so a single scan can
/// catch captions mid-motion. A layout counts as settled once enough consecutive scans agree.
/// Slow phases of an animation (ease-in) can look still across two scans, so the overlay uses
/// three readings within 1 pt.
public final class LayoutStabilizer {
    public static let defaultTolerance: CGFloat = 2
    /// For checking a layout already shown against a later text-recognition read: Vision's boxes
    /// jitter a few points between reads of a still screen, while a real change (a desktop added or
    /// removed, the bar expanding) moves captions by a whole slot. Small real moves are followed by
    /// the pixel fingerprint, not by rescans.
    public static let rescanTolerance: CGFloat = 8
    private let requiredAgreeing: Int
    private let tolerance: CGFloat
    private var previous: [LabelPlacement]?
    private var agreeing = 0

    public init(requiredAgreeing: Int = 2, tolerance: CGFloat = LayoutStabilizer.defaultTolerance) {
        self.requiredAgreeing = max(2, requiredAgreeing)
        self.tolerance = tolerance
    }

    public func reset() {
        previous = nil
        agreeing = 0
    }

    /// Returns true when `layout` and the readings before it agree `requiredAgreeing` times in a row.
    public func observe(_ layout: [LabelPlacement]) -> Bool {
        defer { previous = layout }
        if let previous, Self.same(previous, layout, tolerance: tolerance) {
            agreeing += 1
        } else {
            agreeing = 1
        }
        return agreeing >= requiredAgreeing
    }

    public static func same(_ a: [LabelPlacement], _ b: [LabelPlacement], tolerance: CGFloat = defaultTolerance) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.name == y.name && abs(x.rect.midX - y.rect.midX) < tolerance && abs(x.rect.midY - y.rect.midY) < tolerance
        }
    }
}
