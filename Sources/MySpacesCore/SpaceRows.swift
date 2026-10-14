import Foundation

public struct SpaceRow: Equatable, Identifiable {
    public var id: String { space.key }
    public let space: Space
    public let title: String
    public let subtitle: String
    public let isRenamable: Bool
    public let hasCustomName: Bool
}

public enum SpaceRowBuilder {
    /// Rows for the primary display, in Mission Control order.
    public static func rows(for spaces: [Space], names: [String: String]) -> [SpaceRow] {
        guard let primary = spaces.primaryDisplayID else { return [] }
        let display = spaces.onDisplay(primary)
        return display.map { space in
            switch space.kind {
            case .desktop:
                let number = display.desktopNumber(of: space) ?? 0
                let custom = names[space.key]
                return SpaceRow(
                    space: space,
                    title: custom ?? "Desktop \(number)",
                    subtitle: "Space \(number)" + (space.isCurrent ? " · Current desktop" : ""),
                    isRenamable: true,
                    hasCustomName: custom != nil
                )
            case .fullscreen(let appName):
                return SpaceRow(
                    space: space,
                    title: appName,
                    subtitle: "Full screen" + (space.isCurrent ? " · Current" : ""),
                    isRenamable: false,
                    hasCustomName: false
                )
            }
        }
    }
}

/// Decides which stored names belong to deleted Spaces. A key is pruned only after
/// it is missing from two consecutive non-empty Space lists.
public final class NameReconciler {
    private var missingCounts: [String: Int] = [:]

    public init() {}

    public func keysToPrune(storedKeys: Set<String>, spaces: [Space]) -> Set<String> {
        guard !spaces.isEmpty else { return [] }
        let present = Set(spaces.map(\.key))
        var prune: Set<String> = []
        for key in storedKeys {
            if present.contains(key) {
                missingCounts[key] = nil
            } else {
                let count = (missingCounts[key] ?? 0) + 1
                missingCounts[key] = count
                if count >= 2 { prune.insert(key) }
            }
        }
        for key in prune { missingCounts[key] = nil }
        return prune
    }
}
