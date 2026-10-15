import MySpacesCore
import SwiftUI

/// Every block shares one 14 pt leading edge: header, permission cards, row titles, footer.
private let edge: CGFloat = 14

struct SpaceListView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void
    var showAbout: () -> Void
    @AppStorage("dismissedAccessibilityHint") private var dismissedAccessibilityHint = false
    @AppStorage("dismissedScreenRecordingHint") private var dismissedScreenRecordingHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MySpaces").font(.system(size: 13, weight: .semibold))
                Text("Your desktops, organized.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, edge).padding(.top, 12).padding(.bottom, 10)

            Divider().opacity(0.5)

            permissionCards

            if let error = model.errorMessage {
                HStack {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { model.refresh() }.controlSize(.small)
                }
                .padding(.horizontal, edge).padding(.top, 8)
            }

            VStack(spacing: 1) {
                ForEach(model.rows) { row in
                    SpaceRowView(row: row, model: model)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 6)

            if let note = model.notice ?? model.overlayStatus ?? model.multiDisplayNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, edge).padding(.bottom, 8)
            }

            Divider().opacity(0.5)

            HStack(spacing: 12) {
                Button("Settings…", action: openSettings).buttonStyle(.plain).font(.system(size: 12))
                Spacer()
                Button("About", action: showAbout).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, edge).padding(.vertical, 9)
        }
        .frame(width: 300)
    }

    @ViewBuilder private var permissionCards: some View {
        let showAX = !model.accessibilityGranted && !dismissedAccessibilityHint
        let showSR = !model.screenRecordingGranted && !dismissedScreenRecordingHint
        if showAX || showSR {
            VStack(spacing: 6) {
                if showAX {
                    if model.accessibilityRequested {
                        PermissionCard(
                            symbol: "hourglass",
                            title: "Waiting for Accessibility",
                            detail: "Turn on MySpaces under Accessibility. Already on but still asked? macOS is holding an old entry for MySpaces — reset it and allow again.",
                            actionTitle: "Settings…",
                            action: Permissions.openAccessibilitySettings,
                            secondaryTitle: "Reset and ask again",
                            secondaryAction: model.resetAccessibility,
                            onDismiss: { dismissedAccessibilityHint = true })
                    } else {
                        PermissionCard(
                            symbol: "arrow.left.arrow.right",
                            title: "Switch desktops from this menu",
                            detail: "MySpaces presses your Mission Control shortcuts for you. macOS asks for Accessibility access to allow that.",
                            actionTitle: "Allow…",
                            action: model.requestAccessibility,
                            onDismiss: { dismissedAccessibilityHint = true })
                    }
                }
                if showSR {
                    if model.screenRecordingRequested {
                        PermissionCard(
                            symbol: "arrow.clockwise",
                            title: "Relaunch to finish",
                            detail: "After turning on MySpaces under Screen & System Audio Recording, relaunch so macOS applies it. Already on but still asked? Reset and allow again.",
                            actionTitle: "Relaunch",
                            action: model.relaunch,
                            secondaryTitle: "Reset and ask again",
                            secondaryAction: model.resetScreenRecording,
                            onDismiss: { dismissedScreenRecordingHint = true })
                    } else {
                        PermissionCard(
                            symbol: "rectangle.3.group",
                            title: "Show names in Mission Control",
                            detail: "MySpaces reads the desktop labels on screen to place your names. Nothing is saved or sent anywhere.",
                            actionTitle: "Allow…",
                            action: model.requestScreenRecording,
                            onDismiss: { dismissedScreenRecordingHint = true })
                    }
                }
            }
            .padding(.horizontal, edge - 10).padding(.top, 8)
        }
    }
}

private struct SpaceRowView: View {
    let row: SpaceRow
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if model.editingKey == row.id {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($focused)
                        .onSubmit { model.rename(key: row.id, to: draft) }
                        .onExitCommand { model.editingKey = nil }
                        .onAppear { draft = row.hasCustomName ? row.title : ""; focused = true }
                } else {
                    Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                Text(row.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if row.isRenamable && model.editingKey != row.id {
                Button { model.editingKey = row.id } label: {
                    Image(systemName: "pencil").font(.system(size: 11)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Rename")
            }

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(row.space.isCurrent ? 1 : 0)
                .frame(width: 14)
        }
        .padding(.horizontal, edge - 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if model.editingKey != row.id { model.switchTo(row) } }
    }
}

/// A readable two-line permission explanation with one clear action.
private struct PermissionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Not now", action: onDismiss).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction).controlSize(.small)
                }
                Button(actionTitle, action: action).controlSize(.small).buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
}
