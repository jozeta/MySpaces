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

    let controller: SpacesController

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

    /// Replaced in Task 9 with permission checks and switch verification.
    func switchTo(_ row: SpaceRow) {
        controller.switchTo(key: row.id)
    }
}
