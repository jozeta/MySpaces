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

    /// Captions in a row are drawn on one centre line; their boxes vary by a point or so.
    public static let rowTolerance: CGFloat = 3
    /// Caption boxes in a row are 14–21 pt tall; one much taller than the rest took in something else.
    public static let maxRowHeightRatio: CGFloat = 1.4

    /// The row's centre line and caption height (medians: an odd box out does not move them).
    private static func rowLine(_ placements: [LabelPlacement]) -> (midY: CGFloat, height: CGFloat)? {
        guard !placements.isEmpty else { return nil }
        let mids = placements.map(\.rect.midY).sorted(), heights = placements.map(\.rect.height).sorted()
        return (mids[mids.count / 2], heights[heights.count / 2])
    }

    private static func isOnRow(_ rect: CGRect, _ line: (midY: CGFloat, height: CGFloat)) -> Bool {
        abs(rect.midY - line.midY) <= rowTolerance && rect.height <= line.height * maxRowHeightRatio
    }

    /// Whether the boxes lie on one centre line at one height, as Mission Control's captions do.
    /// A box off the line, or much taller, covers something besides its caption: Vision stretched
    /// it over something bright nearby (a white edge at the bottom of its thumbnail, a dragged
    /// thumbnail crossing the row).
    public static func isOneRow(_ placements: [LabelPlacement]) -> Bool {
        guard let line = rowLine(placements) else { return true }
        return placements.allSatisfy { isOnRow($0.rect, line) }
    }

    /// The boxes, with any not on the row moved onto its centre line at its caption height
    /// (the median of the boxes that are on it). The horizontal extent is kept.
    public static func snappedToRow(_ placements: [LabelPlacement]) -> [LabelPlacement] {
        guard let line = rowLine(placements) else { return placements }
        let heights = placements.filter { isOnRow($0.rect, line) }.map(\.rect.height).sorted()
        guard !heights.isEmpty else { return placements }
        let height = heights[heights.count / 2]
        return placements.map { p in
            guard !isOnRow(p.rect, line) else { return p }
            return LabelPlacement(rect: CGRect(x: p.rect.minX, y: line.midY - height / 2, width: p.rect.width, height: height),
                                  name: p.name, spaceKey: p.spaceKey, maxWidth: p.maxWidth)
        }
    }

    public static func same(_ a: [LabelPlacement], _ b: [LabelPlacement], tolerance: CGFloat = defaultTolerance) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.name == y.name && abs(x.rect.midX - y.rect.midX) < tolerance && abs(x.rect.midY - y.rect.midY) < tolerance
        }
    }
}
