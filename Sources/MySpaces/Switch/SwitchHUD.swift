import AppKit
import MySpacesCore

/// The desktop's name, large, in a translucent panel in the middle of the screen, shown briefly
/// after switching desktops (like the volume and brightness HUDs).
@MainActor
final class SwitchHUD {
    static let enabledKey = "showNameWhenSwitching"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let fontSize: CGFloat = 72
    static let padding = NSSize(width: 96, height: 56)
    static let minimumWidth: CGFloat = 420
    /// Share of the screen width a long name may take before it fades out.
    static let maximumWidthShare: CGFloat = 0.8
    static let cornerRadius: CGFloat = 32
    static let fadeIn: TimeInterval = 0.12
    static let hold: TimeInterval = 0.9
    static let fadeOut: TimeInterval = 0.35

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    func show(_ name: String) {
        guard let screen = NSScreen.screens.first else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        label.stringValue = name
        label.sizeToFit()
        let fit = NameFit(textWidth: label.frame.width, minimumWidth: Self.minimumWidth,
                          maximumWidth: screen.frame.width * Self.maximumWidthShare, padding: Self.padding.width)
        let size = NSSize(width: fit.width, height: label.frame.height + Self.padding.height)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
        label.alignment = fit.fades ? .left : .center
        label.frame = NSRect(x: Self.padding.width / 2, y: (size.height - label.frame.height) / 2,
                             width: size.width - Self.padding.width, height: label.frame.height)
        applyFade(fit)

        hideWork?.cancel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.fadeAway() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeIn + Self.hold, execute: work)
    }

    private func fadeAway() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A newer name may have been shown while this one faded.
                if self?.panel?.alphaValue == 0 { self?.panel?.orderOut(nil) }
            }
        })
    }

    private func applyFade(_ fit: NameFit) {
        label.wantsLayer = true
        guard fit.fades else { label.layer?.mask = nil; return }
        let mask = CAGradientLayer()
        mask.frame = label.bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double(fit.fadeStart)), 1]
        label.layer?.mask = mask
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above full-screen apps and on whichever desktop is now showing.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        // A behind-window blur ignores the layer's corner radius; a stretchable mask image rounds
        // it (and the window shadow follows the mask).
        blur.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        blur.autoresizingMask = [.width, .height]
        panel.contentView = blur

        label.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        blur.addSubview(label)
        return panel
    }
}
