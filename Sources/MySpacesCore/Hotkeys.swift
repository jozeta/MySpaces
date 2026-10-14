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
    static let controlFlag: UInt64 = 0x40000
    /// Virtual key codes for the digits 1...9 (macOS default "Switch to Desktop N" keys).
    static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Parses the `AppleSymbolicHotKeys` dictionary of `com.apple.symbolichotkeys`.
    /// An entry without usable parameters (macOS stores just `{enabled = 1}` when the
    /// default key is kept) means the default chord.
    public static func parse(symbolicHotKeys raw: [String: Any]?) -> SpaceHotkeys {
        let raw = raw ?? [:]
        func chord(_ id: String, default fallback: KeyChord?) -> KeyChord? {
            guard let entry = raw[id] as? [String: Any] else { return nil }
            guard entry["enabled"] as? Bool ?? false else { return nil }
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int] ?? []
            guard params.count >= 3 else { return fallback }
            return KeyChord(keyCode: UInt16(params[1]), modifierFlags: UInt64(params[2]))
        }
        func move(_ id: String, defaultKey: UInt16) -> KeyChord? {
            let fallback = KeyChord(keyCode: defaultKey, modifierFlags: defaultMoveFlags)
            return raw[id] == nil ? fallback : chord(id, default: fallback)
        }
        var desktops: [Int: KeyChord] = [:]
        for n in 1...16 {
            let fallback = n <= digitKeyCodes.count
                ? KeyChord(keyCode: digitKeyCodes[n - 1], modifierFlags: controlFlag) : nil
            if let c = chord(String(firstDesktopID + n - 1), default: fallback) { desktops[n] = c }
        }
        return SpaceHotkeys(
            moveLeft: move(moveLeftID, defaultKey: 123),
            moveRight: move(moveRightID, defaultKey: 124),
            desktops: desktops
        )
    }
}
