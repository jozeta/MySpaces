import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openKeyboardShortcutsSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
    }

    /// Clears MySpaces' own entry for `service` ("Accessibility", "ScreenCapture"). Needed when
    /// System Settings shows MySpaces as allowed but the entry belongs to another signature
    /// (an older build with the same bundle ID), so macOS keeps refusing this one.
    static func reset(_ service: String) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        let output = Pipe()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", service, id]
        task.standardOutput = output
        task.standardError = output
        try? task.run()
        task.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        log.notice("tccutil reset \(service, privacy: .public): exit \(task.terminationStatus) \(text, privacy: .public)")
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
