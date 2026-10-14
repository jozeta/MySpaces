import AppKit
import MySpacesCore

/// One borderless, click-through window per caption, drawn above Mission Control.
@MainActor
final class OverlayRenderer {
    private var windows: [NSWindow] = []
    private var origins: [NSPoint] = []
    private var offset = CGVector.zero

    func hideAll() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        origins.removeAll()
        offset = .zero
    }

    /// `fadeIn` > 0 fades the names in, in step with Mission Control's own caption animation.
    func show(_ items: [(LabelPlacement, PatchStyle)], fadeIn: TimeInterval = 0) {
        hideAll()
        guard let screen = NSScreen.screens.first, !items.isEmpty else { return }
        // One size for the whole row: OCR box heights vary per caption, Mission Control's don't.
        let heights = items.map(\.0.rect.height).sorted()
        let fontSize = min(14, max(10, (heights[heights.count / 2] * 0.68).rounded()))
        // ...and one centre line, so names in a row share a baseline.
        let mids = items.map(\.0.rect.midY).sorted()
        let rowMidY = mids[mids.count / 2]
        for (placement, style) in items {
            let r = placement.rect
            let aligned = LabelPlacement(rect: CGRect(x: r.minX, y: rowMidY - r.height / 2, width: r.width, height: r.height),
                                         name: placement.name, spaceKey: placement.spaceKey, maxWidth: placement.maxWidth)
            windows.append(makeWindow(aligned, style, fontSize: fontSize, screenHeight: screen.frame.height))
        }
        origins = windows.map(\.frame.origin)
        if fadeIn > 0 {
            windows.forEach { $0.alphaValue = 0 }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeIn
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                windows.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    /// Moves every name by (dx, dy) points from where it was drawn (screen top-left coordinates),
    /// so names follow captions through the last few points of Mission Control's animation.
    func move(dx: Int, dy: Int) {
        let target = CGVector(dx: CGFloat(dx), dy: CGFloat(dy))
        guard target != offset else { return }
        offset = target
        for (window, origin) in zip(windows, origins) {
            window.setFrameOrigin(NSPoint(x: origin.x + target.dx, y: origin.y - target.dy))
        }
    }

    /// Matches Mission Control's caption style (regular weight, ~0.68 × caption box height).
    private func makeWindow(_ p: LabelPlacement, _ style: PatchStyle, fontSize: CGFloat, screenHeight: CGFloat) -> NSWindow {
        let label = NSTextField(labelWithString: p.name)
        label.font = .systemFont(ofSize: fontSize, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.sizeToFit()

        let height = max(p.rect.height + 6, label.frame.height + 4)
        let width = max(p.rect.width + 4, min(label.frame.width + 8, p.maxWidth))
        let frame = NSRect(x: p.rect.midX - width / 2, y: screenHeight - p.rect.midY - height / 2,
                           width: width, height: height)

        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Mission Control's Spaces bar is drawn above .floating/.modalPanel; Dock level and up show.
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false

        let background: NSView
        switch style {
        case let .native(r, g, b):
            background = NSView(frame: NSRect(origin: .zero, size: frame.size))
            background.wantsLayer = true
            background.layer?.backgroundColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1).cgColor
            background.layer?.cornerRadius = 4
        case .pill:
            // Solid Graphite (#292D30) pill: predictable on any wallpaper, unlike a blur material.
            background = NSView(frame: NSRect(origin: .zero, size: frame.size))
            background.wantsLayer = true
            background.layer?.backgroundColor = NSColor(srgbRed: 0x29 / 255, green: 0x2D / 255, blue: 0x30 / 255, alpha: 0.92).cgColor
            background.layer?.cornerRadius = 6
        }
        label.frame = NSRect(x: 4, y: (height - label.frame.height) / 2, width: width - 8, height: label.frame.height)
        background.addSubview(label)
        window.contentView?.addSubview(background)
        window.orderFrontRegardless()
        return window
    }
}
