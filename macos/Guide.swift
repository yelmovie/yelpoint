import AVFoundation
import AVKit
import AppKit

/// The usage video with a chapter list. Times match scripts/make-guide.swift.
final class GuideWindow: NSObject, NSWindowDelegate {
  static let chapters: [(title: String, symbol: String, start: Double)] = [
    (tr("처음부터", "From the Start"), "play.fill", 0), (tr("강조", "Highlight"), "cursorarrow", 3.5), (tr("돋보기", "Zoom"), "magnifyingglass", 9.5),
    (tr("펜", "Pen"), "pencil", 15.5), (tr("타이머", "Timer"), "timer", 23.5), (tr("캡처", "Capture"), "camera.viewfinder", 30.5),
    (tr("스팟", "Spot"), "circle.dashed", 39.5), (tr("크기 조절", "Resize"), "arrow.up.and.down", 48), (tr("도구막대", "Toolbar"), "eye.slash", 55),
    (tr("폰 연결", "Phone"), "candybarphone", 64), (tr("칠판 · QR", "Board · QR"), "qrcode", 77),
    (tr("단축키", "Shortcuts"), "keyboard", 87), (tr("이용 안내", "Good to Know"), "info.circle", 92),
  ]
  let window: NSWindow
  let player: AVPlayer
  let sidebar: NSView
  let url: URL
  private var buttons: [ToolButton] = []
  private var timeObserver: Any?
  private var keyMonitor: Any?
  private(set) var currentIndex = 0
  init?(level: NSWindow.Level) {
    guard let url = Bundle.main.url(
      forResource: appEnglish ? "guide-en" : "guide-ko", withExtension: "mp4") else { return nil }
    self.url = url
    player = AVPlayer(url: url)
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1120, height: 540),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    sidebar = NSView(frame: CGRect(x: 0, y: 0, width: 160, height: 540))
    super.init()
    window.title = tr("YelPoint 사용법", "How to Use YelPoint")
    window.isReleasedWhenClosed = false
    window.level = level
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.delegate = self
    let content = NSView(frame: CGRect(x: 0, y: 0, width: 1120, height: 540))
    sidebar.wantsLayer = true
    sidebar.layer?.backgroundColor = Look.dock.cgColor
    for (i, chapter) in GuideWindow.chapters.enumerated() {
      let b = ToolButton(
        frame: CGRect(x: 12, y: 540 - 8 - CGFloat(i + 1) * 35, width: 136, height: 32),
        title: chapter.title, symbol: chapter.symbol
      ) { [weak self] in self?.jump(i) }
      buttons.append(b)
      sidebar.addSubview(b)
    }
    let previous = ToolButton(
      frame: CGRect(x: 12, y: 30, width: 66, height: 44), title: tr("이전", "Back"), symbol: "backward.end.fill"
    ) { [weak self] in self?.skip(-1) }
    let next = ToolButton(
      frame: CGRect(x: 82, y: 30, width: 66, height: 44), title: tr("다음", "Next"), symbol: "forward.end.fill"
    ) { [weak self] in self?.skip(1) }
    previous.toolTip = tr("이전 섹션 (← 키)", "Previous section (← key)")
    next.toolTip = tr("다음 섹션 (→ 키)", "Next section (→ key)")
    sidebar.addSubview(creditLink(CGRect(x: 8, y: 6, width: 144, height: 18), color: Look.paper, align: .center))
    sidebar.addSubview(previous)
    sidebar.addSubview(next)
    let video = AVPlayerView(frame: CGRect(x: 160, y: 0, width: 960, height: 540))
    video.player = player
    video.controlsStyle = .floating
    content.addSubview(sidebar)
    content.addSubview(video)
    window.contentView = content
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 4), queue: .main
    ) { [weak self] time in self?.mark(time.seconds) }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window.isKeyWindow else { return event }
      switch Int(event.keyCode) {
      case 123:
        self.skip(-1)
        return nil
      case 124:
        self.skip(1)
        return nil
      default: return event
      }
    }
  }
  deinit {
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
  }
  var isVisible: Bool { window.isVisible }
  func show() {
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    jump(0)
  }
  func skip(_ delta: Int) {
    jump(min(GuideWindow.chapters.count - 1, max(0, currentIndex + delta)))
  }
  func jump(_ index: Int) {
    let time = CMTime(seconds: GuideWindow.chapters[index].start, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    player.play()
    mark(GuideWindow.chapters[index].start)
  }
  private func mark(_ seconds: Double) {
    let current = GuideWindow.chapters.lastIndex { seconds + 0.01 >= $0.start } ?? 0
    currentIndex = current
    for (i, button) in buttons.enumerated() { button.selected = i == current }
  }
  var onClose: (() -> Void)?
  func windowWillClose(_ notification: Notification) {
    player.pause()
    onClose?()
  }
}
