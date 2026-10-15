import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: AppModel
    private var hosting: NSHostingController<SpaceListView>!

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        super.init()
        // A stable autosave name lets macOS remember where the user ⌘-dragged the icon.
        statusItem.autosaveName = "MySpacesStatusItem"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "MySpaces")
            button.image?.isTemplate = true
            button.action = #selector(toggle)
            button.target = self
        }
        popover.behavior = .transient
        popover.delegate = self
        hosting = NSHostingController(
            rootView: SpaceListView(model: model, openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }, showAbout: { [weak self] in
                self?.popover.performClose(nil)
                Self.showAbout()
            }))
        // Report SwiftUI's height to the popover, so it resizes in place (anchored below the icon)
        // instead of keeping a stale size and growing upward off the screen.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            model.refresh()
            model.startPermissionPolling()
            hosting.view.layoutSubtreeIfNeeded()
            popover.contentSize = hosting.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    static func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MySpaces",
            .credits: NSAttributedString(
                string: "Name your desktops and see the names in Mission Control and when you switch.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    func popoverDidClose(_ notification: Notification) {
        model.stopPermissionPolling()
        model.editingKey = nil
        model.notice = nil
    }
}
