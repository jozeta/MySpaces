/// Names follow their captions through the end of Mission Control's slide. When they keep the
/// same non-zero offset for a while, the layout was recorded before the slide ended: that offset
/// is where it really rests, and the layout should be moved there so the next open needs no follow.
public struct RestingOffset: Sendable {
    public let requiredReadings: Int
    /// Whether an unchanged zero offset counts too (deciding that a layout not yet shown is at rest).
    public let countsZero: Bool
    private var last: (dx: Int, dy: Int)?
    private var count = 0

    public init(requiredReadings: Int, countsZero: Bool = false) {
        self.requiredReadings = requiredReadings
        self.countsZero = countsZero
    }

    /// True once, when an offset (non-zero unless `countsZero`) has been read `requiredReadings` times in a row.
    public mutating func observe(dx: Int, dy: Int) -> Bool {
        if let last, last == (dx, dy) { count += 1 } else { last = (dx, dy); count = 1 }
        guard countsZero || dx != 0 || dy != 0, count >= requiredReadings else { return false }
        reset()
        return true
    }

    public mutating func reset() {
        last = nil
        count = 0
    }
}
