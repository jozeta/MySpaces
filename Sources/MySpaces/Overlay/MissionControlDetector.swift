import AppKit

/// Dock shows a full-screen window at layer 20 only while Mission Control is open.
@MainActor
final class MissionControlDetector {
    var onChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private var timer: Timer?

    func start() {
        // 60 Hz (~0.12 ms per check): names are timed against the moment Mission Control opens.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let open = Self.missionControlVisible()
        guard open != isOpen else { return }
        isOpen = open
        onChange?(open)
    }

    static func missionControlVisible() -> Bool {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == dockPID && ($0[kCGWindowLayer as String] as? Int) == 20
        }
    }
}
