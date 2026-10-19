import Foundation

/// One caption scan at a time. A scan's result can come back after the world moved on (Mission
/// Control closed and the current desktop changed, as when a desktop is clicked in Mission Control)
/// and be dropped; its slot must free up all the same, or no scan ever runs again.
public struct ScanSlot {
    private var current: Int?
    private var issued = 0
    private var startedAt: Date?

    public init() {}

    public var isBusy: Bool { current != nil }

    /// Takes the slot for a new scan; pass the returned id to `end`.
    public mutating func begin(now: Date = Date()) -> Int {
        issued += 1
        current = issued
        startedAt = now
        return issued
    }

    /// The scan with this id is done, whatever became of its result. An older scan ending
    /// (after a `reset`) leaves the newer one's slot alone.
    public mutating func end(_ id: Int) {
        guard id == current else { return }
        current = nil
        startedAt = nil
    }

    /// Frees the slot; the scan running now, if any, ends unheard.
    public mutating func reset() {
        current = nil
        startedAt = nil
    }

    /// A scan has held the slot for longer than any scan takes: its capture never returned.
    public func isStuck(now: Date = Date(), timeout: TimeInterval) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) > timeout
    }
}
