/// Names follow their captions through the end of Mission Control's slide. When they keep the
/// same non-zero offset for a while, the layout was recorded before the slide ended: that offset
/// is where it really rests, and the layout should be moved there so the next open needs no follow.
public struct RestingOffset: Sendable {
    public let requiredReadings: Int
    private var last: (dx: Int, dy: Int)?
    private var count = 0

    public init(requiredReadings: Int) { self.requiredReadings = requiredReadings }

    /// True once, when a non-zero offset has been read `requiredReadings` times in a row.
    public mutating func observe(dx: Int, dy: Int) -> Bool {
        if let last, last == (dx, dy) { count += 1 } else { last = (dx, dy); count = 1 }
        guard dx != 0 || dy != 0, count >= requiredReadings else { return false }
        reset()
        return true
    }

    public mutating func reset() {
        last = nil
        count = 0
    }
}
