import Foundation

public struct Space: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case desktop
        case fullscreen(appName: String)
    }

    public let managedID: Int
    public let uuid: String
    public let displayID: String
    public let kind: Kind
    public let isCurrent: Bool

    public init(managedID: Int, uuid: String, displayID: String, kind: Kind, isCurrent: Bool) {
        self.managedID = managedID
        self.uuid = uuid
        self.displayID = displayID
        self.kind = kind
        self.isCurrent = isCurrent
    }

    /// Stable identity used to store names. The first desktop on a display has an empty UUID.
    public var key: String { uuid.isEmpty ? "main:\(displayID)" : uuid }

    public var isDesktop: Bool { kind == .desktop }
}

extension Array where Element == Space {
    /// Display IDs in first-seen order.
    public var displayIDs: [String] {
        var seen: [String] = []
        for space in self where !seen.contains(space.displayID) { seen.append(space.displayID) }
        return seen
    }

    public var primaryDisplayID: String? { first?.displayID }

    public func onDisplay(_ id: String) -> [Space] { filter { $0.displayID == id } }

    /// 1-based "Desktop N" number as macOS shows it: counts only desktops on the same display.
    public func desktopNumber(of space: Space) -> Int? {
        guard space.isDesktop else { return nil }
        let desktops = onDisplay(space.displayID).filter(\.isDesktop)
        return desktops.firstIndex(of: space).map { $0 + 1 }
    }
}
