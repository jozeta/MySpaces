import Foundation

public enum NavigationPlan: Equatable {
    case alreadyThere
    case direct(KeyChord)
    case step(KeyChord, count: Int)
    case unavailable
}

extension NavigationPlan {
    /// How long to wait before checking that a switch arrived: each step is one slide animation.
    public var verificationDelay: TimeInterval {
        switch self {
        case .direct: return 1.0
        case .step(_, let count): return 1.0 + 0.4 * Double(count)
        case .alreadyThere, .unavailable: return 0
        }
    }
}

public enum NavigationPlanner {
    /// `displaySpaces` are the Spaces of the target's display, in Mission Control order.
    public static func plan(to target: Space, in displaySpaces: [Space], hotkeys: SpaceHotkeys) -> NavigationPlan {
        guard let currentIndex = displaySpaces.firstIndex(where: \.isCurrent),
              let targetIndex = displaySpaces.firstIndex(of: target) else { return .unavailable }
        if currentIndex == targetIndex { return .alreadyThere }
        if let number = displaySpaces.desktopNumber(of: target), let chord = hotkeys.desktops[number] {
            return .direct(chord)
        }
        let delta = targetIndex - currentIndex
        guard let chord = delta > 0 ? hotkeys.moveRight : hotkeys.moveLeft else { return .unavailable }
        return .step(chord, count: abs(delta))
    }
}
