import AppKit
import MySpacesCore

/// One borderless, click-through window per caption, drawn above Mission Control.
@MainActor
final class OverlayRenderer {
    private var windows: [NSWindow] = []

    func hideAll() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func show(_ items: [(LabelPlacement, PatchStyle)]) {
        hideAll()
        guard let screen = NSScreen.screens.first else { return }
        for (placement, style) in items {
            windows.append(makeWindow(placement, style, screenHeight: screen.frame.height))
        }
    }

    private func makeWindow(_ p: LabelPlacement, _ style: PatchStyle, screenHeight: CGFloat) -> NSWindow {
        // Matches Mission Control's caption style (regular weight, ~0.68 × caption box height).
        let fontSize = min(14, max(10, (p.rect.height * 0.68).rounded()))
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
