import AppKit
import CoreImage
import ScreenCaptureKit

/// Frames stay in memory. Excluding our application prevents recursive lenses,
/// while leaving our overlays available to OBS and ordinary display recording.
final class MagnifierCapture: NSObject, SCStreamOutput, SCStreamDelegate {
  private var stream: SCStream?
  private var generation = 0
  private let queue = DispatchQueue(label: "studio.yelpoint.magnifier", qos: .userInitiated)
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private let lock = NSLock()
  private var pointer = CGPoint.zero
  private var displayFrame = CGRect.zero
  private var magnification: CGFloat = 1.8
  private var frameHandler: ((CGImage) -> Void)?
  private var errorHandler: ((String) -> Void)?

  func update(pointer: CGPoint, zoom: CGFloat) {
    lock.lock()
    self.pointer = pointer
    magnification = zoom
    lock.unlock()
  }
  func start(
    screen: NSScreen, onFrame: @escaping (CGImage) -> Void, onError: @escaping (String) -> Void
  ) {
    stop()
    let ticket = generation
    lock.lock()
    displayFrame = screen.frame
    lock.unlock()
    frameHandler = onFrame
    errorHandler = onError
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        guard ticket == self.generation else { return }
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID })
        else {
          throw NSError(
            domain: "YelPoint", code: 2, userInfo: [NSLocalizedDescriptionKey: tr("확대할 화면을 찾지 못했어요.", "Could not find the screen to magnify.")])
        }
        let ownApps = content.applications.filter {
          $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
          display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
        configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
        self.stream = stream
        try await stream.startCapture()
        if ticket != self.generation { try? await stream.stopCapture() }
      } catch {
        if ticket == self.generation { self.errorHandler?(error.localizedDescription) }
      }
    }
  }
  func stop() {
    generation += 1
    if let stream { Task { try? await stream.stopCapture() } }
    stream = nil
    frameHandler = nil
    errorHandler = nil
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer else {
      return
    }
    lock.lock()
    let point = pointer
    let frame = displayFrame
    let zoom = magnification
    lock.unlock()
    guard frame.width > 0, frame.height > 0 else { return }
    let image = CIImage(cvPixelBuffer: buffer)
    let sx = image.extent.width / frame.width
    let sy = image.extent.height / frame.height
    let w = min(image.extent.width, 234 * sx / zoom)
    let h = min(image.extent.height, 158 * sy / zoom)
    let x = min(image.extent.maxX - w, max(0, (point.x - frame.minX) * sx - w / 2))
    let y = min(image.extent.maxY - h, max(0, (point.y - frame.minY) * sy - h / 2))
    guard
      let cropped = imageContext.createCGImage(image, from: CGRect(x: x, y: y, width: w, height: h))
    else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.stream === stream else { return }
      self.frameHandler?(cropped)
    }
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.stream === stream else { return }
      self.errorHandler?(error.localizedDescription)
    }
  }
}
