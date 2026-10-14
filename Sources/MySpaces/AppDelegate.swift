import AppKit
import MySpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menuBar: MenuBarController!
    private var overlay: OverlayCoordinator!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = NameStore(fileURL: NameStore.defaultURL)
        let controller = SpacesController(source: LiveSpacesSource(), store: store,
                                          hotkeys: LiveHotkeySource(), keys: KeyPoster())
        model = AppModel(controller: controller)
        if store.recoveredFromCorruption {
            model.notice = "Your saved names were unreadable and have been reset (backup kept)."
            log.error("names.json was corrupt; moved to names.json.bak")
        }
        overlay = OverlayCoordinator(model: model)
        overlay.start()
        settings = SettingsWindowController(model: model, overlay: overlay)
        menuBar = MenuBarController(model: model, openSettings: { [weak self] in self?.settings.show() })

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
    }
}
