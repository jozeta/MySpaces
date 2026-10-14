import AppKit
import MySpacesCore

@MainActor
final class OverlayCoordinator {
    static let bandHeight: CGFloat = 300
    static let openDelay: TimeInterval = 0.4
    /// The bar animates for ~0.5 s when it expands or collapses; scan after it settles.
    static let edgeSettleDelay: TimeInterval = 0.6
    /// Periodic rescan while open, so a changed layout (Space added/removed) is caught.
    static let rescanInterval: TimeInterval = 1.5
    static let missLimit = 5

    var visionReady = false
    private(set) var consecutiveMisses = 0
    private(set) var lastScanSummary = "No scan yet"

    private let model: AppModel
    private let detector = MissionControlDetector()
    private let renderer = OverlayRenderer()
    private let gate = OverlayScanGate()
    private let recognizer = StripTextRecognizer(bandHeight: OverlayCoordinator.bandHeight)
    private var watchTimer: Timer?
    private var pointerInBar = false
    private var lastEdge = Date.distantPast
    private var lastScanStart = Date.distantPast
    private var scanInFlight = false
    private var shown: [LabelPlacement] = []

    init(model: AppModel) { self.model = model }

    func start() {
        detector.onChange = { [weak self] open in self?.missionControlChanged(open) }
        detector.start()
        DispatchQueue.global(qos: .utility).async {
            StripTextRecognizer.prewarm()
            DispatchQueue.main.async { self.visionReady = true }
        }
    }

    private func missionControlChanged(_ open: Bool) {
        if open {
            gate.open()
            pointerInBar = isPointerInBar()
            lastEdge = Date()
            scanInFlight = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay) { [weak self] in self?.scan() }
            watchTimer?.invalidate()
            watchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.watch() }
            }
        } else {
            gate.close()
            watchTimer?.invalidate()
            hide()
            model.refresh()
        }
    }

    /// Hide immediately when the bar changes shape (pointer enters/leaves it), rescan once it
    /// settles, and rescan periodically to catch layout changes.
    private func watch() {
        let inBar = isPointerInBar()
        if inBar != pointerInBar {
            pointerInBar = inBar
            lastEdge = Date()
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.edgeSettleDelay) { [weak self] in self?.scan() }
            return
        }
        let now = Date()
        if !scanInFlight, now.timeIntervalSince(lastEdge) > Self.edgeSettleDelay,
           now.timeIntervalSince(lastScanStart) > Self.rescanInterval {
            scan()
        }
    }

    private func isPointerInBar() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        return NSEvent.mouseLocation.y > screen.frame.maxY - Self.bandHeight
    }

    private func hide() {
        renderer.hideAll()
        shown = []
    }

    private func scan() {
        guard Permissions.screenRecordingGranted else {
            model.overlayStatus = "Names in Mission Control need Screen Recording."
            return
        }
        guard visionReady else {
            lastScanSummary = "Skipped: text recognition still loading"
            return
        }
        guard let ticket = gate.issueScan() else { return }
        scanInFlight = true
        lastScanStart = Date()
        let displaySpaces = model.controller.primaryDisplaySpaces
        let names = model.controller.names
        let recognizer = self.recognizer
        let band = Self.bandHeight
        let started = Date()
        Task.detached(priority: .userInitiated) {
            do {
                let (image, ppp) = try await ScreenBandCapture.capture(heightPoints: band)
                let labels = try recognizer.recognize(in: image, pointsPerPixel: ppp)
                let placements = LabelMapper.placements(labels: labels, displaySpaces: displaySpaces, names: names)
                // Vision's caption boxes are loose; size patches to the real glyphs.
                let styled = placements?.map { p -> (LabelPlacement, PatchStyle) in
                    let tight = BackgroundSampler.textBounds(for: p.rect, in: image, pointsPerPixel: ppp)
                    let placement = LabelPlacement(rect: tight, name: p.name, spaceKey: p.spaceKey, maxWidth: p.maxWidth)
                    return (placement, BackgroundSampler.style(for: tight, in: image, pointsPerPixel: ppp))
                }
                await MainActor.run {
                    self.finish(ticket, labels: labels, styled: styled, elapsed: Date().timeIntervalSince(started))
                }
            } catch {
                await MainActor.run {
                    self.scanInFlight = false
                    self.lastScanSummary = "Capture failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finish(_ ticket: ScanTicket, labels: [RecognizedLabel], styled: [(LabelPlacement, PatchStyle)]?, elapsed: TimeInterval) {
        scanInFlight = false
        switch gate.decide(ticket, placements: styled?.map(\.0)) {
        case .ignore:
            return
        case .hide:
            hide()
            consecutiveMisses += 1
            let texts = labels.map(\.text).joined(separator: ", ")
            lastScanSummary = String(format: "%.2fs · mismatch · %@", elapsed, texts)
            log.notice("caption mapping failed (\(self.consecutiveMisses)): \(texts, privacy: .public)")
            if consecutiveMisses >= Self.missLimit {
                model.overlayStatus = "Mission Control names aren't working on this macOS version."
            }
        case .show(let placements):
            consecutiveMisses = 0
            model.overlayStatus = nil
            lastScanSummary = String(format: "%.2fs · %d named", elapsed, placements.count)
            guard !Self.sameLayout(placements, shown), let styled else { return } // avoid flicker
            renderer.show(styled)
            shown = placements
        }
    }

    private static func sameLayout(_ a: [LabelPlacement], _ b: [LabelPlacement]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.name == y.name && abs(x.rect.midX - y.rect.midX) < 2 && abs(x.rect.midY - y.rect.midY) < 2
        }
    }
}
