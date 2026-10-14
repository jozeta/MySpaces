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
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var screenRecordingGranted = Permissions.screenRecordingGranted
    @Published private(set) var screenRecordingRequested = false
    @Published private(set) var accessibilityRequested = false

    let controller: SpacesController
    private var switchInFlight = false

    init(controller: SpacesController) {
        self.controller = controller
        refresh()
    }

    private var permissionTimer: Timer?

    /// While the popover is open, keep the permission cards in sync with System Settings.
    func startPermissionPolling() {
        refreshPermissions()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func refreshPermissions() {
        let ax = Permissions.accessibilityGranted
        let sr = Permissions.screenRecordingGranted
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if sr != screenRecordingGranted { screenRecordingGranted = sr }
    }

    /// Shows the macOS prompt, which also adds MySpaces to the Accessibility list.
    func requestAccessibility() {
        Permissions.requestAccessibility()
        accessibilityRequested = true
    }

    func resetAccessibility() {
        Permissions.reset("Accessibility")
        Permissions.requestAccessibility()
        accessibilityRequested = true
    }

    func resetScreenRecording() {
        Permissions.reset("ScreenCapture")
        _ = Permissions.requestScreenRecording()
        screenRecordingRequested = true
    }

    /// The first request shows the macOS prompt and registers MySpaces; later requests can't
    /// prompt again, so open the settings pane as well. macOS applies the grant on relaunch.
    func requestScreenRecording() {
        if !Permissions.requestScreenRecording() { Permissions.openScreenRecordingSettings() }
        screenRecordingRequested = true
    }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
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
            notice = "Allow Accessibility access to switch desktops."
            requestAccessibility()
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
