import Darwin
import Foundation
import MySpacesCore

/// Reads Spaces from SkyLight's private, read-only CGSCopyManagedDisplaySpaces (stable for many
/// macOS releases; used by yabai et al.), falling back to Dock's preferences.
struct LiveSpacesSource: SpacesSource {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    // Resolved at runtime so a macOS without these symbols still launches and uses the fallback.
    private static let connection: DefaultConnection? = symbol("_CGSDefaultConnection")
    private static let copySpaces: CopyManagedDisplaySpaces? = symbol("CGSCopyManagedDisplaySpaces")

    private static func symbol<T>(_ name: String) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil } // RTLD_DEFAULT
        return unsafeBitCast(pointer, to: T.self)
    }

    func currentSpaces() throws -> SpacesRead {
        if let connection = Self.connection, let copySpaces = Self.copySpaces,
           let monitors = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] {
            let live = SpacesParser.parse(monitors: monitors)
            if !live.isEmpty { return SpacesRead(spaces: live, isFallback: false) }
        }
        log.notice("CGSCopyManagedDisplaySpaces unavailable; using com.apple.spaces fallback")
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        let prefs = UserDefaults(suiteName: "com.apple.spaces")?.dictionaryRepresentation() ?? [:]
        return SpacesRead(spaces: SpacesParser.parse(spacesPreferences: prefs), isFallback: true)
    }
}
