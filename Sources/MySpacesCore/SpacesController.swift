import Foundation

/// A Space list plus where it came from. Fallback data (Dock's preferences) may lag behind
/// and spells display identifiers differently, so it is shown but never used for pruning.
public struct SpacesRead {
    public let spaces: [Space]
    public let isFallback: Bool

    public init(spaces: [Space], isFallback: Bool) {
        self.spaces = spaces
        self.isFallback = isFallback
    }
}

public protocol SpacesSource { func currentSpaces() throws -> SpacesRead }
public protocol HotkeySource { func hotkeys() -> SpaceHotkeys }
public protocol KeyPosting { func post(_ chord: KeyChord, times: Int) }

/// UI-independent orchestration: reading Spaces, naming, pruning and switching.
public final class SpacesController {
    public private(set) var spaces: [Space] = []
    public private(set) var rows: [SpaceRow] = []
    public private(set) var lastError: String?

    private let source: SpacesSource
    private let store: NameStore
    private let hotkeySource: HotkeySource
    private let keys: KeyPosting
    private let reconciler = NameReconciler()

    public init(source: SpacesSource, store: NameStore, hotkeys: HotkeySource, keys: KeyPosting) {
        self.source = source
        self.store = store
        self.hotkeySource = hotkeys
        self.keys = keys
    }

    public var names: [String: String] { store.names }

    public var primaryDisplaySpaces: [Space] {
        spaces.primaryDisplayID.map { spaces.onDisplay($0) } ?? []
    }

    public var hasMultipleDisplaysWithSpaces: Bool { spaces.displayIDs.count > 1 }

    public func refresh() {
        do {
            let read = try source.currentSpaces()
            guard !read.spaces.isEmpty else { throw CocoaError(.fileReadUnknown) }
            spaces = read.spaces
            lastError = nil
            if !read.isFallback {
                let prune = reconciler.keysToPrune(storedKeys: Set(store.names.keys), spaces: read.spaces)
                try? store.removeNames(for: prune)
            }
        } catch {
            lastError = "Couldn't read Spaces"
        }
        rows = SpaceRowBuilder.rows(for: spaces, names: store.names)
    }

    public func rename(key: String, to name: String) throws {
        try store.setName(name, for: key)
        rows = SpaceRowBuilder.rows(for: spaces, names: store.names)
    }

    @discardableResult
    public func switchTo(key: String) -> NavigationPlan {
        let display = primaryDisplaySpaces
        guard let target = display.first(where: { $0.key == key }) else { return .unavailable }
        let plan = NavigationPlanner.plan(to: target, in: display, hotkeys: hotkeySource.hotkeys())
        switch plan {
        case .direct(let chord): keys.post(chord, times: 1)
        case .step(let chord, let count): keys.post(chord, times: count)
        case .alreadyThere, .unavailable: break
        }
        return plan
    }
}
