import CoreGraphics
import Foundation
import MySpacesCore

/// Posts a shortcut as a hardware-like key event. Requires Accessibility permission.
struct KeyPoster: KeyPosting {
    /// Gap between repeated steps so Dock registers each one.
    var stepInterval: TimeInterval = 0.06

    func post(_ chord: KeyChord, times: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for i in 0..<times {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: down) else { continue }
                event.flags = CGEventFlags(rawValue: chord.modifierFlags)
                event.post(tap: .cghidEventTap)
            }
            if i < times - 1 { Thread.sleep(forTimeInterval: stepInterval) }
        }
    }
}
