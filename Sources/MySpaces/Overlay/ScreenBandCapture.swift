import AppKit
import ScreenCaptureKit

enum ScreenBandCapture {
    /// Captures the top `heightPoints` of the main display, excluding MySpaces' own overlay windows
    /// so a custom name is never read back as a caption.
    static func capture(heightPoints: CGFloat) async throws -> (CGImage, pointsPerPixel: CGFloat) {
        try await capture(heightPoints: heightPoints, filter: nil)
    }

    /// Cached filter: building SCShareableContent each frame is too slow for the 30 Hz watch.
    /// The filter only excludes the overlay windows that existed when it was built, so it must be
    /// invalidated whenever overlays are shown or hidden.
    nonisolated(unsafe) private static var cachedFilter: (filter: SCContentFilter, width: CGFloat, builtAt: Date)?
    nonisolated(unsafe) private static var windowsChangedAt = Date.distantPast
    /// The window server lists newly shown windows a little late: a filter built sooner than this
    /// after our overlays changed may not exclude them, and its captures can show our own names.
    static let windowListLag: TimeInterval = 0.15

    /// Call whenever overlays are shown or hidden.
    static func invalidateFilter() {
        cachedFilter = nil
        windowsChangedAt = Date()
    }

    /// Like `capture(heightPoints:filter: true)`, and says whether the filter is sure to exclude
    /// every overlay window (built long enough after they last changed).
    static func captureWatched(heightPoints: CGFloat) async throws -> (CGImage, pointsPerPixel: CGFloat, trusted: Bool) {
        let settledAt = windowsChangedAt.addingTimeInterval(windowListLag)
        if let cached = cachedFilter, cached.builtAt < settledAt, Date() >= settledAt {
            cachedFilter = nil // rebuild now that the window list has caught up
        }
        let (image, ppp) = try await capture(heightPoints: heightPoints, filter: true)
        return (image, ppp, (cachedFilter?.builtAt ?? .distantPast) >= settledAt)
    }

    static func capture(heightPoints: CGFloat, filter reuse: Bool?) async throws -> (CGImage, pointsPerPixel: CGFloat) {
        if reuse == true, let cached = cachedFilter {
            return try await shoot(cached.filter, width: cached.width, heightPoints: heightPoints)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        cachedFilter = (filter, CGFloat(display.width), Date())
        return try await shoot(filter, width: CGFloat(display.width), heightPoints: heightPoints)
    }

    private static func shoot(_ filter: SCContentFilter, width: CGFloat, heightPoints: CGFloat) async throws -> (CGImage, pointsPerPixel: CGFloat) {
        let scale = CGFloat(filter.pointPixelScale)
        // Source and output must have exactly the same pixel size; a fractional height makes
        // ScreenCaptureKit rescale the frame (shifted, blurred), so snap to whole pixels.
        let pixelHeight = (heightPoints * scale).rounded(.up)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: width, height: pixelHeight / scale)
        config.width = Int(width * scale)
        config.height = Int(pixelHeight)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, 1 / scale)
    }
}
