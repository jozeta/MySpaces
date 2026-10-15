import AppKit
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// A live stream of the top of the main display while Mission Control is open. One-shot
/// screenshots take 75–180 ms each while Mission Control animates; a stream delivers each new
/// frame as it is drawn, so the caption watch reads the newest frame without waiting.
final class BandStream: NSObject, SCStreamOutput, @unchecked Sendable {
    /// Covers the collapsed bar's captions (~69 pt) and the thumbnail row's (~190 pt).
    static let heightPoints: CGFloat = 240
    /// A new filter shows in frames a little after `updateContentFilter` returns.
    static let filterTakesEffect: TimeInterval = 0.05

    struct Frame {
        let image: CGImage
        let at: Date
        let pointsPerPixel: CGFloat
        /// Taken with a filter built after our overlay windows last changed (so they are excluded).
        let trusted: Bool
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "MySpaces.BandStream")
    private var stream: SCStream?
    private var latest: (image: CGImage, at: Date)?
    private var pointsPerPixel: CGFloat = 1
    private var filterAppliedAt = Date.distantPast
    private var generation = 0

    func start() {
        let gen = lock.withLock { generation += 1; return generation }
        Task {
            guard let (filter, width) = try? await Self.makeFilter() else { return }
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: 0, y: 0, width: width, height: Self.heightPoints)
            config.width = Int(width * scale)
            config.height = Int(Self.heightPoints * scale)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 3
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await stream.startCapture()
            } catch {
                return
            }
            let current = lock.withLock {
                guard gen == generation else { return false }
                self.stream = stream
                pointsPerPixel = 1 / scale
                filterAppliedAt = Date()
                return true
            }
            if !current { try? await stream.stopCapture() } // closed while starting
        }
    }

    func stop() {
        lock.lock()
        generation += 1
        let stream = self.stream
        self.stream = nil
        latest = nil
        lock.unlock()
        if let stream { Task { try? await stream.stopCapture() } }
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return stream != nil && latest != nil
    }

    /// Our overlay windows changed: once the window server lists them, exclude them again.
    func overlaysChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + ScreenBandCapture.windowListLag) { [weak self] in
            Task { await self?.refreshFilter() }
        }
    }

    private func refreshFilter() async {
        let stream = lock.withLock { self.stream }
        guard let stream, let (filter, _) = try? await Self.makeFilter() else { return }
        let started = Date()
        guard (try? await stream.updateContentFilter(filter)) != nil else { return }
        lock.withLock { filterAppliedAt = max(filterAppliedAt, started) }
    }

    /// The newest frame, cropped to the strip from `top` (points), `height` points tall.
    func frame(top: CGFloat, height: CGFloat) -> Frame? {
        lock.lock()
        let latest = self.latest, ppp = pointsPerPixel, applied = filterAppliedAt
        lock.unlock()
        guard let latest else { return nil }
        let rect = CGRect(x: 0, y: (top / ppp).rounded(.down), width: CGFloat(latest.image.width),
                          height: (height / ppp).rounded(.up))
        guard let strip = latest.image.cropping(to: rect) else { return nil }
        let settled = ScreenBandCapture.overlaysChangedAt.addingTimeInterval(ScreenBandCapture.windowListLag)
        return Frame(image: strip, at: latest.at, pointsPerPixel: ppp, trusted: applied >= settled && latest.at > applied.addingTimeInterval(Self.filterTakesEffect))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        guard let image else { return }
        lock.lock(); latest = (image, Date()); lock.unlock()
    }

    private static func makeFilter() async throws -> (SCContentFilter, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return (SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []), CGFloat(display.width))
    }
}
