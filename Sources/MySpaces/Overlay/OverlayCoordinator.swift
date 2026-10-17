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
    /// Settling with no scan started for this long: the chain of probes broke off, start another.
    static let settleStall: TimeInterval = 0.5
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
    /// For the diagnostics report: names were once found lost after the app had run for days.
    private(set) var lastHide = "none"
    private(set) var lastWake: Date?
    let launchedAt = Date()
    private(set) var redraws = 0
    var drawnSummary: String {
        "\(shown.count) shown, \(hiddenCaptions.count) hidden, \(renderer.windowCount) windows (\(renderer.visibleCount) on screen)"
    }

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
    /// Indexes of shown names hidden because their captions moved (a desktop added or removed).
    private var hiddenCaptions: Set<Int> = []
    /// Template captions as read in the previous frame, by template key.
    private var lastTemplateReadings: [String: CaptionFingerprint] = [:]
    private var desktopsChangedAt = Date.distantPast
    /// After desktops change, caption mismatches are retried this long instead of switching names off.
    static let rearrangeGrace: TimeInterval = 3
    /// Room above and below the caption row in the watch's strip: the follow search and a little more.
    static let stripMargin: CGFloat = 10
    private var arriving = RestingOffset(requiredReadings: OverlayCoordinator.arrivalReadings, countsZero: true)
    private var arrivingKey: String?
    /// Read by OCR but not yet seen at rest: the fingerprint watch shows it once it is still.
    private var pendingLayout: Reference?
    /// The collapsed bar reacts to the pointer a few points below its captions.
    static let barEntryMargin: CGFloat = 12
    /// Mission Control starts expanding the bar within this long of the pointer entering it.
    static let expansionStartsWithin: TimeInterval = 0.15
    /// Pointer hid the collapsed names at this time and height (points from the top).
    private var hoverHide: (at: Date, y: CGFloat)?
    /// The bar did not expand with the pointer at this height: only higher up hides the names again.
    private var noExpansionBelowY: CGFloat?
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
            // Saved before scans snapped stretched caption boxes onto their row: relearned instead.
            layouts.references.removeAll { !LayoutStabilizer.isOneRow($0.placements) }
            layouts.opening = layouts.opening.filter { LayoutStabilizer.isOneRow($0.value.placements) }
        }
    }

    private func saveLayouts() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        try? data.write(to: Self.layoutsURL, options: .atomic)
    }

    func start() {
        detector.onChange = { [weak self] open in self?.missionControlChanged(open) }
        detector.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lastWake = Date() }
            log.notice("woke from sleep")
        }
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
            hide("Mission Control closed")
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
        // Desktops can be added or removed in Mission Control itself. Captions read against the old
        // list of desktops cannot be matched, so re-read it (cheap) and relearn when it changes.
        let before = signature()
        let beforeOrder = model.controller.primaryDisplaySpaces.map(\.key)
        model.controller.refresh()
        if signature() != before { spacesChanged(previousOrder: beforeOrder) }
        if settlingSince == nil, !scanInFlight, Date().timeIntervalSince(lastScanStart) > Self.rescanInterval {
            scan()
        }
        restoreLostNames()
        // While settling, each scan schedules the next. One that ends early (read against an older
        // list of desktops, or names already shown another way) leaves none coming: start one.
        if let since = settlingSince, !scanInFlight, Date().timeIntervalSince(max(since, lastScanStart)) > Self.settleStall {
            scan()
        }
    }

    /// Names this coordinator counts as shown whose windows are no longer on screen: drawn again.
    /// (Seen once after the app had run for days: scans kept matching, nothing was drawn.)
    private func restoreLostNames() {
        guard let ref = shownReference, anticipatedUntil == nil,
              renderer.visibleCount < shown.count - hiddenCaptions.count else { return }
        log.notice("names lost: \(self.drawnSummary, privacy: .public); drawing them again")
        redraws += 1
        renderer.show(ref.styled)
        renderer.move(dx: shownOffset.dx, dy: shownOffset.dy)
        if !hiddenCaptions.isEmpty { renderer.hide(hiddenCaptions) }
        overlaysChanged()
    }

    private func spacesChanged(previousOrder: [String]) {
        model.refresh()
        gate.desktopsChanged()
        desktopsChangedAt = Date()
        consecutiveMisses = 0
        pendingLayout = nil
        arrivingKey = nil
        candidateRow = nil
        // A scan in flight read its captions against the old list: let it finish unheard.
        scanInFlight = false
        stabilizer.reset()
        // A name stays only while its desktop is still at the same place in the row: after a
        // desktop is moved, a caption can look exactly as before ("Desktop 5" is still "Desktop 5")
        // while another desktop sits behind it. The new layout is learned either way.
        if let shownRef = shownReference {
            let order = model.controller.primaryDisplaySpaces.map(\.key)
            let moved = Set(shownRef.placements.indices.filter { i in
                let key = shownRef.placements[i].spaceKey
                return previousOrder.firstIndex(of: key) != order.firstIndex(of: key)
            })
            if moved.count == shownRef.placements.count {
                layoutChanged(from: shownRef)
                return
            }
            if !moved.isEmpty { hideCaptions(moved, of: shownRef) }
        }
        // Even if already settling: the scan in flight was read against the old list and ends unheard.
        beginSettling()
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
        // Shown names are checked against their own layout. With none shown, or only some (the
        // rest hid when a desktop was added or removed), new layouts are looked for as well.
        let shownList = shownReference.map { [$0] } ?? []
        let lookForNew = shownReference == nil || !hiddenCaptions.isEmpty
        let newcomers = !lookForNew ? [] : (references + (pendingLayout.map { [$0] } ?? []))
            .filter { $0.signature == sig && $0.key != shownReference?.key && !hiddenForPointer($0) }
        let candidates = shownList + newcomers
        // No layout learned yet with this desktop current (just switched): one learned with another
        // desktop current has its captions in the same places; only the highlight moved.
        let templates = !lookForNew || newcomers.contains(where: { $0.signature == sig }) ? [] :
            references.filter { Self.order(of: $0.signature) == Self.order(of: sig) && !hiddenForPointer($0) }
        let watched = candidates + templates
        guard let stripBottom = watched.map(\.bandHeight).max(),
              let stripTop = watched.flatMap(\.rects).map(\.minY).min().map({ max(0, ($0 - Self.stripMargin).rounded(.down)) }) else { return }
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
            var shownDifferences: [Double]?
            let found = candidates.enumerated().map { index, ref -> (dx: Int, dy: Int)? in
                guard let (image, ppp) = capture else { return nil }
                let offset: (dx: Int, dy: Int) = index < shownList.count ? current : (0, 0)
                let here = inStrip(ref.rects).map { $0.offsetBy(dx: CGFloat(offset.dx), dy: CGFloat(offset.dy)) }
                // Close enough counts: names already shown keep following through slightly-off
                // mid-slide frames, and a layout seen at one spot two frames in a row appears while
                // the row finishes its last sub-point creep (~0.2 s sooner than an exact match).
                let shown = index < shownList.count
                let threshold = CaptionFingerprint.followThreshold
                if let now = CaptionFingerprint(image: image, rects: here, pointsPerPixel: ppp) {
                    let differences = ref.fingerprint.captionDifferences(to: now)
                    if shown { shownDifferences = differences }
                    if (differences.max() ?? 1) < threshold { return offset }
                }
                guard let best = CaptionFingerprint.bestShift(ref.fingerprint, expectedAt: inStrip(ref.rects), in: image,
                                                              pointsPerPixel: ppp, maxShift: followRange),
                      best.difference < threshold else { return nil }
                return (best.dx, best.dy)
            }
            let captionDifferences = shownDifferences
            // Each template's captions as they look now, with backdrops sampled from this frame.
            let templateReadings = templates.map { t -> (CaptionFingerprint, [PatchStyle])? in
                guard let (image, ppp) = capture,
                      let now = CaptionFingerprint(image: image, rects: inStrip(t.rects), pointsPerPixel: ppp), now.hasContent else { return nil }
                let styles = inStrip(t.rects).map {
                    BackgroundSampler.style(for: $0, in: image, pointsPerPixel: ppp).offsetBy(dx: 0, dy: stripTop)
                }
                return (now, styles)
            }
            await MainActor.run {
                self.fingerprintInFlight = false
                guard capture != nil, session == self.gateSession, self.detector.isOpen else { return }
                // Names were hidden while this capture ran (the pointer entered the bar): it shows
                // the layout from before, so it must not bring those names back.
                guard hides == self.hideCount else { return }
                // A new layout at rest replaces whatever is shown.
                if let i = self.arrived(candidates: candidates, found: found, from: shownList.count) {
                    self.arrive(candidates[i], at: found[i]!)
                    return
                }
                if let (template, fingerprint, styles) = self.templateAtRest(templates, templateReadings) {
                    let ref = Reference(signature: sig, fingerprint: fingerprint,
                                        styled: Array(zip(template.placements, styles)))
                    self.arrive(ref, at: (0, 0))
                    return
                }
                guard let shownRef = self.shownReference else { return }
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
                    let moved = Set((captionDifferences ?? []).indices.filter { captionDifferences![$0] >= CaptionFingerprint.followThreshold })
                    let kept = shownRef.placements.count - moved.count
                    if captionDifferences == nil || kept <= 0 {
                        self.layoutChanged(from: shownRef)
                    } else {
                        // Some captions moved (a desktop added or removed next to them), the rest
                        // are where they were: keep those names while the new layout is learned.
                        self.hideCaptions(moved, of: shownRef)
                    }
                }
            }
        }
    }

    /// A template whose captions are on screen and unchanged since the previous frame: at rest.
    private func templateAtRest(_ templates: [Reference], _ readings: [(CaptionFingerprint, [PatchStyle])?])
        -> (Reference, CaptionFingerprint, [PatchStyle])? {
        var seen: [String: CaptionFingerprint] = [:]
        var rested: (Reference, CaptionFingerprint, [PatchStyle])?
        // Where thumbnail captions would be, the collapsed bar shows windows, which can be still and
        // detailed too: those count only once the top row of captions is gone (the bar expanded).
        let collapsed = zip(templates, readings).filter { $0.0.isCollapsedBar }
        let barExpanded = !collapsed.isEmpty && collapsed.allSatisfy { $0.1 == nil }
        for (template, reading) in zip(templates, readings) {
            guard let (now, styles) = reading, template.isCollapsedBar || barExpanded else { continue }
            if rested == nil, let before = lastTemplateReadings[template.key], before.matches(now) {
                rested = (template, now, styles)
            }
            seen[template.key] = now
        }
        lastTemplateReadings = rested == nil ? seen : [:]
        return rested
    }

    /// Part of a signature that names the desktops in order, without which one is current.
    private static func order(of signature: String) -> Substring {
        signature.split(separator: "|", maxSplits: 1).last ?? ""
    }

    /// Index (at or after `start`) of a layout found at one spot for a few frames in a row.
    /// Mid-slide the spot changes every frame. Where it rests may be a few points from where it
    /// was learned (the thumbnail row creeps for a second): `arrive` moves it there.
    private func arrived(candidates: [Reference], found: [(dx: Int, dy: Int)?], from start: Int) -> Int? {
        guard start < candidates.count,
              let i = (start..<candidates.count).first(where: { found[$0].map { $0 == (0, 0) } ?? false })
                ?? (start..<candidates.count).first(where: { found[$0] != nil }),
              let offset = found[i] else {
            arrivingKey = nil
            return nil
        }
        let ref = candidates[i]
        if arrivingKey != ref.key {
            arrivingKey = ref.key
            arriving.reset()
        }
        return arriving.observe(dx: offset.dx, dy: offset.dy) ? i : nil
    }

    private func arrive(_ ref: Reference, at offset: (dx: Int, dy: Int)) {
        if ref.isCollapsedBar, let hoverHide, pointerInBar(ref) {
            noExpansionBelowY = min(hoverHide.y, pointerY())
        }
        hoverHide = nil
        let resting = offset == (0, 0) ? ref : ref.offsetBy(dx: CGFloat(offset.dx), dy: CGFloat(offset.dy))
        settlingSince = nil
        pendingLayout = nil
        remember(resting)
        render(resting)
        confirm(resting)
    }

    /// Hides the names over captions that moved, keeps the others, and learns the new layout.
    private func hideCaptions(_ moved: Set<Int>, of ref: Reference) {
        let newlyHidden = moved.subtracting(hiddenCaptions)
        guard !newlyHidden.isEmpty else { return }
        hiddenCaptions.formUnion(newlyHidden)
        renderer.hide(newlyHidden)
        overlaysChanged()
        if settlingSince == nil { beginSettling() }
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
        hide("captions changed")
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
    /// The margin is a guess (macOS expands a few points below the captions): when the bar does
    /// not expand after all, the names come back and stay until the pointer moves further up.
    private func pointerTick() {
        let y = pointerY()
        guard let shownRef = shownReference, shownRef.isCollapsedBar else {
            if let reference = references.first(where: \.isCollapsedBar), !pointerInBar(reference) { noExpansionBelowY = nil }
            return
        }
        guard pointerInBar(shownRef) else { noExpansionBelowY = nil; return }
        if let floor = noExpansionBelowY, y >= floor { return }
        hoverHide = (at: Date(), y: y)
        layoutChanged(from: shownRef)
    }

    private func pointerInBar(_ ref: Reference) -> Bool {
        pointerY() < ref.bandHeight + Self.barEntryMargin
    }

    /// Collapsed names hidden for the pointer are not shown again while the bar may still be
    /// starting to expand (its captions stay put for a frame or two first).
    private func hiddenForPointer(_ ref: Reference) -> Bool {
        guard ref.isCollapsedBar, pointerInBar(ref) else { return false }
        guard let hoverHide else { return noExpansionBelowY.map { pointerY() < $0 } ?? true }
        return Date().timeIntervalSince(hoverHide.at) < Self.expansionStartsWithin
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
        // Redrawn when it differs, or when some names were hidden (their captions moved and came
        // back to the same place, as when a desktop is added after them).
        if !LayoutStabilizer.same(ref.styled.map(\.0), shown) || !hiddenCaptions.isEmpty {
            renderer.show(ref.styled)
            hiddenCaptions = []
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

    private func hide(_ reason: String) {
        lastHide = "\(reason) at \(Date().formatted(date: .omitted, time: .standard))"
        hideCount += 1
        lastTemplateReadings = [:]
        hiddenCaptions = []
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
                // A fresh screenshot, not the live stream: a stream frame can still hold our own names
                // for a moment after they change, and reading those breaks the caption mapping.
                let (image, ppp) = try await ScreenBandCapture.capture(heightPoints: band)
                let labels = try rows.map { try recognizer.recognize(in: image, pointsPerPixel: ppp, rowMidYs: $0) }
                    ?? recognizer.recognize(in: image, pointsPerPixel: ppp)
                let placements = LabelMapper.placements(labels: labels, displaySpaces: displaySpaces, names: names)
                    .map(LayoutStabilizer.snappedToRow)
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
        // Read against an older list of desktops (one was added or removed meanwhile): stale.
        guard sig == signature() else { return }
        scanInFlight = false
        // The fingerprint watch drew a newer layout while this scan was running: it is stale.
        if shownReference != nil, started < shownAt { return }
        // A remembered layout is fading in ahead of its captions; the fingerprint confirms it.
        if anticipatedUntil != nil { return }
        // The capture still showed our own names (they were drawn just before it): it says
        // nothing about Mission Control's captions, so it must not count as a mismatch.
        // (A name like "Desktop 3" could be a real caption, so it is not counted.)
        let ownNames = Set(shown.map(\.name).filter { $0.range(of: #"^Desktop \d{1,2}$"#, options: .regularExpression) == nil })
        if !ownNames.isEmpty, labels.contains(where: { ownNames.contains($0.text) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeInterval) { [weak self] in self?.scan() }
            return
        }
        let row = LabelMapper.captionRow(in: labels)
        // A known row with no captions means the bar moved or changed shape, not a mismatch.
        // While settling the captions may simply not be drawn yet, so keep probing the fast path.
        let missedRow = !fullScan && row == nil
        if settling && row != nil { captionsSeenWhileSettling = true }
        if missedRow && !settling { forceFullScan = true }
        // Just after desktops were added, removed or moved, Mission Control is still rearranging
        // and the list of desktops can lag it: a mismatch then means "not ready", not "broken".
        let rearranging = Date().timeIntervalSince(desktopsChangedAt) < Self.rearrangeGrace
        let decision = gate.decide(ticket, placements: styled?.map(\.0), settling: settling || missedRow || rearranging)
        switch decision {
        case .ignore:
            return
        case .retry:
            if settlingSince == nil { settlingSince = Date(); stabilizer.reset() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeInterval) { [weak self] in self?.scan() }
        case .hide:
            settlingSince = nil
            hide("captions not matched")
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
            } else if !LayoutStabilizer.same(placements, shownNow, tolerance: LayoutStabilizer.rescanTolerance) {
                // Layout changed since it was drawn: hide and wait for it to settle.
                hide("rescan found a new layout")
                beginSettling()
                return
            }
            lastScanSummary = String(format: "%.2fs · %d named%@", elapsed, placements.count, fullScan ? " · full scan" : "")
            if let row { remember(row: row.midY) }
            guard let styled else { return }
            if let fingerprint {
                let ref = Reference(signature: sig, fingerprint: fingerprint, styled: styled)
                remember(ref)
                // The pointer just entered the bar: leave it to the fingerprint watch, which shows
                // these names again only if the bar does not expand.
                guard !hiddenForPointer(ref) else { return }
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
