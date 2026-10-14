import XCTest
@testable import MySpacesCore

final class HotkeysTests: XCTestCase {
    func entry(_ enabled: Bool, _ keyCode: Int, _ flags: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, keyCode, flags], "type": "standard"]]
    }

    func testDefaultsWhenDomainMissing() {
        let hk = SpaceHotkeys.parse(symbolicHotKeys: nil)
        XCTAssertEqual(hk.moveLeft, KeyChord(keyCode: 123, modifierFlags: 0x840000))
        XCTAssertEqual(hk.moveRight, KeyChord(keyCode: 124, modifierFlags: 0x840000))
        XCTAssertTrue(hk.desktops.isEmpty)
    }

    func testReadsEnabledDesktopShortcutsOnly() {
        let hk = SpaceHotkeys.parse(symbolicHotKeys: [
            "118": entry(true, 18, 262144),
            "119": entry(false, 19, 262144),
            "120": entry(true, 20, 262144),
        ])
        XCTAssertEqual(hk.desktops, [1: KeyChord(keyCode: 18, modifierFlags: 262144),
                                     3: KeyChord(keyCode: 20, modifierFlags: 262144)])
    }

    func testDisabledMoveShortcutIsNil() {
        let hk = SpaceHotkeys.parse(symbolicHotKeys: ["79": entry(false, 123, 8650752), "81": entry(true, 124, 8650752)])
        XCTAssertNil(hk.moveLeft)
        XCTAssertEqual(hk.moveRight, KeyChord(keyCode: 124, modifierFlags: 8650752))
    }

    func testEnabledWithoutParametersUsesDefaultMoveChord() {
        // macOS stores only {enabled = 1} when the default key is kept (seen on macOS 27).
        let hk = SpaceHotkeys.parse(symbolicHotKeys: ["79": ["enabled": true], "81": ["enabled": true]])
        XCTAssertEqual(hk.moveLeft, KeyChord(keyCode: 123, modifierFlags: 0x840000))
        XCTAssertEqual(hk.moveRight, KeyChord(keyCode: 124, modifierFlags: 0x840000))
    }

    func testEnabledDesktopWithoutParametersUsesControlDigit() {
        let hk = SpaceHotkeys.parse(symbolicHotKeys: [
            "118": ["enabled": true],
            "122": ["enabled": true, "value": ["parameters": [1]]],
            "127": ["enabled": true],
        ])
        XCTAssertEqual(hk.desktops[1], KeyChord(keyCode: 18, modifierFlags: 0x40000))
        XCTAssertEqual(hk.desktops[5], KeyChord(keyCode: 23, modifierFlags: 0x40000))
        XCTAssertNil(hk.desktops[10], "no default key exists for Desktop 10+")
    }
}
