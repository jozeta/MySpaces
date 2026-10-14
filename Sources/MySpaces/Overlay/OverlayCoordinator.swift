import AppKit
import MySpacesCore

@MainActor
final class OverlayCoordinator {
    static let bandHeight: CGFloat = 300
    /// Captions finish drawing ~0.3 s after Mission Control opens (measured); probe until then.
    static let probeInterval: TimeInterval = 0.05
    /// If the known rows still show no captions after this long, the bar changed shape: run one
    /// full-band scan (captions draw in ~0.31 s after Mission Control opens).
    static let settleTimeout: TimeInterval = 0.6
    /// Captions still moving after this long (slow animation): show what is there anyway.
    static let settleCap: TimeInterval = 2.0
    /// Measured: the Spaces bar finishes sliding in ~0.31 s after Mission Control opens.
    static let slideInDuration: TimeInterval = 0.35
    /// Periodic OCR re-check while open, so a changed layout (Space added/removed) is caught.
    static let rescanInterval: TimeInterval = 1.5
    /// Caption fingerprint watch rate while Mission Control is open (~25 ms per capture).
    static let fingerprintInterval: TimeInterval = 1.0 / 30
    static let maxReferences = 12
    static let missLimit = 5
    private static let rowsKey = "captionRowMidYs.v2"

    var visionReady = false
    private(set) var consecutiveMisses = 0
    private(set) var lastScanSummary = "No scan yet"

    private let model: AppModel
    private let detector = MissionControlDetector()
    private let renderer = OverlayRenderer()
    private let gate = OverlayScanGate()
    private let stabilizer = LayoutStabilizer()
    private let recognizer = StripTextRecognizer(bandHeight: OverlayCoordinator.bandHeight)
    private var watchTimer: Timer?
    /// Caption rows seen before (collapsed and expanded bar), in points from the top.
    private var knownRows: [CGFloat]
    /// A layout that was drawn before: its caption snapshot, and the names to draw over it.
    private struct Reference {
        let signature: String
        let fingerprint: CaptionFingerprint
        let rects: [CGRect]
        let styled: [(LabelPlacement, PatchStyle)]
        var bandHeight: CGFloat { (rects.map(\.maxY).max() ?? 0) + 4 }
    }
    private var references: [Reference] = []
    private var shownReference: Reference?
    private var shownAt = Date.distantPast
    private var fingerprintTimer: Timer?
    private var fingerprintInFlight = false
    /// Bumped on every open/close, so results from a previous session are dropped.
    private var gateSession = 0
    private var settlingSince: Date?
    private var lastScanStart = Date.distantPast
    private var scanInFlight = false
    /// Next scan reads the whole band (a known row turned up empty).
    private var forceFullScan = false
    /// Row found by a full scan, probed next to confirm it is settled.
    private var candidateRow: CGFloat?
    /// Whether any probe since settling began found captions on a known row.
    private var captionsSeenWhileSettling = false
    private var shown: [LabelPlacement] = []

    init(model: AppModel) {
        self.model = model
        knownRows = (UserDefaults.standard.array(forKey: Self.rowsKey) as? [Double])?.map { CGFloat($0) } ?? []
    }

    func start() {
        detector.onChange = { [weak self] open in self?.missionControlChanged(open) }
        detector.start()
        DispatchQueue.global(qos: .utility).async {
            StripTextRecognizer.prewarm()
            DispatchQueue.main.async { self.visionReady = true }
        }
    }

    private func missionControlChanged(_ open: Bool) {
        gateSession += 1
        if open {
            gate.open()
            forceFullScan = false
            candidateRow = nil
            if knownRows.isEmpty {
                // No known row yet: a full scan is slow, so start it once the bar has slid in.
                settlingSince = Date()
                captionsSeenWhileSettling = false
                stabilizer.reset()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideInDuration) { [weak self] in self?.scan() }
            } else {
                beginSettling()
            }
            watchTimer?.invalidate()
            watchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.watch() }
            }
            fingerprintTimer?.invalidate()
            fingerprintTimer = Timer.scheduledTimer(withTimeInterval: Self.fingerprintInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fingerprintTick() }
            }
        } else {
            gate.close()
            watchTimer?.invalidate()
            fingerprintTimer?.invalidate()
            settlingSince = nil
            hide()
            model.refresh()
        }
    }

    /// The bar is appearing or changing shape: probe quickly until captions are readable.
    private func beginSettling() {
        settlingSince = Date()
        captionsSeenWhileSettling = false
        stabilizer.reset()
        scan()
    }

    private func watch() {
        if settlingSince == nil, !scanInFlight, Date().timeIntervalSince(lastScanStart) > Self.rescanInterval {
            scan()
        }
    }

    /// Identifies a layout: which desktop is current (its caption sits on a highlight and the bar
    /// shows its wallpaper) and which named desktops there are.
    private func signature() -> String {
        let spaces = model.controller.primaryDisplaySpaces
        let names = model.controller.names
        let current = spaces.first(where: \.isCurrent)?.key ?? "-"
        return current + "|" + spaces.filter(\.isDesktop).map { "\($0.key)=\(names[$0.key] ?? "")" }.joined(separator: ",")
    }

    /// ~30 Hz while Mission Control is open: compare the pixels under remembered captions.
    /// Shows names the moment a remembered layout appears and hides them the moment it changes
    /// (closing, sliding, expanding) — no OCR, so within a frame or two.
    private func fingerprintTick() {
        guard !fingerprintInFlight, detector.isOpen, Permissions.screenRecordingGranted else { return }
        let sig = signature()
        let candidates = shownReference.map { [$0] } ?? references.filter { $0.signature == sig }
        guard let height = candidates.map(\.bandHeight).max() else { return }
        fingerprintInFlight = true
        let session = gateSession
        Task.detached(priority: .userInitiated) {
            let capture = try? await ScreenBandCapture.capture(heightPoints: height, filter: true)
            let matches = candidates.map { ref -> Bool in
                guard let (image, ppp) = capture,
                      let now = CaptionFingerprint(image: image, rects: ref.rects, pointsPerPixel: ppp) else { return false }
                return ref.fingerprint.matches(now)
            }
            await MainActor.run {
                self.fingerprintInFlight = false
                guard capture != nil, session == self.gateSession, self.detector.isOpen else { return }
                if self.shownReference != nil {
                    if matches.first != true {
                        self.hide()
                        self.beginSettling()
                    }
                } else if let i = matches.firstIndex(of: true) {
                    let ref = candidates[i]
                    self.settlingSince = nil
                    self.render(ref)
                }
            }
        }
    }

    private func render(_ ref: Reference) {
        if !LayoutStabilizer.same(ref.styled.map(\.0), shown) {
            renderer.show(ref.styled)
            ScreenBandCapture.invalidateFilter()
            shown = ref.styled.map(\.0)
        }
        shownReference = ref
        shownAt = Date()
    }

    private func remember(_ ref: Reference) {
        references.removeAll { $0.signature == ref.signature && abs(($0.rects.first?.midY ?? 0) - (ref.rects.first?.midY ?? 0)) < 8 }
        references.insert(ref, at: 0)
        references = Array(references.prefix(Self.maxReferences))
    }

    private func hide() {
        renderer.hideAll()
        ScreenBandCapture.invalidateFilter()
        shown = []
        shownReference = nil
    }

    private func scan() {
        guard !scanInFlight else { return }
        guard Permissions.screenRecordingGranted else {
            model.overlayStatus = "Names in Mission Control need Screen Recording."
            return
        }
        guard visionReady else {
            lastScanSummary = "Skipped: text recognition still loading"
            return
        }
        guard let ticket = gate.issueScan() else { return }
        let settling = settlingSince != nil
        // Fast path reads only known caption rows; the full band is the fallback.
        let settleElapsed = settlingSince.map { Date().timeIntervalSince($0) } ?? 0
        let timedOut = settleElapsed > Self.settleTimeout && !captionsSeenWhileSettling
        let capped = settleElapsed > Self.settleCap
        let rows: [CGFloat]?
        if let candidateRow, !timedOut {
            rows = [candidateRow]
        } else if knownRows.isEmpty || timedOut || forceFullScan {
            rows = nil
        } else {
            rows = knownRows
        }
        candidateRow = nil
        forceFullScan = false
        scanInFlight = true
        lastScanStart = Date()
        let displaySpaces = model.controller.primaryDisplaySpaces
        let names = model.controller.names
        let recognizer = self.recognizer
        let band = Self.bandHeight
        let sig = signature()
        let started = Date()
        Task.detached(priority: .userInitiated) {
            do {
                let (image, ppp) = try await ScreenBandCapture.capture(heightPoints: band)
                let labels = try rows.map { try recognizer.recognize(in: image, pointsPerPixel: ppp, rowMidYs: $0) }
                    ?? recognizer.recognize(in: image, pointsPerPixel: ppp)
                let placements = LabelMapper.placements(labels: labels, displaySpaces: displaySpaces, names: names)
                // Vision's caption boxes are loose; size patches to the real glyphs.
                let styled = placements?.map { p -> (LabelPlacement, PatchStyle) in
                    let tight = BackgroundSampler.textBounds(for: p.rect, in: image, pointsPerPixel: ppp)
                    let placement = LabelPlacement(rect: tight, name: p.name, spaceKey: p.spaceKey, maxWidth: p.maxWidth)
                    return (placement, BackgroundSampler.style(for: tight, in: image, pointsPerPixel: ppp))
                }
                // Snapshot of the original captions (our windows are excluded from the capture).
                let fingerprint = styled.flatMap { s in
                    s.isEmpty ? nil : CaptionFingerprint(image: image, rects: s.map(\.0.rect), pointsPerPixel: ppp)
                }
                await MainActor.run {
                    self.finish(ticket, labels: labels, styled: styled, settling: settling && !timedOut && !capped,
                                 fullScan: rows == nil, elapsed: Date().timeIntervalSince(started),
                                 fingerprint: fingerprint, signature: sig, started: started)
                }
            } catch {
                await MainActor.run {
                    self.scanInFlight = false
                    self.settlingSince = nil
                    self.lastScanSummary = "Capture failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finish(_ ticket: ScanTicket, labels: [RecognizedLabel], styled: [(LabelPlacement, PatchStyle)]?,
                        settling: Bool, fullScan: Bool, elapsed: TimeInterval,
                        fingerprint: CaptionFingerprint?, signature sig: String, started: Date) {
        scanInFlight = false
        // The fingerprint watch drew a newer layout while this scan was running: it is stale.
        if shownReference != nil, started < shownAt { return }
        let row = LabelMapper.captionRow(in: labels)
        // A known row with no captions means the bar moved or changed shape, not a mismatch.
        // While settling the captions may simply not be drawn yet, so keep probing the fast path.
        let missedRow = !fullScan && row == nil
        if settling && row != nil { captionsSeenWhileSettling = true }
        if missedRow && !settling { forceFullScan = true }
        let decision = gate.decide(ticket, placements: styled?.map(\.0), settling: settling || missedRow)
        switch decision {
        case .ignore:
            return
        case .retry:
            if settlingSince == nil { settlingSince = Date(); stabilizer.reset() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeInterval) { [weak self] in self?.scan() }
        case .hide:
            settlingSince = nil
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
            if settlingSince != nil {
                // Bar may still be sliding in or resizing: wait until two probes agree.
                let settled = stabilizer.observe(placements)
                let overdue = settlingSince.map { Date().timeIntervalSince($0) > Self.settleCap } ?? false
                guard settled || overdue else {
                    if fullScan, let row { candidateRow = row.midY }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeInterval) { [weak self] in self?.scan() }
                    return
                }
                settlingSince = nil
            } else if !LayoutStabilizer.same(placements, shown) {
                // Layout changed since it was drawn: hide and wait for it to settle.
                hide()
                beginSettling()
                return
            }
            lastScanSummary = String(format: "%.2fs · %d named%@", elapsed, placements.count, fullScan ? " · full scan" : "")
            if let row { remember(row: row.midY) }
            guard let styled else { return }
            if let fingerprint {
                let ref = Reference(signature: sig, fingerprint: fingerprint, rects: styled.map(\.0.rect), styled: styled)
                remember(ref)
                render(ref)
            } else if !LayoutStabilizer.same(placements, shown) { // avoid flicker
                renderer.show(styled)
                ScreenBandCapture.invalidateFilter()
                shown = placements
            }
        }
    }

    /// Keeps up to two caption rows (collapsed and expanded bar) for the fast path.
    private func remember(row midY: CGFloat) {
        guard !knownRows.contains(where: { abs($0 - midY) < 8 }) else { return }
        knownRows = Array((knownRows + [midY]).suffix(2))
        UserDefaults.standard.set(knownRows.map(Double.init), forKey: Self.rowsKey)
    }
}
