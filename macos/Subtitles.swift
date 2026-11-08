import AVFoundation
import AVKit
import AppKit
import Speech

/// Nanum Gothic Bold (SIL OFL 1.1), bundled with the app, for subtitles burned into videos.
func subtitleFont(_ size: CGFloat) -> NSFont {
  if NSFont(name: "NanumGothicBold", size: size) == nil,
    let url = Bundle.main.url(forResource: "NanumGothic-Bold", withExtension: "ttf")
  {
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }
  return NSFont(name: "NanumGothicBold", size: size) ?? .boldSystemFont(ofSize: size)
}

/// White bold text on a dark rounded box, like subtitles on video sites.
/// `size` is the letter height as a share of the video's width (see `SubtitleStyle`).
func subtitleImage(_ text: String, videoWidth: CGFloat, size: Double) -> CGImage? {
  let fontSize = max(14, videoWidth * CGFloat(size))
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  style.lineBreakMode = .byWordWrapping
  let attributes: [NSAttributedString.Key: Any] = [.font: subtitleFont(fontSize), .foregroundColor: NSColor.white, .paragraphStyle: style]
  let string = NSAttributedString(string: text, attributes: attributes)
  let maxWidth = videoWidth * 0.86
  let bounds = string.boundingRect(with: CGSize(width: maxWidth, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
  let pad = fontSize * 0.45
  let width = Int(ceil(bounds.width + pad * 2)), height = Int(ceil(bounds.height + pad * 1.4))
  guard width > 0, height > 0,
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else { return nil }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor.black.withAlphaComponent(0.68).setFill()
  NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), xRadius: fontSize * 0.35, yRadius: fontSize * 0.35).fill()
  string.draw(with: CGRect(x: pad, y: pad * 0.7, width: bounds.width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
  NSGraphicsContext.restoreGraphicsState()
  return rep.cgImage
}

enum SubtitleError: LocalizedError {
  case noVideo, export(String), speech(String)
  var errorDescription: String? {
    switch self {
    case .noVideo: return tr("영상 트랙을 찾지 못했어요.", "No video track found.")
    case .export(let s), .speech(let s): return s
    }
  }
}

enum SubtitleWork {
  /// Burns `cues` into a copy of `source`. Sound is kept as it is.
  static func burn(_ cues: [Cue], into source: URL, output: URL, style: SubtitleStyle) async throws {
    let asset = AVURLAsset(url: source)
    guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw SubtitleError.noVideo }
    let duration = try await asset.load(.duration)
    let natural = try await video.load(.naturalSize)
    let composition = AVMutableComposition()
    let range = CMTimeRange(start: .zero, duration: duration)
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    try videoTrack?.insertTimeRange(range, of: video, at: .zero)
    for audio in try await asset.loadTracks(withMediaType: .audio) {
      let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      try track?.insertTimeRange(range, of: audio, at: .zero)
    }
    // Each subtitle is drawn once, then laid over the frames it belongs to. Core Image's origin is the bottom left.
    let overlays: [(cue: Cue, image: CIImage)] = cues.compactMap { cue in
      guard cue.end > cue.start, !cue.text.isEmpty, let image = subtitleImage(cue.text, videoWidth: natural.width, size: style.size) else { return nil }
      let box = style.frame(box: CGSize(width: image.width, height: image.height), in: natural)
      return (cue, CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: box.minX.rounded(), y: box.minY.rounded())))
    }
    let videoComposition = try await AVMutableVideoComposition.videoComposition(with: composition) { request in
      let t = request.compositionTime.seconds
      if let overlay = overlays.first(where: { t >= $0.cue.start && t < $0.cue.end }) {
        request.finish(with: overlay.image.composited(over: request.sourceImage).cropped(to: request.sourceImage.extent), context: nil)
      } else {
        request.finish(with: request.sourceImage, context: nil)
      }
    }
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      throw SubtitleError.export(tr("영상을 만들 수 없어요.", "Could not create the video."))
    }
    try? FileManager.default.removeItem(at: output)
    export.outputURL = output
    export.outputFileType = .mp4
    export.videoComposition = videoComposition
    await export.export()
    if export.status != .completed {
      throw SubtitleError.export(export.error?.localizedDescription ?? tr("영상 저장에 실패했어요.", "Saving the video failed."))
    }
  }

  /// Turns the recording's speech into draft subtitles with Apple's on-device recognizer when it can.
  static func transcribe(_ source: URL, temp: URL, english: Bool, progress: @escaping (String) -> Void) async throws -> [Cue] {
    let status = await withCheckedContinuation { done in SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) } }
    guard status == .authorized else {
      throw SubtitleError.speech(tr(
        "음성 인식 권한이 없어요. 시스템 설정 → 개인정보 보호 및 보안 → 음성 인식에서 YelPoint를 켜 주세요.",
        "Speech recognition is not allowed. Turn on YelPoint in System Settings → Privacy & Security → Speech Recognition."))
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: english ? "en-US" : "ko-KR")), recognizer.isAvailable else {
      throw SubtitleError.speech(tr("지금은 음성 인식을 쓸 수 없어요.", "Speech recognition is not available right now."))
    }
    let asset = AVURLAsset(url: source)
    guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
      throw SubtitleError.speech(tr("이 영상에는 소리가 없어요.", "This video has no sound."))
    }
    let total = try await asset.load(.duration).seconds
    var words: [(text: String, start: Double, duration: Double)] = []
    var start = 0.0
    // Short pieces, so long lessons work with either recognizer.
    while start < total {
      let length = min(50, total - start)
      progress(tr("말소리를 받아쓰는 중… \(Int(start / total * 100))%", "Transcribing… \(Int(start / total * 100))%"))
      let piece = temp.appendingPathComponent("subtitle-audio-\(Int(start)).m4a")
      try? FileManager.default.removeItem(at: piece)
      guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { break }
      export.outputURL = piece
      export.outputFileType = .m4a
      export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600))
      await export.export()
      if export.status == .completed {
        let request = SFSpeechURLRecognitionRequest(url: piece)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        let offset = start
        let found: [(String, Double, Double)] = await withCheckedContinuation { done in
          var finished = false
          recognizer.recognitionTask(with: request) { result, error in
            guard !finished else { return }
            if let result, result.isFinal {
              finished = true
              done.resume(returning: result.bestTranscription.segments.map { ($0.substring, $0.timestamp + offset, $0.duration) })
            } else if error != nil {
              finished = true
              done.resume(returning: [])
            }
          }
        }
        words += found.map { (text: $0.0, start: $0.1, duration: $0.2) }
      }
      try? FileManager.default.removeItem(at: piece)
      start += length
    }
    return cuesFromWords(words)
  }
}

/// Edit the subtitles of one video: preview, list, draft from speech, then save.
final class SubtitleEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate {
  weak var controller: AppController?
  let url: URL
  private(set) var cues: [Cue] = []
  let window: NSWindow
  let player: AVPlayer
  private let table = NSTableView()
  /// The subtitle drawn on the video exactly as it will be burned in.
  let preview = NSImageView()
  private var previewKey = ""
  private(set) weak var videoView: AVPlayerView?
  /// Type here while the video plays: it pauses on the first key and Enter drops the line at that moment.
  let entry = NSTextField()
  private var typingFrom: Double?
  private var editingRow: Int?
  private let playButton = NSButton(title: "", target: nil, action: nil)
  /// The video's own size, known before the player is ready.
  var videoSize = CGSize.zero
  let status = NSTextField(labelWithString: "")
  /// Where the subtitle sits and how big it is; dragged on the video, remembered for next time.
  private(set) var style = SubtitleStyle()
  let stage = SubtitleStage()
  private let timeline = NSSlider()
  private let clockLabel = NSTextField(labelWithString: "")
  private var observer: Any?
  var sidecar: URL { url.deletingPathExtension().appendingPathExtension("subtitles.json") }

  init(url: URL, controller: AppController) {
    self.url = url
    self.controller = controller
    style = controller.preferences.subtitleStyle ?? SubtitleStyle()
    player = AVPlayer(url: url)
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 980, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    super.init()
    window.title = tr("자막 넣기 · ", "Subtitles · ") + url.lastPathComponent
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.minSize = CGSize(width: 900, height: 620)
    if let data = try? Data(contentsOf: sidecar), let saved = try? JSONDecoder().decode([Cue].self, from: data) {
      // Older versions added a placeholder line; it is never a real subtitle.
      cues = saved.filter { $0.text != "자막을 입력하세요" && $0.text != "Type the subtitle" }
    }
    build()
    Task { @MainActor [weak self] in
      guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
        let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform)
      else { return }
      let shown = size.applying(transform)
      self?.videoSize = CGSize(width: abs(shown.width), height: abs(shown.height))
      self?.updatePreview()
    }
    observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
      self?.updatePreview()
      self?.refreshPlay()
      self?.refreshTimeline()
    }
  }
  deinit { if let observer { player.removeTimeObserver(observer) } }

  private func build() {
    guard let content = window.contentView else { return }
    let video = AVPlayerView(frame: CGRect(x: 0, y: 330, width: 980, height: 356))
    video.autoresizingMask = [.width, .height]
    video.player = player
    // Our own big buttons and time bar instead, so the whole picture is free for dragging the subtitle.
    video.controlsStyle = .none
    content.addSubview(video)
    videoView = video
    stage.frame = video.frame
    stage.autoresizingMask = [.width, .height]
    stage.editor = self
    content.addSubview(stage, positioned: .above, relativeTo: video)
    preview.imageScaling = .scaleAxesIndependently
    preview.isHidden = true
    stage.addSubview(preview)
    timeline.frame = CGRect(x: 12, y: 300, width: 860, height: 24)
    timeline.autoresizingMask = [.width, .maxYMargin]
    timeline.minValue = 0
    timeline.maxValue = 1
    timeline.isContinuous = true
    timeline.target = self
    timeline.action = #selector(scrub)
    timeline.setAccessibilityLabel(tr("영상 위치", "Position in the video"))
    content.addSubview(timeline)
    clockLabel.frame = CGRect(x: 878, y: 302, width: 90, height: 20)
    clockLabel.autoresizingMask = [.minXMargin, .maxYMargin]
    clockLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    clockLabel.alignment = .right
    content.addSubview(clockLabel)

    entry.autoresizingMask = [.width, .maxYMargin]
    entry.font = subtitleFont(20)
    entry.placeholderString = tr("영상을 보다가 여기에 자막을 쓰고 Enter · 쓰기 시작하면 영상이 잠깐 멈춰요", "Type the subtitle here while it plays, then Enter · the video pauses as you type")
    entry.bezelStyle = .roundedBezel
    entry.focusRingType = .default
    entry.delegate = self
    entry.target = self
    entry.action = #selector(commitEntry)
    entry.setAccessibilityLabel(tr("자막 입력", "Subtitle"))
    content.addSubview(entry)

    // ① ② ③ across the top, so the order is obvious without reading anything else.
    let steps = NSTextField(labelWithString: tr("① ▶ 눌러 영상 보기   ② 말이 나오면 아래 칸에 쓰고 Enter   ③ 다 되면 ‘자막 넣은 영상 저장’", "① Press ▶ to watch   ② Type what is said below and press Enter   ③ When done, Save video"))
    steps.font = .systemFont(ofSize: 15, weight: .semibold)
    steps.alignment = .center
    steps.frame = CGRect(x: 12, y: 690, width: 956, height: 24)
    steps.autoresizingMask = [.width, .minYMargin]
    content.addSubview(steps)

    playButton.target = self
    playButton.action = #selector(togglePlay)
    playButton.bezelStyle = .rounded
    playButton.controlSize = .large
    playButton.font = .systemFont(ofSize: 15, weight: .semibold)
    playButton.frame = CGRect(x: 12, y: 250, width: 96, height: 40)
    playButton.autoresizingMask = [.maxXMargin, .maxYMargin]
    content.addSubview(playButton)
    let back = NSButton(title: tr("↺ 3초 뒤로", "↺ Back 3 s"), target: self, action: #selector(backThree))
    back.bezelStyle = .rounded
    back.controlSize = .large
    back.frame = CGRect(x: 112, y: 250, width: 104, height: 40)
    back.autoresizingMask = [.maxXMargin, .maxYMargin]
    content.addSubview(back)
    entry.frame = CGRect(x: 224, y: 250, width: 744, height: 40)

    let speech = NSButton(title: tr("🎙 말소리로 자동 만들기", "🎙 Draft from speech"), target: self, action: #selector(transcribe))
    speech.bezelStyle = .rounded
    speech.sizeToFit()
    speech.frame = CGRect(x: 12, y: 204, width: speech.frame.width + 12, height: 32)
    speech.autoresizingMask = [.maxXMargin, .maxYMargin]
    content.addSubview(speech)
    // Everything a child never needs sits under one menu.
    let more = NSPopUpButton(frame: CGRect(x: speech.frame.maxX + 8, y: 206, width: 110, height: 28), pullsDown: true)
    more.autoresizingMask = [.maxXMargin, .maxYMargin]
    more.addItem(withTitle: tr("더보기", "More"))
    let menu = more.menu!
    menu.addItem(ClosureMenuItem(tr("자막 크기·위치 처음대로", "Reset subtitle size and place")) { [weak self] in
      self?.style = SubtitleStyle()
      self?.styleChanged()
    })
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem(tr("SRT 자막 파일로 저장", "Save as an SRT file")) { [weak self] in self?.saveSRT() })
    menu.addItem(ClosureMenuItem(tr("고른 줄 지우기", "Delete the chosen line")) { [weak self] in self?.removeSelected() })
    content.addSubview(more)
    let save = NSButton(title: tr("자막 넣은 영상 저장", "Save video with subtitles"), target: self, action: #selector(saveVideo))
    save.bezelStyle = .rounded
    save.controlSize = .large
    save.bezelColor = .controlAccentColor
    save.font = .systemFont(ofSize: 15, weight: .semibold)
    save.sizeToFit()
    save.frame = CGRect(x: 980 - save.frame.width - 28, y: 200, width: save.frame.width + 16, height: 40)
    save.autoresizingMask = [.minXMargin, .maxYMargin]
    content.addSubview(save)

    status.frame = CGRect(x: 14, y: 176, width: 950, height: 20)
    status.autoresizingMask = [.width, .maxYMargin]
    status.textColor = .secondaryLabelColor
    status.stringValue = tr("말이 나오면 쓰기 시작하세요. 영상이 알아서 멈추고, Enter를 누르면 그 장면에 들어가요.", "Start typing when someone speaks. The video pauses by itself, and Enter puts the line there.")
    content.addSubview(status)
    let listLabel = NSTextField(labelWithString: tr("넣은 자막 · 줄을 누르면 그 장면으로 가서 위 칸에서 고칠 수 있어요", "Your subtitles · click a line to jump there and fix it above"))
    listLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    listLabel.frame = CGRect(x: 14, y: 152, width: 950, height: 18)
    listLabel.autoresizingMask = [.width, .maxYMargin]
    content.addSubview(listLabel)

    for (id, title, width) in [("start", tr("시작", "Start"), 80.0), ("end", tr("끝", "End"), 80.0), ("text", tr("자막", "Subtitle"), 760.0)] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
      column.title = title
      column.width = width
      column.isEditable = true
      table.addTableColumn(column)
    }
    table.dataSource = self
    table.delegate = self
    table.usesAlternatingRowBackgroundColors = true
    let scroll = NSScrollView(frame: CGRect(x: 12, y: 12, width: 956, height: 136))
    scroll.autoresizingMask = [.width, .maxYMargin]
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    content.addSubview(scroll)
  }

  func show() {
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(entry)
    refreshPlay()
  }
  func windowDidResize(_ notification: Notification) { updatePreview() }

  // ---- Preview: the same picture the burn uses, scaled onto the shown video ----
  /// Remembered for the next video too.
  func styleChanged() {
    controller?.preferences.subtitleStyle = style
    controller?.preferencesChanged()
    previewKey = ""
    updatePreview()
  }
  /// `center` is in the stage's coordinates.
  func moveSubtitle(center: CGPoint) {
    let area = stage.videoRect
    guard area.width > 0 else { return }
    style = style.centred(at: CGPoint(x: center.x - area.minX, y: center.y - area.minY), box: preview.frame.size, in: area.size)
    updatePreview()
  }
  func resizeSubtitle(_ size: Double) {
    style.size = min(max(size, SubtitleStyle.sizes.lowerBound), SubtitleStyle.sizes.upperBound)
    previewKey = ""
    updatePreview()
  }
  @objc private func scrub() {
    player.seek(to: CMTime(seconds: timeline.doubleValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
  }
  private func refreshTimeline() {
    let total = player.currentItem?.duration.seconds ?? 0
    let now = max(0, player.currentTime().seconds)
    if total.isFinite, total > 0 {
      timeline.maxValue = total
      if !(NSEvent.pressedMouseButtons & 1 == 1 && window.firstResponder === timeline) { timeline.doubleValue = now }
      clockLabel.stringValue = clock(now).components(separatedBy: ".").first! + " / " + clock(total).components(separatedBy: ".").first!
    }
  }
  @objc func togglePlay() {
    if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    refreshPlay()
  }
  @objc func backThree() {
    let t = max(0, player.currentTime().seconds - 3)
    player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
  }
  func refreshPlay() {
    let playing = player.timeControlStatus == .playing || player.rate > 0
    playButton.title = playing ? tr("⏸ 멈춤", "⏸ Pause") : tr("▶ 재생", "▶ Play")
  }
  func updatePreview() {
    guard let video = videoView, let overlay = video.contentOverlayView else { return }
    let typed = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = typingFrom != nil || editingRow != nil ? typed : (cue(at: player.currentTime().seconds, in: cues)?.text ?? "")
    let presented = player.currentItem?.presentationSize ?? .zero
    let natural = presented.width > 0 ? presented : videoSize
    _ = overlay
    // Paused with nothing to show: a faint sample, so the place and size can still be set.
    let paused = player.timeControlStatus != .playing
    let sample = text.isEmpty && paused
    let shown = sample ? tr("여기에 자막이 나와요", "Subtitles appear here") : text
    guard !shown.isEmpty, natural.width > 0, natural.height > 0 else {
      preview.isHidden = true
      stage.needsDisplay = true
      return
    }
    let key = "\(shown)|\(style.size)|\(natural.width)"
    if key != previewKey {
      previewKey = key
      preview.image = subtitleImage(shown, videoWidth: natural.width, size: style.size).map {
        NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height))
      }
    }
    guard let image = preview.image else {
      preview.isHidden = true
      return
    }
    // Where the picture sits in the player, letterboxed like the player draws it.
    let rect = AVMakeRect(aspectRatio: natural, insideRect: stage.bounds)
    stage.videoRect = rect
    let scale = rect.width / natural.width
    let box = style.frame(box: CGSize(width: image.size.width * scale, height: image.size.height * scale), in: rect.size)
    preview.frame = box.offsetBy(dx: rect.minX, dy: rect.minY)
    preview.alphaValue = sample ? 0.55 : 1
    preview.isHidden = false
    stage.needsDisplay = true
    window.invalidateCursorRects(for: stage)
  }

  // ---- Typing straight onto the video ----
  func controlTextDidChange(_ obj: Notification) {
    guard (obj.object as? NSTextField) === entry else { return }
    if typingFrom == nil, editingRow == nil {
      // People type after they hear it, so the line starts a moment earlier, never before the previous line ends.
      let now = max(0, player.currentTime().seconds)
      let previousEnd = cues.filter { $0.start < now }.map(\.end).max() ?? 0
      typingFrom = max(previousEnd, now - 1)
      player.pause()
    }
    updatePreview()
  }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === entry, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
    entry.stringValue = ""
    typingFrom = nil
    editingRow = nil
    table.deselectAll(nil)
    updatePreview()
    return true
  }
  @objc func commitEntry() {
    let text = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if let row = editingRow, row < cues.count {
      if text.isEmpty { cues.remove(at: row) } else { cues[row].text = text }
      editingRow = nil
      entry.stringValue = ""
      table.deselectAll(nil)
      changed()
      status.stringValue = text.isEmpty ? tr("자막을 지웠어요.", "Subtitle deleted.") : tr("자막을 고쳤어요.", "Subtitle updated.")
      updatePreview()
      return
    }
    guard !text.isEmpty else { return }
    let start = typingFrom ?? max(0, player.currentTime().seconds)
    // Long enough to read, and never running into the next line.
    var end = start + max(2, min(7, Double(text.count) * 0.22))
    if let next = cues.map(\.start).filter({ $0 > start + 0.05 }).min() { end = min(end, next) }
    end = max(end, start + 0.5)
    cues.append(Cue(start: start, end: end, text: text))
    typingFrom = nil
    entry.stringValue = ""
    changed()
    status.stringValue = tr("\(clock(start))에 넣었어요. 계속 보면서 다음 자막을 쓰세요.", "Added at \(clock(start)). Keep watching and type the next one.")
    player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      self?.player.play()
    }
    window.makeFirstResponder(entry)
    updatePreview()
  }
  func windowWillClose(_ notification: Notification) {
    player.pause()
    controller?.subtitleEditor = nil
    controller?.giveFocusBack()
  }

  // ---- Table ----
  func numberOfRows(in tableView: NSTableView) -> Int { cues.count }
  func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
    let c = cues[row]
    switch column?.identifier.rawValue {
    case "start": return clock(c.start)
    case "end": return clock(c.end)
    default: return c.text
    }
  }
  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for column: NSTableColumn?, row: Int) {
    guard row < cues.count, let value = object as? String else { return }
    switch column?.identifier.rawValue {
    case "start": if let t = seconds(value) { cues[row].start = t }
    case "end": if let t = seconds(value) { cues[row].end = t }
    default: cues[row].text = value
    }
    changed()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard table.selectedRow >= 0, table.selectedRow < cues.count else { return }
    let row = table.selectedRow
    player.pause()
    player.seek(to: CMTime(seconds: cues[row].start + 0.01, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      self?.updatePreview()
    }
    // The line goes into the box above to fix; Enter saves it, an empty box deletes it, Esc leaves it.
    typingFrom = nil
    editingRow = row
    entry.stringValue = cues[row].text
    window.makeFirstResponder(entry)
    status.stringValue = tr("위 칸에서 고치고 Enter. 지우려면 칸을 비우고 Enter, 그대로 두려면 Esc.", "Fix it above and press Enter. Empty it and press Enter to delete, or Esc to leave it.")
  }
  private func clock(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }
  private func seconds(_ s: String) -> Double? {
    let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    if parts.count == 2, let m = parts[0], let sec = parts[1] { return m * 60 + sec }
    if parts.count == 1, let sec = parts[0] { return sec }
    return nil
  }
  func setCues(_ next: [Cue]) {
    cues = next.sorted { $0.start < $1.start }
    changed()
  }
  private func changed() {
    cues.sort { $0.start < $1.start }
    previewKey = ""
    table.reloadData()
    if let data = try? JSONEncoder().encode(cues) { try? data.write(to: sidecar) }
  }

  // ---- Actions ----
  @objc func addHere() {
    player.pause()
    editingRow = nil
    table.deselectAll(nil)
    typingFrom = max(0, player.currentTime().seconds)
    window.makeFirstResponder(entry)
    status.stringValue = tr("이 장면에 넣을 자막을 위 칸에 쓰고 Enter를 눌러 주세요.", "Type the subtitle for this moment above and press Enter.")
  }
  @objc func removeSelected() {
    let rows = table.selectedRowIndexes
    guard !rows.isEmpty else { return }
    cues = cues.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
    changed()
  }
  @objc func transcribe() {
    guard let controller else { return }
    if !cues.isEmpty {
      let alert = NSAlert()
      alert.messageText = tr("지금 자막을 말소리 받아쓰기로 바꿀까요?", "Replace these subtitles with a speech draft?")
      alert.addButton(withTitle: tr("바꾸기", "Replace"))
      alert.addButton(withTitle: tr("취소", "Cancel"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    let temp = controller.storage.root.appendingPathComponent("tmp", isDirectory: true)
    Task { @MainActor in
      do {
        let draft = try await SubtitleWork.transcribe(url, temp: temp, english: appEnglish) { [weak self] text in
          Task { @MainActor in self?.status.stringValue = text }
        }
        setCues(draft)
        status.stringValue = draft.isEmpty
          ? tr("알아들은 말이 없어요. 직접 넣어 주세요.", "No speech was recognised. Add subtitles by hand.")
          : tr("자막 \(draft.count)줄을 만들었어요. 틀린 글자를 고친 다음 저장해 주세요.", "Made \(draft.count) lines. Fix any mistakes, then save.")
      } catch {
        status.stringValue = error.localizedDescription
      }
    }
  }
  @objc func saveSRT() {
    window.makeFirstResponder(nil)
    let target = url.deletingPathExtension().appendingPathExtension("srt")
    do {
      try srt(cues).write(to: target, atomically: true, encoding: .utf8)
      status.stringValue = tr("SRT를 저장했어요 · ", "Saved SRT · ") + target.lastPathComponent
    } catch { status.stringValue = error.localizedDescription }
  }
  @objc func saveVideo() {
    window.makeFirstResponder(nil)
    guard !cues.isEmpty else {
      status.stringValue = tr("자막을 먼저 넣어 주세요.", "Add subtitles first.")
      return
    }
    let target = url.deletingPathExtension().appendingPathExtension("subtitled.mp4")
    status.stringValue = tr("자막 넣은 영상을 만드는 중…", "Making the video…")
    let look = style
    let current = cues
    Task { @MainActor in
      do {
        try await SubtitleWork.burn(current, into: url, output: target, style: look)
        try? srt(current).write(to: url.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8)
        status.stringValue = tr("저장했어요 · ", "Saved · ") + target.lastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([target])
      } catch {
        status.stringValue = tr("저장하지 못했어요: ", "Could not save: ") + error.localizedDescription
      }
    }
  }
}

extension AppController {
  func openSubtitles(_ url: URL) {
    subtitleEditor?.window.close()
    let editor = SubtitleEditor(url: url, controller: self)
    subtitleEditor = editor
    editor.show()
  }
  /// Pick any saved recording to add subtitles to.
  /// The 내 영상 window: every saved video, newest first, one press to watch and add subtitles.
  func chooseVideoForSubtitles() {
    guard recorder == nil else { return }
    if videoLibrary == nil { videoLibrary = VideoLibrary(controller: self) }
    videoLibrary?.show()
  }
  /// A video kept somewhere else.
  func chooseOtherVideo() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
    panel.directoryURL = capturesFolder
    panel.message = tr("자막을 넣을 영상을 골라 주세요", "Choose a video to add subtitles to")
    guard recorder == nil else { return }
    // The tool panels float above other windows; tuck them away and lift the file window above
    // everything, or it can open hidden behind them and hold the whole app.
    var chosen: URL?
    withToolsSuspended {
      takeFocus()
      panel.level = NSWindow.Level(rawValue: toolbar.level.rawValue + 2)
      if panel.runModal() == .OK { chosen = panel.url }
    }
    if let chosen { openSubtitles(chosen) } else { giveFocusBack() }
  }
  func offerSubtitles(for url: URL) {
    let alert = NSAlert()
    alert.messageText = tr("녹화를 저장했어요", "Recording saved")
    // Say where it went, or a phone or screen recording is hard to find afterwards.
    alert.informativeText =
      tr("저장 위치: ", "Saved in: ") + storage.capturesLabel + tr("\n파일 이름: ", "\nFile: ") + url.lastPathComponent
      + tr("\n\n자막을 넣을까요? 말소리로 자막 초안을 자동으로 만들 수 있어요.", "\n\nAdd subtitles? A draft can be made from the speech.")
    alert.addButton(withTitle: tr("자막 넣기", "Add subtitles"))
    alert.addButton(withTitle: tr("폴더에서 보기", "Show in Folder"))
    alert.addButton(withTitle: tr("나중에", "Later"))
    var choice = NSApplication.ModalResponse.alertThirdButtonReturn
    withToolsSuspended {
      takeFocus()
      choice = alert.runModal()
    }
    if choice == .alertFirstButtonReturn {
      openSubtitles(url)
    } else if choice == .alertSecondButtonReturn {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      giveFocusBack()
    }
  }
}

/// Lies over the video: drag the subtitle to move it, drag its corner to resize it, or click anywhere to put it there.
final class SubtitleStage: NSView {
  weak var editor: SubtitleEditor?
  var videoRect = CGRect.zero
  private enum Drag {
    case move(CGVector)
    case resize(start: Double, from: CGFloat, center: CGPoint)
  }
  private var drag: Drag?
  private var preview: NSImageView? { editor.map { $0.preview }.flatMap { $0.isHidden ? nil : $0 } }
  var handle: CGRect {
    guard let p = preview else { return .zero }
    return CGRect(x: p.frame.maxX - 10, y: p.frame.minY - 10, width: 20, height: 20)
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    return videoRect.insetBy(dx: -10, dy: -10).contains(local) ? self : nil
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let p = preview else { return }
    let outline = NSBezierPath(roundedRect: p.frame.insetBy(dx: -3, dy: -3), xRadius: 6, yRadius: 6)
    outline.setLineDash([6, 4], count: 2, phase: 0)
    outline.lineWidth = 1.5
    Look.lime.setStroke()
    outline.stroke()
    Look.lime.setFill()
    NSBezierPath(roundedRect: handle.insetBy(dx: 3, dy: 3), xRadius: 3, yRadius: 3).fill()
  }
  override func resetCursorRects() {
    guard let p = preview else { return }
    addCursorRect(p.frame, cursor: .openHand)
    addCursorRect(handle, cursor: .crosshair)
  }
  private func center(of frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
  override func mouseDown(with event: NSEvent) {
    guard let editor else { return }
    let p = convert(event.locationInWindow, from: nil)
    if let box = preview?.frame, handle.contains(p) {
      let c = center(of: box)
      drag = .resize(start: editor.style.size, from: max(1, hypot(p.x - c.x, p.y - c.y)), center: c)
    } else if let box = preview?.frame, box.contains(p) {
      let c = center(of: box)
      drag = .move(CGVector(dx: p.x - c.x, dy: p.y - c.y))
    } else {
      // A click on the picture puts the subtitle there.
      editor.moveSubtitle(center: p)
      drag = .move(.zero)
    }
  }
  override func mouseDragged(with event: NSEvent) {
    guard let editor, let drag else { return }
    let p = convert(event.locationInWindow, from: nil)
    switch drag {
    case .move(let grab):
      editor.moveSubtitle(center: CGPoint(x: p.x - grab.dx, y: p.y - grab.dy))
    case .resize(let start, let from, let c):
      editor.resizeSubtitle(start * Double(hypot(p.x - c.x, p.y - c.y) / from))
    }
  }
  override func mouseUp(with event: NSEvent) {
    guard drag != nil else { return }
    drag = nil
    editor?.styleChanged()
  }
}

/// Recordings and phone videos in big rows with a picture of each; pick one to watch and add subtitles.
final class VideoLibrary: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
  weak var controller: AppController?
  let window: NSWindow
  private let table = NSTableView()
  let status = NSTextField(labelWithString: "")
  private let openButton = NSButton()
  private(set) var videos: [URL] = []
  private var thumbnails: [URL: NSImage] = [:]
  private var details: [URL: String] = [:]

  init(controller: AppController) {
    self.controller = controller
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 660, height: 540), styleMask: [.titled, .closable, .resizable],
      backing: .buffered, defer: false)
    super.init()
    window.title = tr("내 영상", "My Videos")
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.minSize = CGSize(width: 560, height: 420)
    guard let content = window.contentView else { return }
    let heading = NSTextField(labelWithString: tr("녹화한 영상", "Your videos"))
    heading.font = .systemFont(ofSize: 18, weight: .semibold)
    heading.frame = CGRect(x: 20, y: 494, width: 620, height: 28)
    heading.autoresizingMask = [.width, .minYMargin]
    content.addSubview(heading)
    status.font = .systemFont(ofSize: 13)
    status.textColor = .secondaryLabelColor
    status.frame = CGRect(x: 20, y: 468, width: 620, height: 20)
    status.autoresizingMask = [.width, .minYMargin]
    content.addSubview(status)
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video"))
    column.width = 600
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 76
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(openSelected)
    let scroll = NSScrollView(frame: CGRect(x: 20, y: 70, width: 620, height: 390))
    scroll.autoresizingMask = [.width, .height]
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    content.addSubview(scroll)
    openButton.title = tr("보기 · 자막 넣기", "Watch · Subtitles")
    openButton.bezelStyle = .rounded
    openButton.controlSize = .large
    openButton.bezelColor = .controlAccentColor
    openButton.font = .systemFont(ofSize: 15, weight: .semibold)
    openButton.keyEquivalent = "\r"
    openButton.target = self
    openButton.action = #selector(openSelected)
    openButton.sizeToFit()
    openButton.frame = CGRect(x: 640 - openButton.frame.width - 24, y: 18, width: openButton.frame.width + 24, height: 40)
    openButton.autoresizingMask = [.minXMargin, .maxYMargin]
    content.addSubview(openButton)
    var x: CGFloat = 20
    for (title, action) in [(tr("폴더에서 보기", "Show in Folder"), #selector(revealSelected)), (tr("다른 영상 고르기…", "Other video…"), #selector(chooseOther))] {
      let b = NSButton(title: title, target: self, action: action)
      b.bezelStyle = .rounded
      b.sizeToFit()
      b.frame = CGRect(x: x, y: 20, width: b.frame.width + 16, height: 34)
      b.autoresizingMask = [.maxXMargin, .maxYMargin]
      content.addSubview(b)
      x = b.frame.maxX + 8
    }
  }
  func show() {
    reload()
    window.center()
    controller?.takeFocus()
    window.makeKeyAndOrderFront(nil)
  }
  func reload() {
    guard let folder = controller?.capturesFolder else { return }
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    videos = files.filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix("._") }
      .sorted { date($0) > date($1) }
    table.reloadData()
    if !videos.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    openButton.isEnabled = !videos.isEmpty
    status.stringValue = videos.isEmpty
      ? tr("아직 녹화한 영상이 없어요. 캡처 메뉴의 ‘화면 녹화’나 폰 패널의 ‘녹화’·‘영상 가져오기’로 만들 수 있어요.", "No videos yet. Use Record in the capture menu, or Record or Get Videos in the phone panel.")
      : tr("영상을 고르고 ‘보기 · 자막 넣기’를 누르세요. 맨 위가 가장 최근 영상이에요.", "Pick a video, then press Watch · Subtitles. The newest is at the top.")
  }
  func numberOfRows(in tableView: NSTableView) -> Int { videos.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let url = videos[row]
    let cell = NSTableCellView()
    let picture = NSImageView(frame: CGRect(x: 6, y: 6, width: 112, height: 64))
    picture.imageScaling = .scaleProportionallyUpOrDown
    picture.wantsLayer = true
    picture.layer?.backgroundColor = Look.dock.cgColor
    picture.layer?.cornerRadius = 6
    picture.image = thumbnails[url] ?? NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)
    cell.addSubview(picture)
    let title = NSTextField(labelWithString: details[url] ?? url.lastPathComponent)
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.frame = CGRect(x: 130, y: 40, width: 460, height: 22)
    cell.addSubview(title)
    let srt = url.deletingPathExtension().appendingPathExtension("srt")
    let hasSubtitles = FileManager.default.fileExists(atPath: srt.path) && !url.lastPathComponent.hasSuffix(".subtitled.mp4")
    let kind = NSTextField(labelWithString: videoKind(url.lastPathComponent) + (hasSubtitles ? tr(" · 자막 있음", " · has subtitles") : ""))
    kind.font = .systemFont(ofSize: 13)
    kind.textColor = .secondaryLabelColor
    kind.frame = CGRect(x: 130, y: 16, width: 460, height: 20)
    cell.addSubview(kind)
    if thumbnails[url] == nil || details[url] == nil { load(url) }
    return cell
  }
  /// Picture and length are read in the background, then the row is redrawn.
  private func load(_ url: URL) {
    thumbnails[url] = thumbnails[url] ?? NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)
    details[url] = details[url] ?? url.lastPathComponent
    Task { @MainActor [weak self] in
      let asset = AVURLAsset(url: url)
      let seconds = (try? await asset.load(.duration).seconds) ?? 0
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 240, height: 140)
      let picture = try? await generator.image(at: CMTime(seconds: min(1, seconds / 2), preferredTimescale: 600)).image
      guard let self, let row = self.videos.firstIndex(of: url) else { return }
      if let picture { self.thumbnails[url] = NSImage(cgImage: picture, size: CGSize(width: picture.width, height: picture.height)) }
      let made = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
      let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
      self.details[url] = phoneVideoLabel(PhoneVideo(name: url.lastPathComponent, path: url.path, added: made, bytes: bytes, seconds: seconds.isFinite ? seconds : 0))
      self.table.reloadData(forRowIndexes: [row], columnIndexes: [0])
    }
  }
  private var selected: URL? { table.selectedRow >= 0 && table.selectedRow < videos.count ? videos[table.selectedRow] : nil }
  @objc func openSelected() {
    guard let url = selected, let controller else { return }
    window.close()
    // A finished video with subtitles is only for watching; adding more would print them twice.
    if url.lastPathComponent.hasSuffix(".subtitled.mp4") {
      NSWorkspace.shared.open(url)
    } else {
      controller.openSubtitles(url)
    }
  }
  @objc func revealSelected() {
    if let url = selected { NSWorkspace.shared.activateFileViewerSelecting([url]) }
  }
  @objc func chooseOther() {
    window.close()
    controller?.chooseOtherVideo()
  }
  func windowWillClose(_ notification: Notification) {
    controller?.videoLibrary = nil
    DispatchQueue.main.async { [weak controller] in controller?.giveFocusBack() }
  }
}
