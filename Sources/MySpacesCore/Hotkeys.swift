import Foundation

public struct KeyChord: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifierFlags: UInt64

    public init(keyCode: UInt16, modifierFlags: UInt64) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

public struct SpaceHotkeys: Equatable, Sendable {
    public var moveLeft: KeyChord?
    public var moveRight: KeyChord?
    /// Desktop number (1...16) → enabled "Switch to Desktop N" shortcut.
    public var desktops: [Int: KeyChord]

    public init(moveLeft: KeyChord?, moveRight: KeyChord?, desktops: [Int: KeyChord]) {
        self.moveLeft = moveLeft
        self.moveRight = moveRight
        self.desktops = desktops
    }

    static let moveLeftID = "79", moveRightID = "81", firstDesktopID = 118
    static let defaultMoveFlags: UInt64 = 0x840000

    /// Parses the `AppleSymbolicHotKeys` dictionary of `com.apple.symbolichotkeys`.
    public static func parse(symbolicHotKeys raw: [String: Any]?) -> SpaceHotkeys {
        let raw = raw ?? [:]
        func chord(_ id: String) -> (enabled: Bool, chord: KeyChord?)? {
            guard let entry = raw[id] as? [String: Any] else { return nil }
            let enabled = entry["enabled"] as? Bool ?? false
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int] ?? []
            guard params.count >= 3 else { return (enabled, nil) }
            return (enabled, KeyChord(keyCode: UInt16(params[1]), modifierFlags: UInt64(params[2])))
        }
        func move(_ id: String, defaultKey: UInt16) -> KeyChord? {
            guard let found = chord(id) else { return KeyChord(keyCode: defaultKey, modifierFlags: defaultMoveFlags) }
            return found.enabled ? found.chord : nil
        }
        var desktops: [Int: KeyChord] = [:]
        for n in 1...16 {
            if let found = chord(String(firstDesktopID + n - 1)), found.enabled, let c = found.chord {
                desktops[n] = c
            }
        }
        return SpaceHotkeys(
            moveLeft: move(moveLeftID, defaultKey: 123),
            moveRight: move(moveRightID, defaultKey: 124),
            desktops: desktops
        )
    }
}
