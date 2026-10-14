import MySpacesCore
import SwiftUI

struct SpaceListView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void
    @AppStorage("dismissedScreenRecordingHint") private var dismissedScreenRecordingHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MySpaces").font(.system(size: 13, weight: .semibold))
                Text("Your desktops, organized.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider().opacity(0.5)

            if let error = model.errorMessage {
                HStack {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { model.refresh() }.controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }

            if !Permissions.accessibilityGranted {
                PermissionRow(text: "Switching desktops needs Accessibility access.",
                              action: Permissions.openAccessibilitySettings)
            }
            if !Permissions.screenRecordingGranted && !dismissedScreenRecordingHint {
                PermissionRow(text: "Names in Mission Control need Screen Recording.",
                              action: {
                                  Permissions.requestScreenRecording()
                                  Permissions.openScreenRecordingSettings()
                              },
                              onDismiss: { dismissedScreenRecordingHint = true })
            } else if let status = model.overlayStatus {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }

            VStack(spacing: 2) {
                ForEach(model.rows) { row in
                    SpaceRowView(row: row, model: model)
                }
            }
            .padding(6)

            if let note = model.notice ?? model.multiDisplayNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }

            Divider().opacity(0.5)

            HStack {
                Button("Manage Spaces…", action: openSettings).buttonStyle(.plain).font(.system(size: 12))
                Spacer()
                Text("MySpaces \(Bundle.main.shortVersion)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .frame(width: 280)
    }
}

private struct SpaceRowView: View {
    let row: SpaceRow
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.space.isCurrent ? "checkmark" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.space.isCurrent ? Color.accentColor : .clear)
                .frame(width: 12)

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
                    Image(systemName: "pencil").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0.35)
                .help("Rename")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if model.editingKey != row.id { model.switchTo(row) } }
    }
}

struct PermissionRow: View {
    let text: String
    let action: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Allow…", action: action).controlSize(.small)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("Not now")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
}
