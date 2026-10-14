import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: AppModel

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "MySpaces")
            button.image?.isTemplate = true
            button.action = #selector(toggle)
            button.target = self
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: SpaceListView(model: model, openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }))
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.editingKey = nil
        model.notice = nil
    }
}
