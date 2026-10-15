import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel
    private let overlay: OverlayCoordinator
    private let previewSwitchName: () -> Void

    init(model: AppModel, overlay: OverlayCoordinator, previewSwitchName: @escaping () -> Void) {
        self.model = model
        self.overlay = overlay
        self.previewSwitchName = previewSwitchName
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, overlay: overlay, previewSwitchName: previewSwitchName)))
            w.title = "MySpaces Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
