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

    func show(_ items: [(LabelPlacement, PatchStyle)]) {
        hideAll()
        guard let screen = NSScreen.screens.first, !items.isEmpty else { return }
        // One centre line, so names in a row share a baseline.
        let mids = items.map(\.0.rect.midY).sorted()
        let rowMidY = mids[mids.count / 2]
        let text = rowMidY < Self.collapsedBarMaxY ? Self.collapsedText : Self.thumbnailText
        for (placement, style) in items {
            let r = placement.rect
            let aligned = LabelPlacement(rect: CGRect(x: r.minX, y: rowMidY - r.height / 2, width: r.width, height: r.height),
                                         name: placement.name, spaceKey: placement.spaceKey, maxWidth: placement.maxWidth)
            windows.append(makeWindow(aligned, style, text: text, screenHeight: screen.frame.height))
        }
        origins = windows.map(\.frame.origin)
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

    /// The current positions become the new base: the layout itself was moved to where the names are.
    func rebase() {
        origins = windows.map(\.frame.origin)
        offset = .zero
    }

    struct TextStyle {
        let size: CGFloat
        let weight: NSFont.Weight
        let opacity: CGFloat
    }
    /// Mission Control's caption text, fitted pixel by pixel against real captions (macOS 27).
    /// The top bar: 14 pt regular, white at ~72%.
    static let collapsedText = TextStyle(size: 14, weight: .regular, opacity: 0.72)
    /// Under thumbnails the same captions are shrunk ~0.84×, which reads as 11.75 pt medium at ~63%.
    static let thumbnailText = TextStyle(size: 11.75, weight: .medium, opacity: 0.63)
    /// Caption rows above this (points from the top) are the collapsed bar.
    static let collapsedBarMaxY: CGFloat = 120

    private func makeWindow(_ p: LabelPlacement, _ style: PatchStyle, text: TextStyle, screenHeight: CGFloat) -> NSWindow {
        let label = NSTextField(labelWithString: p.name)
        label.font = .systemFont(ofSize: text.size, weight: text.weight)
        label.textColor = NSColor.white.withAlphaComponent(text.opacity)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.sizeToFit()

        let height = max(p.rect.height + 6, label.frame.height + 4)
        let width = max(p.rect.width + 4, min(label.frame.width + 8, p.maxWidth))
        // The name's box, in points from the screen's top left.
        let nameBox = CGRect(x: p.rect.midX - width / 2, y: p.rect.midY - height / 2, width: width, height: height)
        var covered = nameBox
        if case let .backdrop(b) = style { covered = covered.union(b.rect) }
        covered = covered.integral
        let frame = NSRect(x: covered.minX, y: screenHeight - covered.maxY, width: covered.width, height: covered.height)

        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Mission Control's Spaces bar is drawn above .floating/.modalPanel; Dock level and up show.
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false

        let background = NSView(frame: NSRect(origin: .zero, size: frame.size))
        background.wantsLayer = true
        // The name's box inside the window (AppKit's bottom-left origin).
        let box = NSRect(x: nameBox.minX - covered.minX, y: covered.maxY - nameBox.maxY, width: width, height: height)
        switch style {
        case let .backdrop(b):
            let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
            background.layer?.contents = Self.image(of: b, covering: covered, scale: scale)
            background.layer?.contentsGravity = .resize
        case .pill:
            // Solid Graphite (#292D30) pill: predictable on any wallpaper, unlike a blur material.
            // Fully opaque, or the caption underneath shows through.
            let pill = CALayer()
            pill.frame = box
            pill.backgroundColor = NSColor(srgbRed: 0x29 / 255, green: 0x2D / 255, blue: 0x30 / 255, alpha: 1).cgColor
            pill.cornerRadius = 6
            background.layer?.addSublayer(pill)
        }
        label.frame = NSRect(x: box.minX + 4, y: box.minY + (height - label.frame.height) / 2, width: width - 8, height: label.frame.height)
        background.addSubview(label)
        window.contentView?.addSubview(background)
        window.orderFrontRegardless()
        return window
    }

    /// The rebuilt background for `area` (points, screen top left), at the screen's pixel scale.
    private static func image(of b: PatchBackdrop, covering area: CGRect, scale: CGFloat) -> CGImage? {
        let w = max(1, Int((area.width * scale).rounded())), h = max(1, Int((area.height * scale).rounded()))
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let py = area.minY + (CGFloat(y) + 0.5) / scale
            for x in 0..<w {
                let c = b.colour(at: CGPoint(x: area.minX + (CGFloat(x) + 0.5) / scale, y: py))
                let i = (y * w + x) * 4
                pixels[i] = UInt8(max(0, min(255, (c.red * 255).rounded())))
                pixels[i + 1] = UInt8(max(0, min(255, (c.green * 255).rounded())))
                pixels[i + 2] = UInt8(max(0, min(255, (c.blue * 255).rounded())))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
