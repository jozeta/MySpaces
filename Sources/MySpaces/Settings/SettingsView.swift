import AppKit
import MySpacesCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let overlay: OverlayCoordinator
    let previewSwitchName: () -> Void
    @AppStorage(SwitchHUD.enabledKey) private var showNameWhenSwitching = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var refreshTick = 0

    var body: some View {
        Form {
            Section("Permissions") {
                permission("Device Control", detail: "Switch desktops from the menu",
                           granted: Permissions.accessibilityGranted, open: Permissions.openAccessibilitySettings)
                permission("Screen Recording", detail: "Show your names in Mission Control",
                           granted: Permissions.screenRecordingGranted, open: Permissions.openScreenRecordingSettings)
            }
            Section("Switching") {
                Toggle(isOn: $showNameWhenSwitching) {
                    Text("Show the desktop’s name when switching")
                    Text("A large name in the middle of the screen, for about a second.")
                }
                Button("Preview", action: previewSwitchName).disabled(!showNameWhenSwitching)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Direct switching") {
                    Button("Enable in Keyboard Shortcuts…", action: Permissions.openKeyboardShortcutsSettings)
                }
                Text("Turn on “Switch to Desktop 1…” under Mission Control to jump in one step instead of sliding across desktops.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Text(report).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .id(refreshTick)
                HStack {
                    Button("Refresh") { model.refresh(); refreshTick += 1 }
                    Button("Copy report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
    }

    private var report: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let spaces = model.controller.spaces.map { s -> String in
            let kind: String
            switch s.kind {
            case .desktop: kind = "desktop"
            case .fullscreen(let app): kind = "fullscreen(\(app))"
            }
            return "  \(s.managedID) \(s.key) \(kind)\(s.isCurrent ? " current" : "")"
        }.joined(separator: "\n")
        return """
        MySpaces \(Bundle.main.shortVersion) · macOS \(os)
        Accessibility: \(Permissions.accessibilityGranted) · Screen Recording: \(Permissions.screenRecordingGranted)
        Vision ready: \(overlay.visionReady) · Misses in a row: \(overlay.consecutiveMisses)
        Last scan: \(overlay.lastScanSummary)
        Names: \(overlay.drawnSummary) · redrawn after loss: \(overlay.redraws)
        Last hide: \(overlay.lastHide)
        Running since: \(overlay.launchedAt.formatted(date: .abbreviated, time: .shortened)) · last wake: \(overlay.lastWake?.formatted(date: .abbreviated, time: .shortened) ?? "none")
        Spaces:
        \(spaces)
        """
    }

    private func permission(_ title: String, detail: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark").foregroundStyle(.secondary)
            } else {
                Button("Open Settings…", action: open)
            }
        }
    }
}
