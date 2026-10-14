import AppKit
import ScreenCaptureKit

enum ScreenBandCapture {
    /// Captures the top `heightPoints` of the main display, excluding MySpaces' own overlay windows
    /// so a custom name is never read back as a caption.
    static func capture(heightPoints: CGFloat) async throws -> (CGImage, pointsPerPixel: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: heightPoints)
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(heightPoints * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, 1 / scale)
    }
}
