import AppKit
import MySpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menuBar: MenuBarController!
    private var overlay: OverlayCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = SpacesController(
            source: LiveSpacesSource(),
            store: NameStore(fileURL: NameStore.defaultURL),
            hotkeys: LiveHotkeySource(),
            keys: KeyPoster())
        model = AppModel(controller: controller)
        menuBar = MenuBarController(model: model, openSettings: {})

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        overlay = OverlayCoordinator(model: model)
        overlay.start()
    }
}
