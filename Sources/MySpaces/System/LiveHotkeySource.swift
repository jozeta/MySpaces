import Foundation
import MySpacesCore

struct LiveHotkeySource: HotkeySource {
    func hotkeys() -> SpaceHotkeys {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        let raw = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        return SpaceHotkeys.parse(symbolicHotKeys: raw)
    }
}
