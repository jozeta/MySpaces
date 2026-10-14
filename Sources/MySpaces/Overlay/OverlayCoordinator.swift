import AppKit
import MySpacesCore

@MainActor
final class OverlayCoordinator {
    static let bandHeight: CGFloat = 300
    static let openDelay: TimeInterval = 0.4
    static let missLimit = 5

    var visionReady = false
    private(set) var consecutiveMisses = 0
    private(set) var lastScanSummary = "No scan yet"

    private let model: AppModel
    private let detector = MissionControlDetector()
    private let renderer = OverlayRenderer()
    private let recognizer = StripTextRecognizer(bandHeight: OverlayCoordinator.bandHeight)
    private var session = 0
    private var pointerInBar = false
    private var hoverTimer: Timer?

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
        session += 1
        if open {
            let current = session
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay) { [weak self] in self?.scan(session: current) }
            startHoverWatch(session: current)
        } else {
            hoverTimer?.invalidate()
            renderer.hideAll()
            model.refresh()
        }
    }

    /// Rescan when the pointer enters the Spaces bar (it expands into thumbnails).
    private func startHoverWatch(session current: Int) {
        pointerInBar = false
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session == current, let screen = NSScreen.screens.first else { return }
                let inBar = NSEvent.mouseLocation.y > screen.frame.maxY - Self.bandHeight
                if inBar && !self.pointerInBar {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.scan(session: current) }
                }
                self.pointerInBar = inBar
            }
        }
    }

    private func scan(session current: Int) {
        guard session == current, detector.isOpen else { return }
        guard Permissions.screenRecordingGranted else {
            model.overlayStatus = "Names in Mission Control need Screen Recording."
            return
        }
        guard visionReady else {
            lastScanSummary = "Skipped: text recognition still loading"
            return
        }
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
                    self.finish(session: current, labels: labels, styled: styled, elapsed: Date().timeIntervalSince(started))
                }
            } catch {
                await MainActor.run { self.lastScanSummary = "Capture failed: \(error.localizedDescription)" }
            }
        }
    }

    private func finish(session current: Int, labels: [RecognizedLabel], styled: [(LabelPlacement, PatchStyle)]?, elapsed: TimeInterval) {
        guard session == current, detector.isOpen else { return } // MC closed mid-scan: discard
        let texts = labels.map(\.text).joined(separator: ", ")
        lastScanSummary = String(format: "%.2fs · %@", elapsed, texts)
        guard let styled else {
            consecutiveMisses += 1
            log.notice("caption mapping failed (\(self.consecutiveMisses)): \(texts, privacy: .public)")
            if consecutiveMisses >= Self.missLimit {
                model.overlayStatus = "Mission Control names aren't working on this macOS version."
            }
            return
        }
        consecutiveMisses = 0
        model.overlayStatus = nil
        renderer.show(styled)
    }
}
