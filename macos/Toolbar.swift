import AppKit

class ActionButton: NSButton {
  var callback: (() -> Void)?
  init(frame: NSRect, title: String = "", callback: @escaping () -> Void) {
    super.init(frame: frame)
    self.title = title
    self.callback = callback
    target = self
    action = #selector(performClickAction)
    font = .systemFont(ofSize: 12)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func performClickAction() { callback?() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToolButton: NSButton {
  var callback: (() -> Void)?
  /// Toolbar buttons cover nearly the whole bar, so a drag that starts on one moves the bar.
  weak var dragHost: DockView?
  var symbol: String { didSet { needsDisplay = true } }
  var selected = false { didSet { needsDisplay = true } }
  init(frame: NSRect, title: String, symbol: String, callback: @escaping () -> Void) {
    self.symbol = symbol
    super.init(frame: frame)
    self.title = title
    self.callback = callback
    isBordered = false
    target = self
    action = #selector(tapped)
    toolTip = title
    setAccessibilityLabel(title.isEmpty ? symbol : title)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tapped() { callback?() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    guard let dragHost else {
      super.mouseDown(with: event)
      return
    }
    dragHost.mouseDown(with: event)
  }
  override func mouseDragged(with event: NSEvent) {
    guard let dragHost else {
      super.mouseDragged(with: event)
      return
    }
    dragHost.mouseDragged(with: event)
  }
  override func mouseUp(with event: NSEvent) {
    guard let dragHost else {
      super.mouseUp(with: event)
      return
    }
    if dragHost.moved {
      dragHost.mouseUp(with: event)
    } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
      callback?()
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    if selected {
      Look.lime.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11).fill()
    }
    let color = (selected ? Look.dock : Look.paper).withAlphaComponent(isEnabled ? 1 : 0.35)
    let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
      .withSymbolConfiguration(.init(paletteColors: [color]))
    let iw: CGFloat = 17
    let spacing: CGFloat = 7
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: color,
    ]
    let textWidth = title.size(withAttributes: attrs).width
    let x = (bounds.width - iw - (title.isEmpty ? 0 : textWidth + spacing)) / 2
    icon?.draw(in: CGRect(x: x, y: (bounds.height - 17) / 2, width: iw, height: 17))
    if !title.isEmpty {
      title.draw(
        at: CGPoint(x: x + iw + spacing, y: (bounds.height - 15) / 2), withAttributes: attrs)
    }
  }
}

final class DockView: NSView {
  weak var controller: AppController?
  var buttons: [String: ToolButton] = [:]
  // Slim: just enough room for the buttons and the © line under the power button.
  static let wide = CGSize(width: 866, height: 56)
  static let standing = CGSize(width: 92, height: 536)
  private var homes: [String: CGRect] = [:]
  private(set) var vertical = false
  private var pressed = CGPoint.zero
  private(set) var moved = false
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(origin: .zero, size: DockView.wide))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 18
    for (name, title, symbol, x, w) in [
      ("highlight", tr("강조", "Highlight"), "cursorarrow", 20.0, 84.0),
      ("zoom", tr("돋보기", "Zoom"), "magnifyingglass", 106.0, 86.0), ("pen", tr("펜", "Pen"), "pencil", 194.0, 64.0),
      ("timer", tr("타이머", "Timer"), "timer", 260.0, 86.0), ("capture", tr("캡처", "Capture"), "camera.viewfinder", 348.0, 88.0),
      ("spot", tr("스팟", "Spot"), "circle.dashed", 438.0, 76.0),
      ("phone", tr("폰", "Phone"), "candybarphone", 516.0, 70.0),
      ("qr", "QR", "qrcode", 588.0, 60.0),
      ("board", tr("칠판", "Board"), "rectangle.and.pencil.and.ellipsis", 650.0, 70.0),
      ("settings", "", "slider.horizontal.3", 732.0, 38.0),
      ("hide", "", "eye.slash", 772.0, 38.0),
      ("quit", "", "power", 812.0, 38.0),
    ] {
      // The three icon buttons sit higher and shorter, leaving the © line under the power button.
      let icon = ["settings", "hide", "quit"].contains(name)
      let b = ToolButton(
        frame: CGRect(x: x, y: icon ? 18 : 6, width: w, height: icon ? 34 : 44), title: title, symbol: symbol
      ) { [weak controller] in name == "quit" ? controller?.quit() : controller?.toggle(name) }
      b.dragHost = self
      buttons[name] = b
      homes[name] = b.frame
      if name == "settings" { b.setAccessibilityLabel(tr("간단 설정", "Settings")) }
      if name == "board" { b.toolTip = tr("분필로 쓰는 큰 칠판", "A big chalkboard to draw and write on") }
      if name == "qr" { b.toolTip = tr("주소를 QR 코드로 크게 보여 주기", "Show an address as a big QR code") }
      if name == "phone" { b.toolTip = tr("안드로이드 폰·태블릿 화면과 실물화상기", "Android phone or tablet screen and document camera") }
      if name == "hide" {
        b.toolTip = tr("도구막대 숨기기", "Hide toolbar")
        b.setAccessibilityLabel(tr("도구막대 숨기기", "Hide toolbar"))
      }
      if name == "quit" {
        b.toolTip = tr("YelPoint 종료", "Quit YelPoint")
        b.setAccessibilityLabel(tr("YelPoint 종료", "Quit YelPoint"))
      }
      addSubview(b)
    }
    let menu = NSMenu()
    let help = NSMenuItem(
      title: tr("사용법과 단축키", "How to Use"), action: #selector(AppController.showHelp), keyEquivalent: "")
    help.target = controller
    menu.addItem(help)
    let quit = NSMenuItem(
      title: tr("YelPoint 종료", "Quit YelPoint"), action: #selector(AppController.quit), keyEquivalent: "q")
    quit.target = controller
    menu.addItem(quit)
    self.menu = menu
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  func layoutTools(vertical: Bool) {
    self.vertical = vertical
    setFrameSize(vertical ? DockView.standing : DockView.wide)
    for (i, name) in ["highlight", "zoom", "pen", "timer", "capture", "spot", "phone", "qr", "board"].enumerated() {
      buttons[name]?.frame =
        vertical
        ? CGRect(x: 6, y: DockView.standing.height - 14 - CGFloat(i + 1) * 45, width: 80, height: 43)
        : homes[name] ?? .zero
    }
    // Standing up, settings and hide share a row and quit gets the bottom row to itself.
    buttons["settings"]?.frame =
      vertical ? CGRect(x: 6, y: 66, width: 38, height: 40) : homes["settings"] ?? .zero
    buttons["hide"]?.frame =
      vertical ? CGRect(x: 48, y: 66, width: 38, height: 40) : homes["hide"] ?? .zero
    buttons["quit"]?.frame =
      vertical ? CGRect(x: 27, y: 22, width: 38, height: 38) : homes["quit"] ?? .zero
    needsDisplay = true
  }
  // Moved here rather than by the window server, so the bar can change shape mid-drag.
  override func mouseDown(with event: NSEvent) {
    pressed = NSEvent.mouseLocation
    moved = false
    controller?.beginToolbarDrag(at: pressed)
  }
  override func mouseDragged(with event: NSEvent) {
    let p = NSEvent.mouseLocation
    if !moved, hypot(p.x - pressed.x, p.y - pressed.y) < 4 { return }
    moved = true
    controller?.dragToolbar(to: p)
  }
  override func mouseUp(with event: NSEvent) {
    if moved {
      controller?.endToolbarDrag()
    } else if creditRect.insetBy(dx: -6, dy: -4).contains(convert(event.locationInWindow, from: nil)) {
      showCreditMenu()
    }
  }
  // ---- © mark centered under the power button: blog and suggestions ----
  private static let creditAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: Look.paper.withAlphaComponent(0.72),
  ]
  static let creditLabel = "© yelsam.lab"
  var creditRect: CGRect {
    let size = (DockView.creditLabel as NSString).size(withAttributes: DockView.creditAttributes)
    let power = buttons["quit"]?.frame ?? .zero
    // Kept inside the bar on the right; the power button sits close to the edge.
    let x = min(power.midX - size.width / 2, bounds.maxX - size.width - 6)
    return CGRect(x: x.rounded(), y: (power.minY - size.height - 2).rounded(), width: size.width, height: size.height)
  }
  func showCreditMenu() { creditMenu().popUp(positioning: nil, at: CGPoint(x: creditRect.minX, y: creditRect.maxY + 4), in: self) }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.withAlphaComponent(0.18).setFill()
    (vertical
      ? CGRect(x: 12, y: 111, width: 68, height: 1) : CGRect(x: 726, y: 17, width: 1, height: 22))
      .fill()
    NSColor.white.withAlphaComponent(0.4).setFill()
    (DockView.creditLabel as NSString).draw(at: creditRect.origin, withAttributes: DockView.creditAttributes)
    let columns: [CGFloat] = vertical ? [39, 45, 51] : [8, 13]
    let rows: [CGFloat] = vertical ? [bounds.maxY - 10, bounds.maxY - 5] : [21, 27, 33]
    for x in columns {
      for y in rows {
        NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 2, height: 2)).fill()
      }
    }
  }
  func refresh() {
    guard let c = controller else { return }
    buttons["highlight"]?.selected = c.preferences.highlight
    buttons["zoom"]?.selected = c.zoom
    buttons["pen"]?.selected = c.pen
    buttons["timer"]?.selected = c.timerPanel.isVisible || c.countdown.isActive
    buttons["capture"]?.selected = c.capturePanel.isVisible || c.selecting || c.recorder != nil
    buttons["capture"]?.title = c.recorder == nil ? tr("캡처", "Capture") : tr("녹화중", "Recording")
    buttons["spot"]?.selected = c.spotPanel.isVisible || c.spot != nil
    buttons["settings"]?.selected = c.settingsPanel.isVisible
    buttons["phone"]?.selected = c.phonePanel.isVisible || c.phone.running
    buttons["qr"]?.selected = c.qrPanel.isVisible || c.qrWindow.isVisible
    buttons["board"]?.selected = c.boardWindow.isVisible
  }
}

/// The knob is drawn at the real pen width, in the current ink.
/// What the toolbar shrinks to. Click to expand, drag to move.
final class MiniView: NSView {
  weak var controller: AppController?
  private var grabbed = CGPoint.zero
  private var moved = false
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 46, height: 46))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 23
    toolTip = tr("누르면 도구막대가 보여요. 끌면 옮겨져요.", "Click to show the toolbar. Drag to move.")
    setAccessibilityRole(.button)
    setAccessibilityLabel(tr("도구막대 보이기", "Show toolbar"))
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let icon = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(paletteColors: [Look.lime]))
    icon?.draw(in: bounds.insetBy(dx: 12, dy: 12))
  }
  override func mouseDown(with event: NSEvent) {
    guard let origin = window?.frame.origin else { return }
    let p = NSEvent.mouseLocation
    grabbed = CGPoint(x: p.x - origin.x, y: p.y - origin.y)
    moved = false
  }
  override func mouseDragged(with event: NSEvent) {
    guard let window else { return }
    let p = NSEvent.mouseLocation
    let origin = CGPoint(x: p.x - grabbed.x, y: p.y - grabbed.y)
    if !moved, hypot(origin.x - window.frame.minX, origin.y - window.frame.minY) < 4 { return }
    moved = true
    controller?.moveMini(to: origin)
  }
  override func mouseUp(with event: NSEvent) {
    if moved {
      controller?.keepMiniOnScreen()
    } else {
      controller?.setToolbarHidden(false)
    }
  }
}

final class PenWidthSlider: NSView {
  weak var controller: AppController?
  private let trackStart: CGFloat = 16
  private var trackEnd: CGFloat { bounds.width - 44 }
  init(frame: NSRect, controller: AppController) {
    self.controller = controller
    super.init(frame: frame)
    toolTip = tr("끌어서 펜 굵기 바꾸기", "Drag to change pen width")
    setAccessibilityRole(.slider)
    setAccessibilityLabel(tr("펜 굵기", "Pen width"))
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let c = controller else { return }
    let width = c.preferences.penWidth
    Look.paper.withAlphaComponent(0.3).setFill()
    NSBezierPath(
      roundedRect: CGRect(x: trackStart, y: bounds.midY - 1.5, width: trackEnd - trackStart, height: 3),
      xRadius: 1.5, yRadius: 1.5
    ).fill()
    let x = trackStart + (width - 1) / 29 * (trackEnd - trackStart)
    let size = max(12, width)
    let knob = NSBezierPath(
      ovalIn: CGRect(x: x - size / 2, y: bounds.midY - size / 2, width: size, height: size))
    c.inkColor.setFill()
    knob.fill()
    Look.paper.setStroke()
    knob.lineWidth = 2
    knob.stroke()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
      .foregroundColor: Look.paper,
    ]
    let text = String(Int(width))
    let measured = text.size(withAttributes: attributes)
    text.draw(
      at: CGPoint(x: bounds.maxX - 14 - measured.width, y: bounds.midY - measured.height / 2),
      withAttributes: attributes)
  }
  func pick(x: CGFloat) {
    controller?.preferences.penWidth = penWidth(
      atFraction: (x - trackStart) / (trackEnd - trackStart))
    needsDisplay = true
  }
  override func mouseDown(with event: NSEvent) { pick(x: convert(event.locationInWindow, from: nil).x) }
  override func mouseDragged(with event: NSEvent) {
    pick(x: convert(event.locationInWindow, from: nil).x)
  }
  override func mouseUp(with event: NSEvent) { controller?.preferencesChanged() }
}

final class PenView: NSView {
  weak var controller: AppController?
  var undo: ToolButton!, clear: ToolButton!, widthSlider: PenWidthSlider!
  var wheelButton: ColorWheelButton!
  private var dots: [NSButton] = []
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 407, height: 48))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    for i in 0..<3 {
      let b = ActionButton(frame: CGRect(x: 9 + i * 35, y: 8, width: 29, height: 32)) {
        [weak controller] in
        controller?.preferences.penColor = i
        controller?.preferences.inkRGB = nil
        controller?.preferencesChanged()
      }
      b.isBordered = false
      b.title = "●"
      b.font = .systemFont(ofSize: 23)
      b.contentTintColor = Look.ink[i]
      b.attributedTitle = NSAttributedString(
        string: "●",
        attributes: [
          .font: NSFont.systemFont(ofSize: 23), .foregroundColor: Look.ink[i],
        ])
      b.toolTip = [tr("주황색", "Orange"), tr("파란색", "Blue"), tr("초록색", "Green")][i]
      b.setAccessibilityLabel(b.toolTip)
      dots.append(b)
      addSubview(b)
    }
    let wheel = ColorWheelButton(frame: CGRect(x: 115, y: 11, width: 27, height: 27)) {
      [weak controller] in controller?.toggleColorPanel()
    }
    wheel.controller = controller
    wheel.isBordered = false
    wheel.toolTip = tr("색상환에서 색 고르기", "Pick a color from the wheel")
    wheel.setAccessibilityLabel(tr("색상환에서 색 고르기", "Pick a color from the wheel"))
    wheelButton = wheel
    addSubview(wheel)
    widthSlider = PenWidthSlider(
      frame: CGRect(x: 150, y: 4, width: 160, height: 40), controller: controller)
    addSubview(widthSlider)
    undo = ToolButton(
      frame: CGRect(x: 316, y: 4, width: 38, height: 40), title: "", symbol: "arrow.uturn.backward"
    ) { [weak controller] in controller?.undo() }
    undo.toolTip = tr("되돌리기", "Undo")
    undo.setAccessibilityLabel(tr("되돌리기", "Undo"))
    addSubview(undo)
    clear = ToolButton(
      frame: CGRect(x: 361, y: 4, width: 38, height: 40), title: "", symbol: "trash"
    ) { [weak controller] in controller?.clear() }
    clear.toolTip = tr("모두 지우기", "Clear all")
    clear.setAccessibilityLabel(tr("모두 지우기", "Clear all"))
    addSubview(clear)
  }
  required init?(coder: NSCoder) { fatalError() }
  func refresh() {
    guard let c = controller else { return }
    widthSlider.needsDisplay = true
    let hasInk =
      c.overlays.contains { !$0.1.strokes.isEmpty || $0.1.activeStroke != nil }
      || c.stickers.contains { ($0.contentView as? StickerView)?.hasInk == true }
    var restorable = false
    if case .cleared = c.undoHistory.last { restorable = true }
    undo.isEnabled = hasInk || restorable
    clear.isEnabled = hasInk
    undo.needsDisplay = true
    clear.needsDisplay = true
    wheelButton.needsDisplay = true
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let c = controller else { return }
    Look.lime.setStroke()
    let slot = c.preferences.inkRGB == nil ? c.preferences.penColor : 3
    // Around whichever control is chosen, wherever the layout put it (flat or standing).
    let chosen = slot < dots.count ? dots[slot].frame : wheelButton.frame
    let r = CGRect(x: chosen.midX - 15.5, y: chosen.midY - 15.5, width: 31, height: 31)
    let p = NSBezierPath(ovalIn: r)
    p.lineWidth = 1
    p.stroke()
  }
}

/// Hue runs around the rim, saturation from centre to rim, as `wheelPick` reads it back.
func makeColorWheel(diameter: Int) -> NSImage {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: diameter, pixelsHigh: diameter, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: diameter * 4, bitsPerPixel: 32)!
  let radius = Double(diameter) / 2
  let pixels = rep.bitmapData!
  for y in 0..<diameter {
    for x in 0..<diameter {
      let dx = Double(x) + 0.5 - radius
      let dy = radius - Double(y) - 0.5
      let pick = wheelPick(dx: dx, dy: dy, radius: radius)
      let rgb = hsvToRGB(hue: pick.hue, saturation: pick.saturation, value: 1)
      let alpha = min(1, max(0, radius - hypot(dx, dy)))
      let i = (y * diameter + x) * 4
      // The bitmap is premultiplied.
      pixels[i] = UInt8(Double(rgb >> 16 & 255) * alpha)
      pixels[i + 1] = UInt8(Double(rgb >> 8 & 255) * alpha)
      pixels[i + 2] = UInt8(Double(rgb & 255) * alpha)
      pixels[i + 3] = UInt8(255 * alpha)
    }
  }
  let image = NSImage(size: CGSize(width: diameter / 2, height: diameter / 2))
  image.addRepresentation(rep)
  return image
}

final class ColorWheelButton: ActionButton {
  weak var controller: AppController?
  private static let wheel = makeColorWheel(diameter: 54)
  convenience init(frame: NSRect, callback: @escaping () -> Void) {
    self.init(frame: frame, title: "", callback: callback)
  }
  override func draw(_ dirtyRect: NSRect) {
    ColorWheelButton.wheel.draw(in: bounds)
    guard let c = controller else { return }
    c.inkColor.setFill()
    NSBezierPath(ovalIn: bounds.insetBy(dx: 8, dy: 8)).fill()
  }
}

final class ColorWheelView: NSView {
  weak var controller: AppController?
  private static let wheel = makeColorWheel(diameter: 336)
  private let wheelRect = CGRect(x: 14, y: 50, width: 168, height: 168)
  private let barRect = CGRect(x: 14, y: 16, width: 168, height: 18)
  private var hue = 0.0, saturation = 1.0, value = 1.0
  private var trackingBar = false
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 196, height: 232))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 16
    setAccessibilityLabel(tr("펜 색상환과 밝기 막대", "Pen color wheel and brightness"))
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  func sync() {
    guard let color = controller?.inkColor.usingColorSpace(.sRGB) else { return }
    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
    color.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
    (hue, saturation, value) = (Double(h), Double(s), Double(v))
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    ColorWheelView.wheel.draw(in: wheelRect)
    let top = NSColor(rgb: hsvToRGB(hue: hue, saturation: saturation, value: 1))
    let bar = NSBezierPath(roundedRect: barRect, xRadius: 9, yRadius: 9)
    NSGradient(starting: .black, ending: top)?.draw(in: bar, angle: 0)
    let angle = hue * 2 * Double.pi
    let distance = saturation * wheelRect.width / 2
    let wheelMark = CGPoint(
      x: wheelRect.midX + cos(angle) * distance, y: wheelRect.midY + sin(angle) * distance)
    let barMark = CGPoint(x: barRect.minX + value * barRect.width, y: barRect.midY)
    for mark in [wheelMark, barMark] {
      let ring = NSBezierPath(ovalIn: CGRect(x: mark.x - 7, y: mark.y - 7, width: 14, height: 14))
      ring.lineWidth = 2
      NSColor.white.setStroke()
      ring.stroke()
    }
  }
  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    trackingBar = barRect.insetBy(dx: -6, dy: -8).contains(p)
    pick(p)
  }
  override func mouseDragged(with event: NSEvent) { pick(convert(event.locationInWindow, from: nil)) }
  override func mouseUp(with event: NSEvent) { controller?.preferencesChanged() }
  func pick(_ p: CGPoint) {
    if trackingBar {
      value = min(1, max(0, (p.x - barRect.minX) / barRect.width))
    } else {
      let result = wheelPick(
        dx: p.x - wheelRect.midX, dy: p.y - wheelRect.midY, radius: wheelRect.width / 2)
      (hue, saturation) = result
    }
    controller?.preferences.inkRGB = hsvToRGB(hue: hue, saturation: saturation, value: value)
    controller?.penView.refresh()
    needsDisplay = true
  }
}

/// The small © yelsam.lab popup: the blog, and a mail with suggestions.
func creditMenu() -> NSMenu {
  let menu = NSMenu()
  let title = NSMenuItem(title: "© yelsam.lab", action: nil, keyEquivalent: "")
  title.isEnabled = false
  menu.addItem(title)
  menu.addItem(ClosureMenuItem(tr("옐샘 블로그 둘러보기", "Visit Yelsam's blog")) { NSWorkspace.shared.open(blogURL) })
  menu.addItem(ClosureMenuItem(tr("옐샘에게 제안하기", "Send Yelsam a suggestion")) { suggestToYelsam() })
  return menu
}
/// Opens a mail to Yelsam; without a mail app, copies the address instead.
func suggestToYelsam() {
  if NSWorkspace.shared.open(suggestURL) { return }
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(suggestAddress, forType: .string)
  (NSApp.delegate as? AppController)?.toast(tr("메일 주소를 복사했어요 · ", "Address copied · ") + suggestAddress)
}

/// Small, and only in places that stay out of the lesson on screen.
func creditLink(_ frame: CGRect, color: NSColor, align: NSTextAlignment) -> NSButton {
  let link = ActionButton(frame: frame) {}
  link.callback = { [weak link] in
    guard let link else { return }
    creditMenu().popUp(positioning: nil, at: CGPoint(x: 0, y: link.isFlipped ? link.bounds.maxY + 4 : -4), in: link)
  }
  link.isBordered = false
  let style = NSMutableParagraphStyle()
  style.alignment = align
  link.attributedTitle = NSAttributedString(
    string: tr("© yelsam.lab · 블로그·제안", "© yelsam.lab · Blog·Ideas"),
    attributes: [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: color.withAlphaComponent(0.7),
      .paragraphStyle: style,
    ])
  link.toolTip = tr("옐샘 블로그 둘러보기 · 옐샘에게 제안하기", "Visit Yelsam's blog · Send a suggestion")
  link.setAccessibilityLabel(tr("yelsam.lab 블로그와 제안", "yelsam.lab blog and suggestions"))
  return link
}

final class ZoomView: NSView {
  weak var controller: AppController?
  private var buttons: [ActionButton] = []
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 286, height: 48))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    for (i, level) in zoomLevels.enumerated() {
      let b = ActionButton(frame: CGRect(x: 8 + i * 54, y: 7, width: 54, height: 34)) {
        [weak controller] in controller?.setZoom(level)
      }
      b.isBordered = false
      b.wantsLayer = true
      b.layer?.cornerRadius = 10
      b.setAccessibilityLabel(tr("배율", "Zoom") + " \(level)")
      buttons.append(b)
      addSubview(b)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  func refresh() {
    guard let c = controller else { return }
    // Control+scroll can land between the buttons; the nearest one shows as chosen.
    let nearest = zoomLevels.min { abs($0 - c.preferences.zoom) < abs($1 - c.preferences.zoom) }
    for (i, level) in zoomLevels.enumerated() {
      let selected = level == nearest
      buttons[i].layer?.backgroundColor = selected ? Look.lime.cgColor : NSColor.clear.cgColor
      buttons[i].attributedTitle = NSAttributedString(
        string: level == level.rounded() ? "\(Int(level))×" : "\(level)×",
        attributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
          .foregroundColor: selected ? Look.dock : Look.paper,
        ])
    }
  }
}

/// The countdown, floating on its own. Drag to move, drag the bottom-right corner to resize.
final class ClockView: NSView {
  weak var controller: AppController?
  var text = ""
  var alert = false
  var pop: CGFloat?
  private var startFrame = CGRect.zero
  private var startPoint = CGPoint.zero
  private var resizing = false
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 196, height: 76))
    toolTip = tr("끌어서 옮기기 · 오른쪽 아래 모서리를 끌어 크기 조절", "Drag to move · drag the bottom-right corner to resize")
  }
  required init?(coder: NSCoder) { fatalError() }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let scale = bounds.width / 196
    let p = pop ?? 0
    let shrink = 1 - 0.85 * p * p
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: bounds.midX, yBy: bounds.midY)
    transform.scale(by: shrink)
    transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
    transform.concat()
    (alert ? Look.ink[0] : Look.dock).withAlphaComponent(1 - p).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 16 * scale, yRadius: 16 * scale).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 40 * scale, weight: .semibold),
      .foregroundColor: Look.paper.withAlphaComponent(1 - p),
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
      at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
      withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    if p > 0 {
      Look.lime.withAlphaComponent(1 - p).setFill()
      for i in 0..<10 {
        let angle = CGFloat(i) / 10 * 2 * .pi
        let reach = (0.15 + 0.35 * p) * bounds.height
        let dot = 3 * scale * (1 - p * 0.5)
        let x = bounds.midX + cos(angle) * reach * 2.2
        let y = bounds.midY + sin(angle) * reach
        NSBezierPath(ovalIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)).fill()
      }
    } else {
      Look.paper.withAlphaComponent(0.35).setStroke()
      for inset in [CGFloat(6), 11] {
        let grip = NSBezierPath()
        grip.move(to: CGPoint(x: bounds.maxX - inset * scale, y: 4 * scale))
        grip.line(to: CGPoint(x: bounds.maxX - 4 * scale, y: inset * scale))
        grip.lineWidth = 1.5
        grip.stroke()
      }
    }
  }
  override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    let local = convert(event.locationInWindow, from: nil)
    resizing = local.x > bounds.width - 26 && local.y < 26
    startFrame = window.frame
    startPoint = NSEvent.mouseLocation
  }
  override func mouseDragged(with event: NSEvent) {
    guard let window else { return }
    let p = NSEvent.mouseLocation
    if resizing {
      window.setFrame(resizedClock(startFrame, dx: p.x - startPoint.x), display: true)
    } else {
      window.setFrameOrigin(
        CGPoint(x: startFrame.minX + p.x - startPoint.x, y: startFrame.minY + p.y - startPoint.y))
    }
  }
  override func mouseUp(with event: NSEvent) { controller?.clockMoved() }
}

final class TimerView: NSView {
  weak var controller: AppController?
  var minutesField: NSTextField!
  var start: ToolButton!
  var minuteButtons: [NSButton] = []
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 388, height: 48))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    func add(
      _ title: String, _ x: Int, _ width: Int, _ name: String,
      _ minutes: @escaping (Int) -> Int
    ) {
      let b = ActionButton(frame: CGRect(x: x, y: 8, width: width, height: 32)) {
        [weak controller, weak self] in
        guard let c = controller else { return }
        // Drop a half-typed value first, or the field keeps showing it over the new minutes.
        self?.minutesField.abortEditing()
        c.setTimer(minutes: minutes(c.countdown.minutes))
        self?.refresh()
      }
      b.isBordered = false
      b.attributedTitle = NSAttributedString(
        string: title,
        attributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Look.paper,
        ])
      b.toolTip = name
      b.setAccessibilityLabel(name)
      minuteButtons.append(b)
      addSubview(b)
    }
    add("−", 8, 30, tr("1분 줄이기", "1 minute less")) { $0 - 1 }
    add("+", 94, 30, tr("1분 늘리기", "1 minute more")) { $0 + 1 }
    for (i, value) in [5, 10, 30, 60].enumerated() {
      add(String(value), 136 + i * 40, 38, tr("\(value)분으로 맞추기", "Set to \(value) minutes")) { _ in value }
    }
    minutesField = NSTextField(string: "")
    minutesField.frame = CGRect(x: 38, y: 12, width: 34, height: 24)
    minutesField.alignment = .center
    minutesField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    minutesField.textColor = Look.paper
    minutesField.backgroundColor = NSColor.white.withAlphaComponent(0.12)
    minutesField.drawsBackground = true
    minutesField.isBordered = false
    minutesField.focusRingType = .none
    minutesField.target = self
    minutesField.action = #selector(minutesTyped)
    minutesField.cell?.sendsActionOnEndEditing = true
    minutesField.toolTip = tr("분을 입력하고 Enter (1~60)", "Type minutes and press Enter (1 to 60)")
    minutesField.setAccessibilityLabel(tr("분 입력", "Minutes"))
    addSubview(minutesField)
    let unit = NSTextField(labelWithString: tr("분", "min"))
    unit.frame = CGRect(x: 73, y: 15, width: 22, height: 18)
    unit.font = .systemFont(ofSize: 11)
    unit.textColor = Look.paper
    addSubview(unit)
    start = ToolButton(
      frame: CGRect(x: 302, y: 4, width: 38, height: 40), title: "", symbol: "play.fill"
    ) { [weak controller] in controller?.timerStartPause() }
    addSubview(start)
    let reset = ToolButton(
      frame: CGRect(x: 342, y: 4, width: 38, height: 40), title: "",
      symbol: "arrow.counterclockwise"
    ) { [weak controller] in controller?.timerReset() }
    reset.toolTip = tr("타이머 초기화", "Reset timer")
    reset.setAccessibilityLabel(tr("타이머 초기화", "Reset timer"))
    addSubview(reset)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func minutesTyped() {
    if let value = Int(minutesField.stringValue.trimmingCharacters(in: .whitespaces)) {
      controller?.setTimer(minutes: value)
    }
    window?.makeFirstResponder(nil)
    refresh()
  }
  func refresh() {
    guard let c = controller else { return }
    if minutesField.currentEditor() == nil { minutesField.stringValue = "\(c.countdown.minutes)" }
    minutesField.isEnabled = !c.countdown.isLocked
    start.symbol = c.countdown.isRunning ? "pause.fill" : "play.fill"
    start.toolTip = c.countdown.isRunning ? tr("일시정지", "Pause") : tr("시작", "Start")
    start.setAccessibilityLabel(start.toolTip)
    for button in minuteButtons {
      button.isEnabled = !c.countdown.isLocked
      button.alphaValue = c.countdown.isLocked ? 0.35 : 1
    }
  }
}

final class CaptureView: NSView {
  weak var controller: AppController?
  var record: ToolButton!
  private var subtitles: ToolButton!
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 516, height: 48))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    let items: [(String, String, String, (AppController) -> Void)] = [
      (tr("다시 캡처", "Capture"), "viewfinder", tr("드래그해서 영역 캡처", "Drag to capture an area"), { $0.beginSelection() }),
      (tr("그림 붙이기", "Paste"), "doc.on.clipboard", tr("복사한 그림을 화면에 띄우기", "Show the copied picture on screen"), { $0.pasteSticker() }),
      (tr("PNG 저장", "Save PNG"), "square.and.arrow.down", tr("마지막 캡처를 PNG로 저장", "Save the last capture as PNG"), { $0.saveCapture() }),
      (tr("화면 녹화", "Record"), "record.circle", tr("화면 녹화 시작·정지", "Start or stop recording"), { $0.toggleRecording() }),
      (tr("내 영상", "My Videos"), "film", tr("녹화한 영상 보기 · 자막 넣기", "Watch your videos and add subtitles"), { $0.chooseVideoForSubtitles() }),
    ]
    for (i, (title, symbol, tip, action)) in items.enumerated() {
      let b = ToolButton(
        frame: CGRect(x: 8 + i * 100, y: 4, width: 100, height: 40), title: title, symbol: symbol
      ) { [weak controller] in
        if let controller { action(controller) }
      }
      b.toolTip = tip
      // By position, not by label, so renaming a button can never leave these empty.
      if i == 3 { record = b }
      if i == 4 { subtitles = b }
      addSubview(b)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  func refresh() {
    guard let c = controller else { return }
    record.selected = c.recorder != nil
    record.title = c.recorder == nil ? tr("화면 녹화", "Record") : tr("녹화 정지", "Stop")
    record.symbol = c.recorder == nil ? "record.circle" : "stop.fill"
    // Locked while recording, so a stray click next to Stop cannot open a file window.
    subtitles.isEnabled = c.recorder == nil
  }
}

/// Shortcut keys as a small two-column table: key on the left, what it does on the right.
final class ShortcutTable: NSView {
  static var rows: [(key: String, text: String)] {
    [
      ("⌃⌥ 1~6", tr("1 강조 · 2 돋보기 · 3 펜\n4 타이머 · 5 캡처 · 6 스팟", "1 Highlight · 2 Zoom · 3 Pen\n4 Timer · 5 Capture · 6 Spot")),
      ("⌃⌥ 0", tr("도구막대 숨기기 · 다시 보이기", "Hide or show the toolbar")),
      ("Esc", tr("쓰던 도구 끄고 평소 마우스로", "Tools off, back to the mouse")),
      (tr("Option 꾹", "Hold ⌥"), tr("필기 중에 아래 화면 클릭", "Click through the ink")),
      ("⌃ + " + tr("스크롤", "scroll"), tr("위로 크게 · 아래로 작게\n(강조 원 · 스팟 크기)", "Up larger · down smaller\n(pointer ring, spot)")),
    ]
  }
  static let keyWidth: CGFloat = 76
  static let rowGap: CGFloat = 5
  private static let textFont = NSFont.systemFont(ofSize: 10.5)
  private static let keyFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
  static func height(width: CGFloat) -> CGFloat {
    rows.reduce(18) { $0 + rowHeight($1.text, width: width) + rowGap }
  }
  private static func rowHeight(_ text: String, width: CGFloat) -> CGFloat {
    let box = (text as NSString).boundingRect(
      with: CGSize(width: width - keyWidth - 8, height: 200), options: [.usesLineFragmentOrigin],
      attributes: [.font: textFont])
    return max(18, ceil(box.height) + 2)
  }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    (tr("단축키", "Shortcut keys") as NSString).draw(
      at: CGPoint(x: 0, y: 0), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: Look.dock])
    var y: CGFloat = 18
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    for (i, row) in ShortcutTable.rows.enumerated() {
      let height = ShortcutTable.rowHeight(row.text, width: bounds.width)
      if i > 0 {
        Look.dock.withAlphaComponent(0.08).setFill()
        CGRect(x: 0, y: y - ShortcutTable.rowGap / 2 - 0.5, width: bounds.width, height: 1).fill()
      }
      let chip = CGRect(x: 0, y: y + (height - 18) / 2, width: ShortcutTable.keyWidth, height: 18)
      Look.dock.withAlphaComponent(0.09).setFill()
      NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
      (row.key as NSString).draw(
        in: chip.offsetBy(dx: 0, dy: 2),
        withAttributes: [.font: ShortcutTable.keyFont, .foregroundColor: Look.dock, .paragraphStyle: center])
      (row.text as NSString).draw(
        in: CGRect(x: ShortcutTable.keyWidth + 8, y: y + 1, width: bounds.width - ShortcutTable.keyWidth - 8, height: height),
        withAttributes: [.font: ShortcutTable.textFont, .foregroundColor: Look.dock.withAlphaComponent(0.85)])
      y += height + ShortcutTable.rowGap
    }
  }
}

final class SettingsView: NSView {
  weak var controller: AppController?
  var checks: [NSButton] = []
  var message: NSTextField!
  static let width: CGFloat = 286
  /// Grows with the shortcut table, so English and Korean both fit.
  static var height: CGFloat { 237 + ShortcutTable.height(width: 250) }
  init(controller: AppController) {
    self.controller = controller
    let height = SettingsView.height
    super.init(frame: CGRect(x: 0, y: 0, width: SettingsView.width, height: height))
    wantsLayer = true
    layer?.backgroundColor = Look.paper.cgColor
    layer?.cornerRadius = 16
    let heading = NSTextField(labelWithString: "YelPoint")
    heading.frame = CGRect(x: 18, y: height - 32, width: 100, height: 20)
    heading.font = .systemFont(ofSize: 14, weight: .semibold)
    heading.textColor = Look.dock
    addSubview(heading)
    addSubview(creditLink(CGRect(x: 118, y: height - 31, width: 150, height: 18), color: Look.dock, align: .right))
    for (i, title) in [tr("단축키 표시", "Show shortcut keys"), tr("필기 자동 지우기 (4초)", "Fade ink after 4 seconds"), tr("주변 어둡게", "Dim around pointer")].enumerated() {
      let b = ActionButton(
        frame: CGRect(x: 18, y: height - 67 - CGFloat(i) * 31, width: 250, height: 25), title: title
      ) { [weak controller] in controller?.changeSetting(i) }
      b.setButtonType(.switch)
      b.textColorCompat()
      checks.append(b)
      addSubview(b)
    }
    let tableHeight = ShortcutTable.height(width: 250)
    let table = ShortcutTable(frame: CGRect(x: 18, y: 100, width: 250, height: tableHeight))
    addSubview(table)
    // ⌃ and ⌥ explained; replaced by a warning if a shortcut clashes with another app.
    message = NSTextField(wrappingLabelWithString: tr("⌃ = Control 키 · ⌥ = Option 키", "⌃ = Control · ⌥ = Option"))
    message.frame = CGRect(x: 18, y: 72, width: 250, height: 26)
    message.font = .systemFont(ofSize: 10)
    message.textColor = Look.dock.withAlphaComponent(0.7)
    addSubview(message)
    let language = NSTextField(labelWithString: "언어 / Language")
    language.frame = CGRect(x: 18, y: 46, width: 100, height: 18)
    language.font = .systemFont(ofSize: 11)
    language.textColor = Look.dock
    addSubview(language)
    for (i, title) in ["한국어", "English"].enumerated() {
      let b = ActionButton(frame: CGRect(x: 120 + i * 76, y: 42, width: 72, height: 26), title: title) {
        [weak controller] in controller?.setLanguage(english: i == 1)
      }
      b.bezelStyle = .rounded
      b.state = (i == 1) == appEnglish ? .on : .off
      b.isEnabled = (i == 1) != appEnglish
      addSubview(b)
    }
    let help = ActionButton(frame: CGRect(x: 14, y: 12, width: 115, height: 26), title: tr("사용법", "How to Use")) {
      [weak controller] in controller?.showHelp()
    }
    help.bezelStyle = .rounded
    addSubview(help)
    let quit = ActionButton(frame: CGRect(x: 151, y: 12, width: 120, height: 26), title: tr("종료", "Quit")) {
      [weak controller] in controller?.quit()
    }
    quit.bezelStyle = .rounded
    addSubview(quit)
  }
  required init?(coder: NSCoder) { fatalError() }
  func refresh() {
    guard let c = controller else { return }
    for (i, value) in [c.preferences.keyboardHUD, c.preferences.fadingInk, c.preferences.spotlight]
      .enumerated()
    { checks[i].state = value ? .on : .off }
  }
}

extension NSButton {
  func textColorCompat() {
    attributedTitle = NSAttributedString(
      string: title,
      attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Look.dock])
  }
}

/// Re-lays a panel for a standing toolbar: the same controls in the same order, wrapped into
/// rows that fit a narrow column, so a standing bar never has a long flat panel sticking out of it.
final class PanelStack {
  private var frames: [ObjectIdentifier: CGRect] = [:]
  private var sizes: [ObjectIdentifier: CGSize] = [:]
  private var labels: [ObjectIdentifier: (Bool, Int)] = [:]
  func apply(_ view: NSView, vertical: Bool, width: CGFloat) {
    let key = ObjectIdentifier(view)
    if sizes[key] == nil {
      sizes[key] = view.frame.size
      for v in view.subviews { frames[ObjectIdentifier(v)] = v.frame }
    }
    guard vertical else {
      for v in view.subviews {
        if let f = frames[ObjectIdentifier(v)] { v.frame = f }
        if let label = v as? NSTextField, let old = labels[ObjectIdentifier(v)] {
          label.cell?.wraps = old.0
          label.maximumNumberOfLines = old.1
        }
      }
      if let size = sizes[key] { view.setFrameSize(size) }
      return
    }
    let pad: CGFloat = 6, gap: CGFloat = 4, room = width - pad * 2
    // Reading order of the flat layout: top row first, then left to right.
    let items = view.subviews.compactMap { v in frames[ObjectIdentifier(v)].map { (v, $0) } }
      .sorted { a, b in
        let ra = -(a.1.midY / 20).rounded(), rb = -(b.1.midY / 20).rounded()
        return ra != rb ? ra < rb : a.1.minX < b.1.minX
      }
    var rows: [[(NSView, CGSize)]] = [[]]
    var used: CGFloat = 0
    for (v, f) in items {
      var size = CGSize(width: min(f.width, room), height: f.height)
      if let label = v as? NSTextField, !label.isEditable, f.width > room {
        // A long status line wraps onto up to three lines instead of being cut off.
        if labels[ObjectIdentifier(v)] == nil { labels[ObjectIdentifier(v)] = (label.cell?.wraps ?? false, label.maximumNumberOfLines) }
        label.cell?.wraps = true
        label.maximumNumberOfLines = 3
        let fit = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: room, height: 1000)).height ?? f.height
        size = CGSize(width: room, height: min(max(f.height, ceil(fit)), f.height * 3 + 6))
      }
      if !rows[rows.count - 1].isEmpty, used + gap + size.width > room {
        rows.append([])
        used = 0
      }
      used += (rows[rows.count - 1].isEmpty ? 0 : gap) + size.width
      rows[rows.count - 1].append((v, size))
    }
    let heights = rows.map { $0.map(\.1.height).max() ?? 0 }
    let total = pad * 2 + heights.reduce(0, +) + gap * CGFloat(max(0, rows.count - 1))
    view.setFrameSize(CGSize(width: width, height: total))
    var top = total - pad
    for (row, height) in zip(rows, heights) {
      let rowWidth = row.map(\.1.width).reduce(0, +) + gap * CGFloat(max(0, row.count - 1))
      var x = ((width - rowWidth) / 2).rounded()
      for (v, size) in row {
        v.frame = CGRect(x: x, y: (top - height + (height - size.height) / 2).rounded(), width: size.width, height: size.height)
        x += size.width + gap
      }
      top -= height + gap
    }
  }
}
