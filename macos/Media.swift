import AVFoundation
import AppKit
import ApplicationServices
import ScreenCaptureKit

func pixelAligned(_ rect: CGRect, scale s: CGFloat) -> CGRect {
  let x0 = (rect.minX * s).rounded() / s, y0 = (rect.minY * s).rounded() / s
  return CGRect(
    x: x0, y: y0, width: (rect.maxX * s).rounded() / s - x0, height: (rect.maxY * s).rounded() / s - y0)
}

enum ScreenGrab {
  /// `rect` is in the overlay's bottom-left coordinates. Annotations stay in the
  /// image; only the windows in `excluding` (our controls) are left out.
  @MainActor static func capture(screen: NSScreen, rect: CGRect, excluding ids: Set<CGWindowID>)
    async throws -> CGImage
  {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
      throw NSError(
        domain: "YelPoint", code: 3, userInfo: [NSLocalizedDescriptionKey: tr("캡처할 화면을 찾지 못했어요.", "Could not find the screen to capture.")])
    }
    let filter = SCContentFilter(
      display: display, excludingWindows: content.windows.filter { ids.contains($0.windowID) })
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = CGRect(
      x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
    configuration.width = Int((rect.width * screen.backingScaleFactor).rounded())
    configuration.height = Int((rect.height * screen.backingScaleFactor).rounded())
    configuration.showsCursor = false
    configuration.capturesAudio = false
    return try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: configuration)
  }
}

/// Records one display to an MP4 on the external SSD. Writer calls stay on `queue`.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate,
  AVCaptureAudioDataOutputSampleBufferDelegate
{
  private var stream: SCStream?
  private var microphone: AVCaptureSession?
  private var audioInput: AVAssetWriterInput?
  private var sessionStart = CMTime.invalid
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var started = false
  private var url: URL?
  private var errorHandler: ((String) -> Void)?
  private let queue = DispatchQueue(label: "studio.yelpoint.recorder", qos: .userInitiated)
  private let microphoneQueue = DispatchQueue(label: "studio.yelpoint.microphone")

  func prepare(url: URL, width: Int, height: Int, audio: Bool) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 4],
      ])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
    if audio {
      let track = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
          AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
        ])
      track.expectsMediaDataInRealTime = true
      writer.add(track)
      audioInput = track
    }
    guard writer.startWriting() else {
      throw writer.error
        ?? NSError(
          domain: "YelPoint", code: 4, userInfo: [NSLocalizedDescriptionKey: tr("녹화 파일을 만들지 못했어요.", "Could not create the recording file.")])
    }
    self.writer = writer
    self.input = input
    self.url = url
  }
  /// Returns whether a microphone is being recorded.
  @MainActor func start(
    screen: NSScreen, excluding ids: Set<CGWindowID>, url: URL, useMicrophone: Bool,
    onError: @escaping (String) -> Void
  ) async throws -> Bool {
    // Off-screen windows too: a panel opened mid-recording must stay out of the video.
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
      throw NSError(
        domain: "YelPoint", code: 3, userInfo: [NSLocalizedDescriptionKey: tr("녹화할 화면을 찾지 못했어요.", "Could not find the screen to record.")])
    }
    let size = recordingSize(
      CGSize(
        width: screen.frame.width * screen.backingScaleFactor,
        height: screen.frame.height * screen.backingScaleFactor))
    let session = useMicrophone ? makeMicrophoneSession() : nil
    try prepare(url: url, width: size.width, height: size.height, audio: session != nil)
    errorHandler = onError
    let filter = SCContentFilter(
      display: display, excludingWindows: content.windows.filter { ids.contains($0.windowID) })
    let configuration = SCStreamConfiguration()
    configuration.width = size.width
    configuration.height = size.height
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configuration.queueDepth = 6
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = true
    configuration.capturesAudio = false
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    self.stream = stream
    try await stream.startCapture()
    if let session {
      microphone = session
      microphoneQueue.async { session.startRunning() }
    }
    return session != nil
  }
  /// The fixed PCM format keeps every microphone on the path the self-test covers.
  private func makeMicrophoneSession() -> AVCaptureSession? {
    guard let device = AVCaptureDevice.default(for: .audio),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return nil }
    let session = AVCaptureSession()
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddInput(input), session.canAddOutput(output) else { return nil }
    session.addInput(input)
    session.addOutput(output)
    return session
  }
  /// Call on `queue`, or from a test that owns the recorder.
  func appendAudio(_ sample: CMSampleBuffer) {
    guard let writer, let audioInput, writer.status == .writing, started,
      sample.presentationTimeStamp >= sessionStart, audioInput.isReadyForMoreMediaData
    else { return }
    audioInput.append(sample)
  }
  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) { appendAudio(sampleBuffer) }
  /// Call on `queue`, or from a test that owns the recorder.
  func append(_ sample: CMSampleBuffer) {
    guard let writer, let input, writer.status == .writing, sample.imageBuffer != nil else {
      return
    }
    if !started {
      sessionStart = sample.presentationTimeStamp
      writer.startSession(atSourceTime: sessionStart)
      started = true
    }
    if input.isReadyForMoreMediaData { input.append(sample) }
  }
  /// `completion` runs off the main thread, so quitting can wait for it.
  func stop(completion: @escaping (Result<URL, Error>) -> Void) {
    let active = stream
    let session = microphone
    stream = nil
    microphone = nil
    errorHandler = nil
    Task {
      if let active { try? await active.stopCapture() }
      self.microphoneQueue.async {
        session?.stopRunning()
        self.queue.async { self.finish(completion) }
      }
    }
  }
  private func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
    guard let writer, let input, let url else {
      completion(.failure(NSError(domain: "YelPoint", code: 5, userInfo: [NSLocalizedDescriptionKey: tr("녹화가 시작되기 전에 멈췄어요. 다시 녹화해 주세요.", "Recording stopped before it started. Please record again.")])))
      return
    }
    self.writer = nil
    self.input = nil
    guard started else {
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: url)
      completion(
        .failure(
          NSError(
            domain: "YelPoint", code: 6,
            userInfo: [NSLocalizedDescriptionKey: tr("녹화된 화면이 없어요. 다시 시도해 주세요.", "Nothing was recorded. Please try again.")])))
      return
    }
    input.markAsFinished()
    audioInput?.markAsFinished()
    audioInput = nil
    writer.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
    writer.finishWriting {
      if writer.status == .completed {
        completion(.success(url))
      } else {
        completion(.failure(writer.error ?? NSError(domain: "YelPoint", code: 7, userInfo: [NSLocalizedDescriptionKey: tr("녹화 파일을 마무리하지 못했어요. 남은 저장 공간을 확인해 주세요.", "Could not finish the recording file. Check the free space.")])))
      }
    }
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid else { return }
    append(sampleBuffer)
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    let handler = errorHandler
    DispatchQueue.main.async { handler?(error.localizedDescription) }
  }
}

/// A crosshair with a camera badge, so capture mode is obvious before the drag starts.
let captureCursor: NSCursor = {
  let image = NSImage(size: CGSize(width: 32, height: 32), flipped: true) { _ in
    for (width, color) in [(CGFloat(3.5), NSColor.black.withAlphaComponent(0.7)), (1.6, NSColor.white)] {
      color.setStroke()
      for (a, b) in [
        (CGPoint(x: 2, y: 16), CGPoint(x: 12, y: 16)), (CGPoint(x: 20, y: 16), CGPoint(x: 30, y: 16)),
        (CGPoint(x: 16, y: 2), CGPoint(x: 16, y: 12)), (CGPoint(x: 16, y: 20), CGPoint(x: 16, y: 30)),
      ] {
        let line = NSBezierPath()
        line.move(to: a)
        line.line(to: b)
        line.lineWidth = width
        line.lineCapStyle = .round
        line.stroke()
      }
    }
    Look.dock.setFill()
    NSBezierPath(roundedRect: CGRect(x: 18, y: 19, width: 13, height: 10), xRadius: 2.5, yRadius: 2.5).fill()
    Look.lime.setFill()
    NSBezierPath(roundedRect: CGRect(x: 19, y: 20, width: 11, height: 8), xRadius: 2, yRadius: 2).fill()
    Look.dock.setFill()
    NSBezierPath(ovalIn: CGRect(x: 22, y: 21.5, width: 5, height: 5)).fill()
    return true
  }
  return NSCursor(image: image, hotSpot: CGPoint(x: 16, y: 16))
}()

/// A menu item that runs a closure, for menus built in code.
final class ClosureMenuItem: NSMenuItem {
  private let run: () -> Void
  init(_ title: String, _ run: @escaping () -> Void) {
    self.run = run
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError() }
  @objc private func fire() { run() }
}

enum UndoTarget {
  case display(CGDirectDisplayID)
  case sticker(StickerView)
  case cleared(ClearedInk)
}

/// What the trash button removed, kept so Undo can bring it all back.
struct ClearedInk {
  let displays: [(CGDirectDisplayID, [InkStroke])]
  let stickers: [(StickerView, StickerView.Ink)]
  let history: [UndoTarget]
}

/// Drawn only; a press here moves the pinned image, even while the pen is on.
final class GripView: NSView {
  override var mouseDownCanMoveWindow: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    Look.dock.setFill()
    NSBezierPath(ovalIn: bounds).fill()
    let icon = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [Look.paper])))
    icon?.draw(in: bounds.insetBy(dx: 5, dy: 5))
  }
}

final class StickerView: NSView {
  let image: NSImage
  /// Ink and typed notes on this image. They move with it and are saved and copied with it.
  private(set) var strokes: [InkStroke] = []
  struct Note {
    let text: String
    let origin: CGPoint
    let color: NSColor
    let size: CGFloat
  }
  private(set) var notes: [Note] = []
  /// true for a note, false for a stroke, in the order they were added, for undo.
  private var order: [Bool] = []
  var hasInk: Bool { !order.isEmpty }
  struct Ink {
    let strokes: [InkStroke]
    let notes: [Note]
    let order: [Bool]
  }
  var ink: Ink {
    get { Ink(strokes: strokes, notes: notes, order: order) }
    set {
      strokes = newValue.strokes
      notes = newValue.notes
      order = newValue.order
      needsDisplay = true
    }
  }
  /// The big labelled buttons under the image, so nobody has to know about right-clicking.
  var bar: QuietPanel?
  var barObserver: NSObjectProtocol?
  /// The close button and the move grip, in this view's coordinates.
  private(set) var closeFrame = CGRect.zero
  private(set) var gripFrame = CGRect.zero
  /// Where the context menu was opened, so a note starts there.
  var menuPoint = CGPoint.zero
  weak var controller: AppController?
  private(set) var editor: NSTextField?
  func addStroke(_ stroke: InkStroke) {
    strokes.append(stroke)
    order.append(false)
    needsDisplay = true
  }
  func undoLast() -> Bool {
    guard let note = order.popLast() else { return false }
    if note { notes.removeLast() } else { strokes.removeLast() }
    needsDisplay = true
    return true
  }
  func clearInk() {
    strokes = []
    notes = []
    order = []
    needsDisplay = true
  }
  func beginNote(color: NSColor) {
    guard editor == nil else { return }
    let field = NSTextField(string: "")
    field.frame = CGRect(x: menuPoint.x, y: menuPoint.y - 16, width: 240, height: 32)
    field.font = .systemFont(ofSize: 24, weight: .semibold)
    field.textColor = color
    field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
    field.drawsBackground = true
    field.isBordered = false
    field.focusRingType = .none
    field.placeholderString = tr("입력 후 Enter", "Type, then Enter")
    field.target = self
    field.action = #selector(commitNote)
    field.cell?.sendsActionOnEndEditing = true
    addSubview(field)
    editor = field
    window?.makeKey()
    window?.makeFirstResponder(field)
  }
  @objc func commitNote() {
    guard let field = editor else { return }
    editor = nil
    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    field.removeFromSuperview()
    if !text.isEmpty, let color = field.textColor {
      notes.append(Note(text: text, origin: CGPoint(x: field.frame.minX + 2, y: field.frame.minY + 2), color: color, size: 24))
      order.append(true)
      controller?.noteAdded(self)
    }
    needsDisplay = true
  }
  override func rightMouseDown(with event: NSEvent) {
    menuPoint = convert(event.locationInWindow, from: nil)
    super.rightMouseDown(with: event)
  }
  init(image: NSImage, size: CGSize, onClose: @escaping () -> Void) {
    self.image = image
    super.init(frame: CGRect(origin: .zero, size: size))
    wantsLayer = true
    layer?.borderColor = Look.lime.cgColor
    layer?.borderWidth = 2
    let close = ActionButton(
      frame: CGRect(x: max(0, size.width - 28), y: max(0, size.height - 28), width: 24, height: 24),
      callback: onClose)
    close.isBordered = false
    close.attributedTitle = NSAttributedString(
      string: "✕",
      attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Look.paper])
    close.wantsLayer = true
    close.layer?.backgroundColor = Look.dock.cgColor
    close.layer?.cornerRadius = 12
    close.toolTip = tr("붙인 이미지 닫기", "Close pasted image")
    close.setAccessibilityLabel(tr("붙인 이미지 닫기", "Close pasted image"))
    addSubview(close)
    closeFrame = close.frame
    let grip = GripView(frame: CGRect(x: 4, y: max(0, size.height - 28), width: 24, height: 24))
    grip.toolTip = tr("끌어서 옮기기", "Drag to move")
    addSubview(grip)
    gripFrame = grip.frame
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    image.draw(in: bounds)
    drawStrokes()
  }
  private func drawStrokes() {
    for stroke in strokes {
      guard let start = stroke.points.first else { continue }
      let path = NSBezierPath()
      path.lineWidth = stroke.width
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      path.move(to: start)
      if stroke.points.count == 1 { path.line(to: CGPoint(x: start.x + 0.1, y: start.y + 0.1)) }
      for p in stroke.points.dropFirst() { path.line(to: p) }
      stroke.color.setStroke()
      path.stroke()
    }
    for note in notes {
      note.text.draw(
        at: note.origin,
        withAttributes: [.font: NSFont.systemFont(ofSize: note.size, weight: .semibold), .foregroundColor: note.color])
    }
  }
  /// The image at its own resolution with the ink drawn on top.
  func composite() -> CGImage? {
    guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(
        data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    context.scaleBy(
      x: CGFloat(source.width) / bounds.width, y: CGFloat(source.height) / bounds.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    drawStrokes()
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
  }
}

extension AppController {
  var controlWindowIDs: Set<CGWindowID> {
    Set(
      ([toolbar, penPanel, settingsPanel, timerPanel, capturePanel, colorPanel, spotPanel, miniPanel, zoomPanel, phonePanel, qrPanel]
        .compactMap { $0 } + stickers.compactMap { ($0.contentView as? StickerView)?.bar }).map {
        CGWindowID($0.windowNumber)
      })
  }
  var capturesFolder: URL { storage.captures }
  func toast(_ text: String) {
    keyText = text
    keyUntil = ProcessInfo.processInfo.systemUptime + 2.5
    invalidateAll()
  }
  func ensureScreenAccess() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    // The self-test copy has its own bundle id and no permission; it never captures pixels.
    if ProcessInfo.processInfo.arguments.contains("--ui-self-test") { return true }
    withToolsSuspended { guideScreenAccess() }
    return CGPreflightScreenCaptureAccess()
  }
  /// A switch can look on while macOS still ties it to an older build, so the old
  /// record goes first. macOS only applies the permission after a relaunch.
  private func guideScreenAccess() {
    NSApp.activate(ignoringOtherApps: true)
    let ask = NSAlert()
    ask.messageText = tr("화면 기록 권한이 필요해요", "Screen Recording permission needed")
    ask.informativeText =
      tr("‘설정 열기’를 누르면 화면 기록 설정이 바로 열려요. 목록의 YelPoint 스위치를 켜 주세요. 예전에 켠 기록은 맞지 않을 수 있어서 먼저 지워 둘게요.", "Open Settings takes you to Screen Recording. Turn on the YelPoint switch in the list. Any old record that no longer matches is cleared first.")
    ask.addButton(withTitle: tr("설정 열기", "Open Settings"))
    ask.addButton(withTitle: tr("취소", "Cancel"))
    guard ask.runModal() == .alertFirstButtonReturn else { return }
    runQuietly("/usr/bin/tccutil", ["reset", "ScreenCapture", "studio.yelpoint.app"], wait: true)
    _ = CGRequestScreenCaptureAccess()
    if let page = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(page)
    }
    let done = NSAlert()
    done.messageText = tr("스위치를 켰으면 다시 시작해 주세요", "Restart once the switch is on")
    done.informativeText = tr("macOS는 앱을 다시 시작해야 권한을 적용해요. macOS가 ‘종료 후 다시 열기’를 물어보면 그걸 눌러도 돼요.", "macOS applies the permission after a restart. You can also choose Quit & Reopen if macOS offers it.")
    done.addButton(withTitle: tr("앱 다시 시작", "Restart App"))
    done.addButton(withTitle: tr("나중에", "Later"))
    if done.runModal() == .alertFirstButtonReturn { relaunch() }
  }
  /// The app redirects its own home folder, so helpers get a clean environment.
  private func runQuietly(_ path: String, _ arguments: [String], wait: Bool) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.environment = [:]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    if wait { task.waitUntilExit() }
  }
  func relaunch() {
    // The delay lets this copy quit, or the new one would hand over to it and exit.
    runQuietly("/bin/sh", ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath], wait: false)
    DispatchQueue.main.async { NSApp.terminate(nil) }
  }
  func beginSelection() {
    guard !toolsSuspended, ensureScreenAccess() else { return }
    finishStrokes()
    pen = false
    zoom = false
    capture.stop()
    capturedDisplay = nil
    magnifiedImage = nil
    hideToolPanels()
    selecting = true
    captureCursor.set()
    refreshTools()
    invalidateAll()
  }
  func finishSelection(screen: NSScreen, rect: CGRect) {
    // Drags land between pixels. A fractional area makes the capture resample and look soft,
    // so it snaps to whole pixels; the pinned image then sits exactly on the screen's pixels.
    let rect = pixelAligned(rect, scale: screen.backingScaleFactor)
    selecting = false
    NSCursor.arrow.set()
    guard rect.width >= 4, rect.height >= 4 else {
      refreshTools()
      invalidateAll()
      present(capturePanel)
      refreshTools()
      return
    }
    hideHalo = true
    pulses = []
    refreshTools()
    for (_, view) in overlays { view.display() }
    let ids = controlWindowIDs
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 80_000_000)
      do {
        let image = try await ScreenGrab.capture(screen: screen, rect: rect, excluding: ids)
        guard let self else { return }
        self.hideHalo = false
        self.store(
          image, scale: screen.backingScaleFactor,
          frame: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
      } catch {
        guard let self else { return }
        self.hideHalo = false
        self.invalidateAll()
        self.showMessage(tr("캡처하지 못했어요", "Could not capture"), error.localizedDescription)
      }
    }
  }
  /// The capture stays pinned where it was taken with the pen ready, so writing on it is immediate.
  func store(_ image: CGImage, scale: CGFloat, frame: CGRect? = nil) {
    lastCapture = image
    let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
    guard let frame else {
      present(capturePanel)
      refreshTools()
      toast(tr("캡처해서 복사했어요", "Captured and copied"))
      return
    }
    addSticker(NSImage(cgImage: image, size: size), at: frame)
    if !pen { toggle("pen") }
    toast(tr("캡처해서 복사했어요 · ⌘V로 바로 붙여넣거나 위에 필기할 수 있어요", "Captured and copied · paste with ⌘V or write on it"))
  }
  /// Hands a finished stroke that began on a pinned image over to that image.
  func adoptStroke(_ stroke: InkStroke, from screen: NSScreen) -> Bool {
    guard let start = stroke.points.first else { return false }
    let p = CGPoint(x: screen.frame.minX + start.x, y: screen.frame.minY + start.y)
    guard let window = stickers.last(where: { $0.isVisible && $0.frame.contains(p) }),
      let view = window.contentView as? StickerView
    else { return false }
    let dx = screen.frame.minX - window.frame.minX
    let dy = screen.frame.minY - window.frame.minY
    view.addStroke(
      InkStroke(
        points: stroke.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }, color: stroke.color,
        width: stroke.width, created: stroke.created, expires: false))
    if case .display = undoHistory.last { undoHistory[undoHistory.count - 1] = .sticker(view) }
    clip(view)
    return true
  }
  func pasteSticker() {
    guard let image = NSImage(pasteboard: NSPasteboard.general) else {
      showMessage(tr("붙일 이미지가 없어요", "No image to paste"), tr("먼저 영역을 캡처하거나 이미지를 복사해 주세요.", "Capture an area or copy an image first."))
      return
    }
    addSticker(image)
  }
  func addSticker(_ image: NSImage, at frame: CGRect? = nil) {
    // The display under the pointer, so pasting works on any monitor.
    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        ?? toolbar.screen ?? NSScreen.main
    else { return }
    let visible = screen.visibleFrame
    let size =
      frame?.size
      ?? stickerSize(
        image.size, limit: CGSize(width: visible.width * 0.7, height: visible.height * 0.7))
    // Below the ink overlays, so the pen can write over a pasted image. It takes typing for notes.
    let window = panel(size: size, level: .statusBar, typing: true)
    window.hasShadow = true
    window.isMovableByWindowBackground = true
    let view = StickerView(image: image, size: size) { [weak self, weak window] in
      if let window { self?.removeSticker(window) }
    }
    view.controller = self
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem(tr("글자 넣기", "Add text")) { [weak self, weak view] in
      if let self, let view { view.beginNote(color: self.inkColor) }
    })
    menu.addItem(ClosureMenuItem(tr("복사하기", "Copy")) { [weak self, weak view] in
      if let view { self?.copySticker(view) }
    })
    menu.addItem(ClosureMenuItem(tr("복사해서 바로 붙여넣기", "Copy and paste into the app")) {
      [weak self, weak view] in
      if let view { self?.pasteInto(view) }
    })
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem(tr("저장", "Save")) { [weak self, weak view] in
      if let view { self?.saveCapture(from: view) }
    })
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem(tr("닫기", "Close")) { [weak self, weak window] in
      if let window { self?.removeSticker(window) }
    })
    view.menu = menu
    window.contentView = view
    let offset = CGFloat(stickers.count % 6) * 28
    window.setFrameOrigin(
      frame?.origin
        ?? CGPoint(
          x: visible.midX - size.width / 2 + offset, y: visible.midY - size.height / 2 - offset))
    window.orderFrontRegardless()
    attachBar(to: view, in: window)
    stickers.append(window)
  }
  func removeSticker(_ window: QuietPanel) {
    if let view = window.contentView as? StickerView {
      view.bar?.orderOut(nil)
      view.bar?.close()
      view.bar = nil
      if let observer = view.barObserver { NotificationCenter.default.removeObserver(observer) }
      view.barObserver = nil
    }
    window.orderOut(nil)
    stickers.removeAll { $0 === window }
    window.contentView = nil
    window.close()
  }
  /// 복사됨 · 저장 · 글자 · 붙여넣기 · 닫기, in a panel above the pen layer so they work while drawing.
  func attachBar(to view: StickerView, in window: QuietPanel) {
    let items: [(String, String, String, (AppController, StickerView, QuietPanel) -> Void)] = [
      (tr("복사됨", "Copied"), "checkmark", tr("이미 클립보드에 있어요. 누르면 다시 복사해요.", "Already on the clipboard. Click to copy again."), { c, v, _ in c.copySticker(v) }),
      (tr("저장", "Save"), "square.and.arrow.down", tr("PNG로 저장", "Save as PNG"), { c, v, _ in c.saveCapture(from: v) }),
      (tr("글자", "Text"), "textformat", tr("그림 위에 글자 쓰기", "Type on the image"), { c, v, _ in
        v.menuPoint = CGPoint(x: 12, y: v.bounds.midY)
        v.beginNote(color: c.inkColor)
      }),
      (tr("붙여넣기", "Paste"), "doc.on.clipboard", tr("앞에 있는 앱에 바로 붙여넣기", "Paste into the app in front"), { c, v, _ in c.pasteInto(v) }),
      (tr("닫기", "Close"), "xmark", tr("이 그림 닫기", "Close this image"), { c, _, w in c.removeSticker(w) }),
    ]
    let width = CGFloat(items.count) * 82 + 8
    let bar = panel(size: CGSize(width: width, height: 44), level: toolbar.level)
    bar.hasShadow = true
    let content = NSView(frame: CGRect(x: 0, y: 0, width: width, height: 44))
    content.wantsLayer = true
    content.layer?.backgroundColor = Look.dock.cgColor
    content.layer?.cornerRadius = 12
    for (i, (title, symbol, tip, action)) in items.enumerated() {
      let b = ToolButton(frame: CGRect(x: 4 + CGFloat(i) * 82, y: 2, width: 82, height: 40), title: title, symbol: symbol) {
        [weak self, weak view, weak window] in
        if let self, let view, let window { action(self, view, window) }
      }
      b.toolTip = tip
      b.selected = i == 0
      content.addSubview(b)
    }
    bar.contentView = content
    view.bar = bar
    view.barObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification, object: window, queue: .main
    ) { [weak self, weak window] _ in
      if let self, let window { self.placeBar(of: window) }
    }
    placeBar(of: window)
    bar.orderFrontRegardless()
  }
  /// Under the image, or above it when there is no room below; kept on screen.
  func placeBar(of window: NSWindow) {
    guard let view = window.contentView as? StickerView, let bar = view.bar else { return }
    let frame = window.frame
    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
    var origin = CGPoint(x: frame.minX, y: frame.minY - bar.frame.height - 6)
    if origin.y < visible.minY { origin.y = min(frame.maxY + 6, visible.maxY - bar.frame.height) }
    origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - bar.frame.width - 4)
    bar.setFrameOrigin(origin)
  }
  enum StickerHandle { case close, move }
  /// The ✕ and the grip still work while the pen layer lies over a pinned image.
  func stickerHandle(at p: CGPoint) -> (QuietPanel, StickerHandle)? {
    guard let window = stickers.last(where: { $0.isVisible && $0.frame.contains(p) }),
      let view = window.contentView as? StickerView
    else { return nil }
    let local = CGPoint(x: p.x - window.frame.minX, y: p.y - window.frame.minY)
    if view.closeFrame.insetBy(dx: -4, dy: -4).contains(local) { return (window, .close) }
    if view.gripFrame.insetBy(dx: -4, dy: -4).contains(local) { return (window, .move) }
    return nil
  }
  func sticker(at p: CGPoint) -> StickerView? {
    stickers.last(where: { $0.isVisible && $0.frame.contains(p) })?.contentView as? StickerView
  }
  func noteAdded(_ view: StickerView) {
    undoHistory.append(.sticker(view))
    clip(view)
    refreshTools()
  }
  /// Keeps the clipboard on the image with its ink, so ⌘V always pastes what is on screen.
  func clip(_ view: StickerView) {
    guard let merged = view.composite() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([NSImage(cgImage: merged, size: view.bounds.size)])
  }
  /// The image with its ink. The pen goes off so the next click reaches the app to paste into.
  @discardableResult func copySticker(_ view: StickerView, announce: Bool = true) -> Bool {
    guard let merged = view.composite() else { return false }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([NSImage(cgImage: merged, size: view.bounds.size)])
    if pen { toggle("pen") }
    if announce {
      toast(tr("복사했어요 · 붙여넣을 곳을 클릭하고 ⌘V", "Copied · click where it goes, then ⌘V"))
    }
    return true
  }
  /// Copies, then presses ⌘V in the app in front. YelPoint's panels never take focus,
  /// so that is still the lesson app. Sending keys needs Accessibility permission.
  func pasteInto(_ view: StickerView) {
    guard copySticker(view, announce: false) else { return }
    guard AXIsProcessTrusted() else {
      _ = AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
      showMessage(
        tr("바로 붙여넣기 권한", "Paste permission"),
        tr(
          "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 YelPoint를 허용하면 바로 붙여넣기가 돼요. 지금은 복사만 했으니 붙여넣을 곳을 클릭하고 ⌘V를 눌러 주세요.",
          "Allow YelPoint in System Settings → Privacy & Security → Accessibility to paste directly. For now it is copied: click where it goes and press ⌘V."))
      return
    }
    if NSApp.isActive { NSApp.deactivate() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      let source = CGEventSource(stateID: .hidSystemState)
      for down in [true, false] {
        let key = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
        key?.flags = .maskCommand
        key?.post(tap: .cghidEventTap)
      }
      self?.toast(tr("붙여넣었어요", "Pasted"))
    }
  }
  @discardableResult func saveCapture(from view: StickerView? = nil) -> URL? {
    var source =
      (view ?? stickers.last?.contentView as? StickerView)?.composite() ?? lastCapture
    if source == nil, let image = NSImage(pasteboard: NSPasteboard.general) {
      source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    guard let source else {
      showMessage(tr("저장할 캡처가 없어요", "No capture to save"), tr("먼저 영역을 캡처해 주세요.", "Capture an area first."))
      return nil
    }
    do {
      guard
        let png = NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:])
      else { throw NSError(domain: "YelPoint", code: 8, userInfo: [NSLocalizedDescriptionKey: tr("캡처를 PNG로 바꾸지 못했어요.", "Could not turn the capture into a PNG.")]) }
      try FileManager.default.createDirectory(at: capturesFolder, withIntermediateDirectories: true)
      let url = capturesFolder.appendingPathComponent(mediaFileName(extension: "png", date: Date()))
      try png.write(to: url, options: .atomic)
      toast(tr("저장했어요 · ", "Saved · ") + storage.capturesLabel)
      return url
    } catch {
      showMessage(tr("저장하지 못했어요", "Could not save"), tr("저장 공간이 남아 있는지 확인해 주세요.\n", "Check the drive connection and free space.\n") + error.localizedDescription)
      return nil
    }
  }
  func toggleRecording() {
    if recorder != nil {
      stopRecording()
      return
    }
    guard !toolsSuspended, ensureScreenAccess(), let screen = toolbar.screen ?? NSScreen.main else {
      return
    }
    do {
      try FileManager.default.createDirectory(at: capturesFolder, withIntermediateDirectories: true)
    } catch {
      showMessage(tr("녹화를 시작하지 못했어요", "Could not start recording"), tr("저장 공간이 남아 있는지 확인해 주세요.\n", "Check the drive connection and free space.\n") + error.localizedDescription)
      return
    }
    let url = capturesFolder.appendingPathComponent(mediaFileName(extension: "mp4", date: Date()))
    let active = ScreenRecorder()
    recorder = active
    recordingLive = false
    refreshTools()
    let ids = controlWindowIDs
    Task { @MainActor [weak self] in
      let allowed = await AVCaptureDevice.requestAccess(for: .audio)
      guard let controller = self, controller.recorder === active else { return }
      if !allowed {
        controller.showMessage(
          tr("마이크 권한이 없어요", "No microphone permission"),
          tr("이번 녹화는 소리 없이 진행할게요. 소리를 넣으려면 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 YelPoint를 허용해 주세요.", "This recording will have no sound. To add sound, allow YelPoint in System Settings → Privacy & Security → Microphone."))
      }
      do {
        let hasSound = try await active.start(
          screen: screen, excluding: ids, url: url, useMicrophone: allowed
        ) { message in
          guard let self else { return }
          self.stopRecording()
          self.showMessage(tr("녹화가 중지됐어요", "Recording stopped"), message)
        }
        // Stop was pressed while it was still starting: end it quietly and drop the stub file.
        guard let self, self.recorder === active else {
          active.stop { result in
            if case .success(let stub) = result { try? FileManager.default.removeItem(at: stub) }
          }
          return
        }
        self.recordingLive = true
        // With a projector or second monitor, say which one is being recorded.
        let which = NSScreen.screens.count > 1 ? tr(" · \(screen.localizedName) 화면", " · \(screen.localizedName)") : ""
        self.toast((hasSound ? tr("녹화 시작 · 마이크 켜짐", "Recording · Mic on") : tr("녹화 시작 · 소리 없음", "Recording · No sound")) + which)
      } catch {
        guard let self, self.recorder === active else { return }
        self.recorder = nil
        self.refreshTools()
        self.showMessage(tr("녹화를 시작하지 못했어요", "Could not start recording"), error.localizedDescription)
      }
    }
  }
  func stopRecording() {
    guard let active = recorder else { return }
    recorder = nil
    refreshTools()
    // Not capturing yet: the start finishes on its own, sees it was cancelled and cleans up.
    guard recordingLive else {
      toast(tr("녹화를 취소했어요", "Recording cancelled"))
      return
    }
    recordingLive = false
    active.stop { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .success(let url):
          self.toast(tr("녹화를 저장했어요 · ", "Recording saved · ") + self.storage.capturesLabel)
          self.offerSubtitles(for: url)
        case .failure(let error): self.showMessage(tr("녹화를 저장하지 못했어요", "Could not save the recording"), error.localizedDescription)
        }
      }
    }
  }
  func finishRecordingBeforeQuit() {
    guard let active = recorder, recordingLive else { return }
    recorder = nil
    let done = DispatchSemaphore(value: 0)
    active.stop { _ in done.signal() }
    _ = done.wait(timeout: .now() + 5)
  }
}
