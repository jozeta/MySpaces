import AppKit
import MySpacesCore
import os

let log = Logger(subsystem: "com.myspaces.app", category: "app")

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rows: [SpaceRow] = []
    @Published private(set) var errorMessage: String?
    @Published var notice: String?
    @Published var editingKey: String?
    @Published private(set) var multiDisplayNote: String?
    @Published var overlayStatus: String?

    let controller: SpacesController
    private var switchInFlight = false

    init(controller: SpacesController) {
        self.controller = controller
        refresh()
    }

    func refresh() {
        controller.refresh()
        rows = controller.rows
        errorMessage = controller.lastError
        multiDisplayNote = controller.hasMultipleDisplaysWithSpaces
            ? "Only your main display is supported in this version." : nil
    }

    func rename(key: String, to name: String) {
        do {
            try controller.rename(key: key, to: name)
            rows = controller.rows
        } catch {
            log.error("rename failed: \(error.localizedDescription, privacy: .public)")
            notice = "Couldn't save the name."
        }
        editingKey = nil
    }

    func switchTo(_ row: SpaceRow) {
        // A second click before the first switch lands would plan from a stale current desktop.
        guard !switchInFlight else { return }
        guard Permissions.accessibilityGranted else {
            notice = "Allow MySpaces to switch desktops in Accessibility settings."
            Permissions.requestAccessibility()
            return
        }
        let plan = controller.switchTo(key: row.id)
        switch plan {
        case .alreadyThere:
            return
        case .unavailable:
            notice = "Turn on “Move left/right a space” or “Switch to Desktop” shortcuts to switch."
            return
        case .direct, .step:
            break
        }
        let target = row.id
        switchInFlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + plan.verificationDelay) { [weak self] in
            guard let self else { return }
            self.switchInFlight = false
            self.refresh()
            if self.rows.first(where: { $0.space.isCurrent })?.id != target {
                self.notice = "Didn't reach that desktop. Enable direct switching in Settings."
                log.notice("switch verification failed for \(target, privacy: .public)")
            }
        }
    }
}
