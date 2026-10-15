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
    /// Caption fingerprint watch rate while Mission Control is open (reads the live stream's newest frame).
    static let fingerprintInterval: TimeInterval = 1.0 / 60
    static let maxReferences = 12
    /// Captions within this many points of a remembered layout's are that layout, learned again.
    static let sameLayoutTolerance: CGFloat = 8
    // Measured relative to Mission Control opening: captions start appearing ~0.19 s after the
    // Dock window appears; by ~0.23 s they are within ~5 pt of where they rest (~0.5 s). The
    // remembered opening layout appears then, at the resting place, fully opaque: its patches are
    // tall enough to cover that last slide, while a fade would let the sliding captions show through.
    // (The expanded thumbnail row slides sideways by about one slot, so it is never predicted:
    // names appear there only once it has come to rest.)
    static let anticipateOpenDelay: TimeInterval = 0.23
    /// An anticipated layout must be confirmed by an exact fingerprint match within this time.
    static let anticipationGrace: TimeInterval = 0.9
    static let missLimit = 5
    private static let rowsKey = "captionRowMidYs.v2"

    var visionReady = false
    private(set) var consecutiveMisses = 0
    private(set) var lastScanSummary = "No scan yet"

    private let model: AppModel
    private let detector = MissionControlDetector()
    private let renderer = OverlayRenderer()
    private let gate = OverlayScanGate()
    /// Three agreeing readings: slow phases of an animation can look still across two.
    private let stabilizer = LayoutStabilizer(requiredAgreeing: 3, tolerance: 2)
    /// Search range around a remembered layout: the end of Mission Control's animations drifts a
    /// few points, and the names follow.
    /// Kept small: on close the bar slides up, and names must not chase it. (The opening slide's
    /// last ~5 pt are not followed at all: names wait at the resting place for the captions.)
    static let followRange = CGSize(width: 8, height: 4)
    /// Readings (~30 Hz) at one unchanged offset before it counts as the layout's resting place.
    static let restingReadings = 6
    private var restingOffset = RestingOffset(requiredReadings: OverlayCoordinator.restingReadings)
    /// Frames (~30 Hz) a layout must stay at one spot before its names are shown.
    static let arrivalReadings = 2
    /// No new frame for this long: the screen is still, and its last frame may be read again.
    static let stillAfter: TimeInterval = 0.05
    private let bandStream = BandStream()
    private var lastFrameAt: Date?
    /// The shown layout's captions were missing from the last trusted frame.
    private var mismatchSeen = false
    /// Room above and below the caption row in the watch's strip: the follow search and a little more.
    static let stripMargin: CGFloat = 10
    private var arriving = RestingOffset(requiredReadings: OverlayCoordinator.arrivalReadings, countsZero: true)
    private var arrivingKey: String?
    /// Read by OCR but not yet seen at rest: the fingerprint watch shows it once it is still.
    private var pendingLayout: Reference?
    /// The collapsed bar reacts to the pointer a few points below its captions.
    static let barEntryMargin: CGFloat = 12
    private var shownOffset: (dx: Int, dy: Int) = (0, 0)
    private let recognizer = StripTextRecognizer(bandHeight: OverlayCoordinator.bandHeight)
    private var watchTimer: Timer?
    /// Caption rows seen before (collapsed and expanded bar), in points from the top.
    private var knownRows: [CGFloat]
    /// A layout that was drawn before: its caption snapshot, and the names to draw over it.
    private struct Reference: Codable {
        let signature: String
        let fingerprint: CaptionFingerprint
        let rects: [CGRect]
        let placements: [LabelPlacement]
        let styles: [PatchStyle]

        init(signature: String, fingerprint: CaptionFingerprint, styled: [(LabelPlacement, PatchStyle)]) {
            self.signature = signature
            self.fingerprint = fingerprint
            self.rects = styled.map(\.0.rect)
            self.placements = styled.map(\.0)
            self.styles = styled.map(\.1)
        }

        var styled: [(LabelPlacement, PatchStyle)] { Array(zip(placements, styles)) }

        /// The same layout, resting (dx, dy) points away from where it was recorded.
        func offsetBy(dx: CGFloat, dy: CGFloat) -> Reference {
            Reference(signature: signature, fingerprint: fingerprint, styled: styled.map { p, style in
                (LabelPlacement(rect: p.rect.offsetBy(dx: dx, dy: dy), name: p.name, spaceKey: p.spaceKey, maxWidth: p.maxWidth),
                 style.offsetBy(dx: dx, dy: dy))
            })
        }
        var bandHeight: CGFloat { (rects.map(\.maxY).max() ?? 0) + 4 }
        var key: String { "\(signature)@\(Int(rects.first?.midX ?? 0)),\(Int(rects.first?.midY ?? 0))" }
        /// Captions in the top strip (collapsed bar, ~59 pt) rather than under thumbnails (~179 pt).
        var isCollapsedBar: Bool { (rects.map(\.minY).max() ?? 0) < 120 }
    }

    /// Saved between launches so the first open after launch is as fast as the rest.
    private struct Layouts: Codable {
        var references: [Reference] = []
        /// Signature → the layout first shown when Mission Control opens.
        var opening: [String: Reference] = [:]
    }
    /// v4: earlier files could hold layouts recorded before the bar finished sliding, flat patches, and
    /// patches cut short by a too-tight caption box.
    private static var layoutsURL: URL {
        NameStore.defaultURL.deletingLastPathComponent().appendingPathComponent("layouts-v4.json")
    }
    private var layouts = Layouts()
    private var references: [Reference] {
        get { layouts.references }
        set { layouts.references = newValue }
    }
    private var openedAt = Date.distantPast
    private var firstShowInSession = true
    /// Shown ahead of the captions; not yet confirmed by an exact fingerprint match.
    private var anticipatedUntil: Date?
    private var shownConfirmed = false
    private var shownReference: Reference?
    private var shownAt = Date.distantPast
    private var fingerprintTimer: Timer?
    private var pointerTimer: Timer?
    private var fingerprintInFlight = false
    /// Bumped on every hide, so a fingerprint capture taken before it cannot show names again.
    private var hideCount = 0
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
    /// Where the shown names are now: as drawn, moved by however far they followed their captions.
    private var shownNow: [LabelPlacement] {
        shown.map { p in
            LabelPlacement(rect: p.rect.offsetBy(dx: CGFloat(shownOffset.dx), dy: CGFloat(shownOffset.dy)),
                           name: p.name, spaceKey: p.spaceKey, maxWidth: p.maxWidth)
        }
    }

    init(model: AppModel) {
        self.model = model
        knownRows = (UserDefaults.standard.array(forKey: Self.rowsKey) as? [Double])?.map { CGFloat($0) } ?? []
        if let data = try? Data(contentsOf: Self.layoutsURL),
           let saved = try? JSONDecoder().decode(Layouts.self, from: data) {
            layouts = saved
        }
    }

    private func saveLayouts() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        try? data.write(to: Self.layoutsURL, options: .atomic)
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
        pendingLayout = nil
        if open {
            bandStream.start()
            gate.open()
            openedAt = Date()
            firstShowInSession = true
            anticipatedUntil = nil
            if let opening = layouts.opening[signature()] {
                anticipate(opening, after: Self.anticipateOpenDelay)
            }
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
            pointerTimer?.invalidate()
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerTick() }
            }
        } else {
            gate.close()
            bandStream.stop()
            watchTimer?.invalidate()
            fingerprintTimer?.invalidate()
            pointerTimer?.invalidate()
            settlingSince = nil
            anticipatedUntil = nil
            hide()
            saveLayouts()
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
    /// shows its wallpaper), the order of all Spaces, and the names.
    private func signature() -> String {
        let spaces = model.controller.primaryDisplaySpaces
        let names = model.controller.names
        let current = spaces.first(where: \.isCurrent)?.key ?? "-"
        // Every Space in order, full-screen ones included: each one shifts the thumbnails.
        return current + "|" + spaces.map { space in
            switch space.kind {
            case .desktop: return "\(space.key)=\(names[space.key] ?? "")"
            case .fullscreen(let app): return "fs:\(app)"
            }
        }.joined(separator: ",")
    }

    /// ~30 Hz while Mission Control is open: compare the pixels under remembered captions.
    /// Shows names the moment a remembered layout appears and hides them the moment it changes
    /// (closing, sliding, expanding) — no OCR, so within a frame or two.
    private func fingerprintTick() {
        guard !fingerprintInFlight, detector.isOpen, Permissions.screenRecordingGranted else { return }
        let sig = signature()
        // While the pointer is in the collapsed bar it is expanding: its captions are still in
        // place for a frame or two, but showing their names again would flicker over the expansion.
        let candidates = shownReference.map { [$0] }
            ?? (references + (pendingLayout.map { [$0] } ?? []))
                .filter { $0.signature == sig && !($0.isCollapsedBar && pointerInBar($0)) }
        guard let stripBottom = candidates.map(\.bandHeight).max(),
              let stripTop = candidates.flatMap(\.rects).map(\.minY).min().map({ max(0, ($0 - Self.stripMargin).rounded(.down)) }) else { return }
        let stripHeight = stripBottom + Self.stripMargin - stripTop
        // The live stream's newest frame. A frame already read is read again only once the screen
        // has been still for a moment: mid-animation, two reads of one frame would look like rest.
        let streamed = bandStream.isRunning ? bandStream.frame(top: stripTop, height: stripHeight) : nil
        if let streamed, streamed.at == lastFrameAt, Date().timeIntervalSince(streamed.at) < Self.stillAfter { return }
        lastFrameAt = streamed?.at
        fingerprintInFlight = true
        let session = gateSession
        let hides = hideCount
        let followRange = Self.followRange
        Task.detached(priority: .userInitiated) {
            let watched = if let streamed {
                (streamed.image, pointsPerPixel: streamed.pointsPerPixel, trusted: streamed.trusted)
            } else {
                try? await ScreenBandCapture.captureWatched(top: stripTop, heightPoints: stripHeight)
            }
            // Caption rects are in screen points; the strip image starts at `stripTop`.
            let inStrip = { (rects: [CGRect]) in rects.map { $0.offsetBy(dx: 0, dy: -stripTop) } }
            let capture = watched.map { ($0.0, $0.pointsPerPixel) }
            let trusted = watched?.trusted ?? false
            let current = await MainActor.run { self.shownOffset }
            // Exact check at the current offset first (cheap); search nearby only if it fails.
            let found = candidates.map { ref -> (dx: Int, dy: Int)? in
                guard let (image, ppp) = capture else { return nil }
                let here = inStrip(ref.rects).map { $0.offsetBy(dx: CGFloat(current.dx), dy: CGFloat(current.dy)) }
                if let now = CaptionFingerprint(image: image, rects: here, pointsPerPixel: ppp), ref.fingerprint.matches(now) {
                    return current
                }
                return CaptionFingerprint.locate(ref.fingerprint, expectedAt: inStrip(ref.rects), in: image,
                                                 pointsPerPixel: ppp, maxShift: followRange)
            }
            await MainActor.run {
                self.fingerprintInFlight = false
                guard capture != nil, session == self.gateSession, self.detector.isOpen else { return }
                // Names were hidden while this capture ran (the pointer entered the bar): it shows
                // the layout from before, so it must not bring those names back.
                guard hides == self.hideCount else { return }
                if let shownRef = self.shownReference {
                    let anticipating = self.anticipatedUntil.map { Date() < $0 } ?? false
                    if let offset = found.first ?? nil, !(anticipating && offset != (0, 0)) {
                        self.mismatchSeen = false
                        self.follow(offset)
                        self.confirm(shownRef)
                        if self.restingOffset.observe(dx: offset.dx, dy: offset.dy) { self.rebase(shownRef, at: offset) }
                    } else if anticipating {
                        // Shown where the captions come to rest; they are still sliding into place.
                        // Holding still here is what keeps the names from creeping along with them.
                    } else if !trusted {
                        // The capture filter may predate our newest windows (the window server lists
                        // new windows a little late) and so see our own names: not a reason to hide.
                    } else if !self.mismatchSeen {
                        // One odd frame is not enough to hide (a filter change landing mid-frame);
                        // the next frame, ~17 ms later, decides.
                        self.mismatchSeen = true
                    } else {
                        self.layoutChanged(from: shownRef)
                    }
                } else if let i = found.firstIndex(where: { $0.map { $0 == (0, 0) } ?? false }) ?? found.firstIndex(where: { $0 != nil }),
                          let offset = found[i] {
                    // Shown once it is still: found at one spot for a few frames in a row. Mid-slide
                    // the spot changes every frame. Where it rests may be a few points from where it
                    // was learned (the thumbnail row creeps for a second): it is moved there.
                    let ref = candidates[i]
                    if self.arrivingKey != ref.key {
                        self.arrivingKey = ref.key
                        self.arriving.reset()
                    }
                    guard self.arriving.observe(dx: offset.dx, dy: offset.dy) else { return }
                    let resting = offset == (0, 0) ? ref : ref.offsetBy(dx: CGFloat(offset.dx), dy: CGFloat(offset.dy))
                    self.settlingSince = nil
                    self.pendingLayout = nil
                    self.remember(resting)
                    self.render(resting)
                    self.confirm(resting)
                } else {
                    self.arrivingKey = nil
                }
            }
        }
    }

    /// Show a remembered layout ahead of its captions, timed to their animation.
    private func anticipate(_ ref: Reference, after delay: TimeInterval) {
        let session = gateSession
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, session == self.gateSession, self.detector.isOpen, self.shownReference == nil else { return }
            self.render(ref)
            self.shownConfirmed = false
            self.anticipatedUntil = Date().addingTimeInterval(Self.anticipationGrace)
        }
    }

    /// The shown captions changed (Mission Control closing, or the bar expanding/collapsing):
    /// hide at once and show again only when the new layout is at rest.
    private func layoutChanged(from old: Reference) {
        anticipatedUntil = nil
        hide()
        beginSettling()
    }

    /// An exact fingerprint match: the layout is really there. Learn when it shows up.
    private func confirm(_ ref: Reference) {
        anticipatedUntil = nil
        guard !shownConfirmed else { return }
        shownConfirmed = true
        if firstShowInSession, Date().timeIntervalSince(openedAt) < 1.5 {
            layouts.opening[ref.signature] = ref
        }
        firstShowInSession = false
    }

    /// The collapsed bar expands as soon as the pointer enters it. Hide the collapsed names at
    /// that moment instead of a frame or two later, when the captions have started to move.
    /// (If it does not expand after all, the fingerprint watch shows them again once the pointer leaves.)
    private func pointerTick() {
        guard let shownRef = shownReference, shownRef.isCollapsedBar, pointerInBar(shownRef) else { return }
        layoutChanged(from: shownRef)
    }

    private func pointerInBar(_ ref: Reference) -> Bool {
        pointerY() < ref.bandHeight + Self.barEntryMargin
    }

    /// Pointer distance from the top of the main screen, in points.
    private func pointerY() -> CGFloat {
        guard let screen = NSScreen.screens.first else { return .greatestFiniteMagnitude }
        return screen.frame.maxY - NSEvent.mouseLocation.y
    }

    /// The names followed their captions to a steady offset: the layout was recorded before the
    /// bar finished sliding. Move it to where it rests, so next time the names appear right there.
    private func rebase(_ ref: Reference, at offset: (dx: Int, dy: Int)) {
        let moved = ref.offsetBy(dx: CGFloat(offset.dx), dy: CGFloat(offset.dy))
        references.removeAll { $0.key == ref.key }
        remember(moved)
        for (sig, opening) in layouts.opening where opening.key == ref.key { layouts.opening[sig] = moved }
        renderer.rebase()
        shownOffset = (0, 0)
        shownReference = moved
        shown = moved.styled.map(\.0)
        log.notice("layout rebased by (\(offset.dx), \(offset.dy))")
    }

    private func follow(_ offset: (dx: Int, dy: Int)) {
        shownOffset = offset
        renderer.move(dx: offset.dx, dy: offset.dy)
    }

    private func render(_ ref: Reference) {
        if !LayoutStabilizer.same(ref.styled.map(\.0), shown) {
            renderer.show(ref.styled)
            shownOffset = (0, 0)
            overlaysChanged()
            shown = ref.styled.map(\.0)
        }
        shownReference = ref
        shownAt = Date()
    }

    private func remember(_ ref: Reference) {
        // Only the same layout learned again replaces one: the thumbnail row rests in two places at
        // one height (off-centre after the pointer enters, centred after it leaves), keep both.
        references.removeAll {
            $0.signature == ref.signature && LayoutStabilizer.same($0.placements, ref.placements, tolerance: Self.sameLayoutTolerance)
        }
        references.insert(ref, at: 0)
        references = Array(references.prefix(Self.maxReferences))
    }

    private func overlaysChanged() {
        ScreenBandCapture.invalidateFilter()
        bandStream.overlaysChanged()
    }

    private func hide() {
        hideCount += 1
        mismatchSeen = false
        arrivingKey = nil
        shownConfirmed = false
        restingOffset.reset()
        renderer.hideAll()
        overlaysChanged()
        shown = []
        shownReference = nil
        shownOffset = (0, 0)
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
        // A remembered layout is fading in ahead of its captions; the fingerprint confirms it.
        if anticipatedUntil != nil { return }
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
                    if let fingerprint { pendingLayout = Reference(signature: sig, fingerprint: fingerprint, styled: styled ?? []) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeInterval) { [weak self] in self?.scan() }
                    return
                }
                settlingSince = nil
            } else if !LayoutStabilizer.same(placements, shownNow) {
                // Layout changed since it was drawn: hide and wait for it to settle.
                hide()
                beginSettling()
                return
            }
            lastScanSummary = String(format: "%.2fs · %d named%@", elapsed, placements.count, fullScan ? " · full scan" : "")
            if let row { remember(row: row.midY) }
            guard let styled else { return }
            if let fingerprint {
                let ref = Reference(signature: sig, fingerprint: fingerprint, styled: styled)
                remember(ref)
                render(ref)
                confirm(ref)
            } else if !LayoutStabilizer.same(placements, shown) { // avoid flicker
                renderer.show(styled)
                overlaysChanged()
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
