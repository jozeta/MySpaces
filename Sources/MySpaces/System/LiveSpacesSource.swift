import Foundation
import MySpacesCore

// Private, read-only SkyLight functions (stable for many macOS releases; used by yabai et al.).
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

struct LiveSpacesSource: SpacesSource {
    func currentSpaces() throws -> [Space] {
        let monitors = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()) as? [[String: Any]] ?? []
        let live = SpacesParser.parse(monitors: monitors)
        if !live.isEmpty { return live }
        // Fallback: Dock's preferences (may lag behind the live state).
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        let prefs = UserDefaults(suiteName: "com.apple.spaces")?.dictionaryRepresentation() ?? [:]
        return SpacesParser.parse(spacesPreferences: prefs)
    }
}
