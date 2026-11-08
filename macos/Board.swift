import AppKit
import CoreText

/// Chalk colors on the tray, left to right.
let chalkColors: [NSColor] = [
  NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1), NSColor(srgbRed: 0.97, green: 0.86, blue: 0.42, alpha: 1),
  NSColor(srgbRed: 0.96, green: 0.66, blue: 0.73, alpha: 1), NSColor(srgbRed: 0.62, green: 0.83, blue: 0.94, alpha: 1),
  NSColor(srgbRed: 0.73, green: 0.89, blue: 0.63, alpha: 1),
]

/// Small, fast, repeatable random numbers, so a stroke redraws the same grain after an undo.
struct ChalkRandom {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
}

enum ChalkMark {
  case stroke(points: [CGPoint], color: Int, width: CGFloat, seed: UInt64)
  case text(String, at: CGPoint, color: Int, size: CGFloat, seed: UInt64, font: Int)
  case erase(points: [CGPoint], width: CGFloat)
}

enum BoardTool { case chalk, text, eraser }

/// Board lettering, all SIL OFL 1.1 and bundled with the app: Nanum Pen Script, Nanum Gothic Bold, Nanum Myeongjo Bold.
/// Each covers Korean and English. `scale` evens out the sizes, since handwriting runs small.
let chalkFonts: [(ko: String, en: String, name: String, file: String, scale: CGFloat)] = [
  ("손글씨", "Handwriting", "NanumPen", "NanumPenScript-Regular", 1),
  ("고딕", "Sans", "NanumGothicBold", "NanumGothic-Bold", 0.78),
  ("명조", "Serif", "NanumMyeongjoBold", "NanumMyeongjo-Bold", 0.78),
]
func chalkFont(_ size: CGFloat, style: Int = 0) -> NSFont {
  let entry = chalkFonts[chalkFonts.indices.contains(style) ? style : 0]
  let points = size * entry.scale
  if NSFont(name: entry.name, size: points) == nil, let url = Bundle.main.url(forResource: entry.file, withExtension: "ttf") {
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }
  return NSFont(name: entry.name, size: points) ?? .systemFont(ofSize: size * 0.8, weight: .medium)
}

/// A green chalkboard in a wooden frame with a chalk tray. Draw, write Korean or English, erase, save.
final class BoardView: NSView, NSTextFieldDelegate {
  weak var controller: AppController?
  private(set) var marks: [ChalkMark] = []
  private var wiped: [ChalkMark]?
  var color = 0
  var thick = false
  /// Index into `chalkFonts` for new writing.
  var fontStyle = 0
  /// True while saving a PNG, so the tray buttons stay out of the picture.
  private var exporting = false
  var tool = BoardTool.chalk { didSet { finishText(); needsDisplay = true } }
  private var current: [CGPoint] = []
  private var currentSeed: UInt64 = 0
  private var ink: CGContext?
  private var surface: CGImage?
  private var editor: NSTextField?
  private var editorPoint = CGPoint.zero
  static let frameWidth: CGFloat = 22
  static let trayHeight: CGFloat = 76

  init(controller: AppController) {
    self.controller = controller
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  var boardRect: CGRect {
    CGRect(
      x: BoardView.frameWidth, y: BoardView.frameWidth, width: bounds.width - BoardView.frameWidth * 2,
      height: bounds.height - BoardView.frameWidth - BoardView.trayHeight)
  }
  var trayRect: CGRect { CGRect(x: 0, y: bounds.height - BoardView.trayHeight, width: bounds.width, height: BoardView.trayHeight) }
  var strokeWidth: CGFloat { thick ? 14 : 6 }
  var textSize: CGFloat { thick ? 84 : 56 }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    surface = nil
    ink = nil
    redrawInk()
  }

  // ---- Ink layer ----
  private func makeInk() -> CGContext? {
    let scale = window?.backingScaleFactor ?? 2
    let size = boardRect.size
    guard size.width > 10, size.height > 10,
      let ctx = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Board coordinates: origin at the board's top-left, y downward, in points.
    ctx.translateBy(x: 0, y: size.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    return ctx
  }
  func redrawInk() {
    ink = makeInk()
    guard let ink else { return }
    for mark in marks { render(mark, into: ink) }
    needsDisplay = true
  }
  private func render(_ mark: ChalkMark, into ctx: CGContext) {
    switch mark {
    case .stroke(let points, let color, let width, let seed):
      var random = ChalkRandom(state: seed)
      chalkLine(points, color: chalkColors[color], width: width, random: &random, into: ctx)
    case .text(let string, let at, let color, let size, let seed, let font):
      var random = ChalkRandom(state: seed)
      chalkText(string, at: at, color: chalkColors[color], font: chalkFont(size, style: font), random: &random, into: ctx)
    case .erase(let points, let width):
      ctx.saveGState()
      ctx.setBlendMode(.clear)
      ctx.setLineWidth(width)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      ctx.addLines(between: points.count == 1 ? [points[0], points[0]] : points)
      ctx.strokePath()
      ctx.restoreGState()
    }
  }
  /// Chalk is a spray of grains, denser in the middle, with gaps where the board's grain shows.
  private func chalkLine(_ points: [CGPoint], color: NSColor, width: CGFloat, random: inout ChalkRandom, into ctx: CGContext) {
    guard let first = points.first else { return }
    let path = points.count == 1 ? [first, first] : points
    for (a, b) in zip(path, path.dropFirst()) {
      let length = hypot(b.x - a.x, b.y - a.y)
      let steps = max(1, Int(length / max(1, width * 0.3)))
      for s in 0..<steps {
        let t = CGFloat(s) / CGFloat(steps)
        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        for _ in 0..<Int(width * 2.2) {
          if random.unit() < 0.18 { continue }
          let angle = random.unit() * .pi * 2
          let r = width * 0.5 * sqrt(random.unit())
          let grain = 0.5 + random.unit() * 1.6
          ctx.setFillColor(color.withAlphaComponent(0.25 + random.unit() * 0.6).cgColor)
          ctx.fill(CGRect(x: p.x + cos(angle) * r - grain / 2, y: p.y + sin(angle) * r - grain / 2, width: grain, height: grain))
        }
      }
    }
  }
  private func chalkText(_ string: String, at: CGPoint, color: NSColor, font: NSFont, random: inout ChalkRandom, into ctx: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.withAlphaComponent(0.93)]
    let text = string as NSString
    let box = text.size(withAttributes: attributes)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    // The view is flipped, so lines run top to bottom like typing.
    var y = at.y
    for line in string.components(separatedBy: "\n") {
      (line as NSString).draw(at: CGPoint(x: at.x, y: y), withAttributes: attributes)
      y += box.height / CGFloat(max(1, string.components(separatedBy: "\n").count))
    }
    NSGraphicsContext.current = previous
    // Rub some grains out so the letters look written in chalk.
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    let area = CGRect(x: at.x, y: at.y, width: box.width, height: box.height)
    for _ in 0..<Int(area.width * area.height * 0.06) {
      let grain = 0.6 + random.unit() * 1.4
      ctx.setFillColor(NSColor.black.withAlphaComponent(0.35 + random.unit() * 0.5).cgColor)
      ctx.fill(CGRect(x: area.minX + random.unit() * area.width, y: area.minY + random.unit() * area.height, width: grain, height: grain))
    }
    ctx.restoreGState()
  }

  // ---- Board surface, frame and tray ----
  private func makeSurface() -> CGImage? {
    let size = boardRect.size
    let scale: CGFloat = 1
    guard size.width > 10,
      let ctx = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(
      colorsSpace: space,
      colors: [CGColor(srgbRed: 0.20, green: 0.38, blue: 0.31, alpha: 1), CGColor(srgbRed: 0.15, green: 0.30, blue: 0.25, alpha: 1)] as CFArray,
      locations: [0, 1])!
    ctx.drawLinearGradient(
      base, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    var random = ChalkRandom(state: 7)
    // Old eraser smudges.
    for _ in 0..<Int(size.width * size.height / 26000) {
      let center = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
      let radius = 60 + random.unit() * 220
      let smudge = CGGradient(
        colorsSpace: space,
        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.035), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1])!
      ctx.saveGState()
      ctx.translateBy(x: center.x, y: center.y)
      ctx.scaleBy(x: 1.6, y: 0.7)
      ctx.drawRadialGradient(smudge, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
      ctx.restoreGState()
    }
    // Fine dust.
    for _ in 0..<Int(size.width * size.height / 220) {
      ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.02 + random.unit() * 0.04))
      ctx.fill(CGRect(x: random.unit() * size.width, y: random.unit() * size.height, width: 1.2, height: 1.2))
    }
    return ctx.makeImage()
  }
  private func wood(_ rect: CGRect, light: CGFloat, radius: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(
      starting: NSColor(srgbRed: 0.55 * light, green: 0.33 * light, blue: 0.18 * light, alpha: 1),
      ending: NSColor(srgbRed: 0.40 * light, green: 0.22 * light, blue: 0.11 * light, alpha: 1))?.draw(in: path, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    var random = ChalkRandom(state: UInt64(rect.minY + 3))
    NSColor(srgbRed: 0.30, green: 0.16, blue: 0.08, alpha: 0.25).setStroke()
    for i in 0..<Int(rect.height / 4) {
      let y = rect.minY + CGFloat(i) * 4 + random.unit() * 2
      let grain = NSBezierPath()
      grain.move(to: CGPoint(x: rect.minX, y: y))
      grain.curve(
        to: CGPoint(x: rect.maxX, y: y + random.unit() * 3),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.3, y: y + random.unit() * 4 - 2),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.7, y: y + random.unit() * 4 - 2))
      grain.lineWidth = 0.6
      grain.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
  }
  /// Tray buttons after the five chalk sticks.
  var trayItems: [(id: String, title: String, rect: CGRect)] {
    let titles: [(String, String)] = [
      ("thick", thick ? tr("굵게", "Thick") : tr("가늘게", "Thin")), ("text", tr("글씨", "Text")),
      ("font", tr(chalkFonts[fontStyle].ko, chalkFonts[fontStyle].en)), ("eraser", tr("지우개", "Eraser")),
      ("undo", tr("되돌리기", "Undo")), ("wipe", tr("모두 지우기", "Wipe")), ("save", tr("PNG 저장", "Save PNG")), ("close", tr("닫기", "Close")),
    ]
    var x = bounds.width - 18
    var result: [(String, String, CGRect)] = []
    for (id, title) in titles.reversed() {
      let width = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold)]).width + 30
      x -= width
      result.append((id, title, CGRect(x: x, y: trayRect.minY + 20, width: width, height: 40)))
      x -= 8
    }
    return result.reversed().map { (id: $0.0, title: $0.1, rect: $0.2) }
  }
  func chalkRect(_ i: Int) -> CGRect {
    CGRect(x: 40 + CGFloat(i) * 70, y: trayRect.minY + (i == color && tool == .chalk ? 24 : 32), width: 54, height: 16)
  }
  override func draw(_ dirtyRect: NSRect) {
    wood(bounds, light: 1, radius: 14)
    let board = boardRect
    if surface == nil { surface = makeSurface() }
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    NSColor.black.withAlphaComponent(0.4).setFill()
    board.insetBy(dx: -2, dy: -2).fill()
    if let surface {
      cg.saveGState()
      cg.translateBy(x: board.minX, y: board.maxY)
      cg.scaleBy(x: 1, y: -1)
      cg.draw(surface, in: CGRect(origin: .zero, size: board.size))
      cg.restoreGState()
    }
    if let image = ink?.makeImage() {
      cg.saveGState()
      cg.translateBy(x: board.minX, y: board.maxY)
      cg.scaleBy(x: 1, y: -1)
      cg.draw(image, in: CGRect(origin: .zero, size: board.size))
      cg.restoreGState()
    }
    // Tray ledge with a little dust.
    wood(trayRect.insetBy(dx: 6, dy: 4), light: 1.15, radius: 8)
    NSColor.white.withAlphaComponent(0.08).setFill()
    NSBezierPath(roundedRect: CGRect(x: 30, y: trayRect.minY + 44, width: 380, height: 10), xRadius: 5, yRadius: 5).fill()
    for (i, chalk) in chalkColors.enumerated() {
      let r = chalkRect(i)
      if i == color && tool == .chalk {
        chalk.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: -5, dy: -5), xRadius: 10, yRadius: 10).fill()
      }
      chalk.setFill()
      NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
      NSColor.black.withAlphaComponent(0.12).setFill()
      NSBezierPath(roundedRect: CGRect(x: r.minX, y: r.midY + 2, width: r.width, height: r.height / 2 - 2), xRadius: 5, yRadius: 5).fill()
    }
    for item in trayItems where !exporting {
      let selected = (item.id == "text" && tool == .text) || (item.id == "eraser" && tool == .eraser) || (item.id == "thick" && thick)
      (selected ? NSColor.white.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.22)).setFill()
      NSBezierPath(roundedRect: item.rect, xRadius: 10, yRadius: 10).fill()
      let style = NSMutableParagraphStyle()
      style.alignment = .center
      (item.title as NSString).draw(
        in: item.rect.offsetBy(dx: 0, dy: 10),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 15, weight: .bold), .paragraphStyle: style,
          .foregroundColor: selected ? NSColor(srgbRed: 0.25, green: 0.15, blue: 0.08, alpha: 1) : NSColor.white.withAlphaComponent(0.92),
        ])
    }
  }

  // ---- Input ----
  private func boardPoint(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    return CGPoint(x: p.x - boardRect.minX, y: p.y - boardRect.minY)
  }
  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if trayRect.contains(p) {
      trayClick(p)
      return
    }
    guard boardRect.contains(p) else { return }
    let b = boardPoint(event)
    switch tool {
    case .text:
      if editor != nil { finishText() } else { beginText(at: b) }
    case .chalk, .eraser:
      finishText()
      current = [b]
      currentSeed = UInt64(Date().timeIntervalSince1970 * 1000) ^ UInt64(marks.count) << 32
      extend(to: b)
    }
  }
  override func mouseDragged(with event: NSEvent) {
    guard !current.isEmpty else { return }
    extend(to: boardPoint(event))
  }
  override func mouseUp(with event: NSEvent) {
    guard !current.isEmpty else { return }
    commitStroke()
  }
  /// Draws only the newest piece, so long strokes stay smooth.
  private func extend(to p: CGPoint) {
    guard let ink else { return }
    let last = current.last ?? p
    if current.count > 1, hypot(p.x - last.x, p.y - last.y) < 1.5 { return }
    if current.count > 1 || last != p { current.append(p) }
    let piece = [last, p]
    if tool == .eraser {
      render(.erase(points: piece, width: strokeWidth * 5), into: ink)
    } else {
      var random = ChalkRandom(state: currentSeed &+ UInt64(current.count))
      chalkLine(piece, color: chalkColors[color], width: strokeWidth, random: &random, into: ink)
    }
    needsDisplay = true
  }
  private func commitStroke() {
    let points = current
    current = []
    if tool == .eraser {
      marks.append(.erase(points: points, width: strokeWidth * 5))
    } else {
      marks.append(.stroke(points: points, color: color, width: strokeWidth, seed: currentSeed))
    }
    wiped = nil
    // Redraw once with the stroke's own grain, so undo and redraw look the same.
    redrawInk()
  }
  /// For the self-test: a whole stroke in board coordinates.
  func drawStroke(_ points: [CGPoint]) {
    current = [points[0]]
    currentSeed = 42
    for p in points { extend(to: p) }
    commitStroke()
  }
  private func trayClick(_ p: CGPoint) {
    for i in chalkColors.indices where chalkRect(i).insetBy(dx: -6, dy: -10).contains(p) {
      color = i
      tool = .chalk
      return
    }
    guard let item = trayItems.first(where: { $0.rect.contains(p) }) else { return }
    switch item.id {
    case "thick": thick.toggle(); needsDisplay = true
    case "text": tool = tool == .text ? .chalk : .text
    case "font":
      // Next lettering style; writing starts right away in it.
      fontStyle = (fontStyle + 1) % chalkFonts.count
      tool = .text
    case "eraser": tool = tool == .eraser ? .chalk : .eraser
    case "undo": undo()
    case "wipe": wipe()
    case "save": controller?.saveBoard()
    default: controller?.closeBoard()
    }
  }
  func undo() {
    finishText()
    if let wiped {
      marks = wiped
      self.wiped = nil
    } else if !marks.isEmpty {
      marks.removeLast()
    }
    redrawInk()
  }
  func wipe() {
    finishText()
    guard !marks.isEmpty else { return }
    wiped = marks
    marks = []
    redrawInk()
  }

  // ---- Text (any input method, so Korean works) ----
  private func beginText(at p: CGPoint) {
    let field = NSTextField(string: "")
    field.font = chalkFont(textSize, style: fontStyle)
    field.textColor = chalkColors[color]
    field.drawsBackground = false
    field.isBordered = false
    field.focusRingType = .none
    field.placeholderString = tr("여기에 쓰고 Enter", "Type, then Enter")
    field.delegate = self
    field.target = self
    field.action = #selector(textEntered)
    field.cell?.sendsActionOnEndEditing = false
    let height = textSize * 1.35
    field.frame = CGRect(x: boardRect.minX + p.x, y: boardRect.minY + p.y, width: max(240, boardRect.maxX - boardRect.minX - p.x - 20), height: height)
    addSubview(field)
    editor = field
    editorPoint = p
    window?.makeFirstResponder(field)
  }
  @objc private func textEntered() { finishText() }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(cancelOperation(_:)) {
      editor?.stringValue = ""
      finishText()
      return true
    }
    return false
  }
  /// Writes whatever is in the text box onto the board in chalk.
  func finishText() {
    guard let field = editor else { return }
    editor = nil
    let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    field.removeFromSuperview()
    window?.makeFirstResponder(self)
    guard !string.isEmpty else { return }
    writeText(string, at: editorPoint)
  }
  func writeText(_ string: String, at p: CGPoint) {
    marks.append(.text(string, at: p, color: color, size: textSize, seed: UInt64(marks.count + 1) &* 7919, font: fontStyle))
    wiped = nil
    redrawInk()
  }
  var isEditingText: Bool { editor != nil }
  /// The board in its frame with the chalk ledge, without the tray buttons.
  func pngData() -> Data? {
    finishText()
    exporting = true
    defer {
      exporting = false
      needsDisplay = true
    }
    guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    cacheDisplay(in: bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { controller?.closeBoard() } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { undo() } else { super.keyDown(with: event) }
  }
  /// Fraction of the board covered by chalk in `rect` (board coordinates), for the self-test.
  func inkCoverage(in rect: CGRect) -> Double {
    guard let image = ink?.makeImage(), let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
    let scale = CGFloat(image.width) / boardRect.width
    var covered = 0
    var total = 0
    for y in stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 2) {
      for x in stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 2) {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
        total += 1
        // Row 0 is the top of the board: the ink context draws with y downward.
        if bytes[y * image.bytesPerRow + x * 4 + 3] > 20 { covered += 1 }
      }
    }
    return total == 0 ? 0 : Double(covered) / Double(total)
  }
}

/// The board window takes the keyboard, so Korean and English input methods work in it.
final class BoardWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

extension AppController {
  func openBoard() {
    finishStrokes()
    pen = false
    zoom = false
    capture.stop()
    capturedDisplay = nil
    magnifiedImage = nil
    hideToolPanels()
    let visible = (toolbar.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    boardWindow.setFrame(visible.insetBy(dx: 16, dy: 16), display: true)
    takeFocus()
    boardWindow.makeKeyAndOrderFront(nil)
    boardWindow.makeFirstResponder(boardView)
    refreshTools()
    invalidateAll()
  }
  func closeBoard() {
    boardView.finishText()
    boardWindow.orderOut(nil)
    refreshTools()
    giveFocusBack()
  }
  /// Saves the board with its frame as a PNG beside the other captures.
  @discardableResult func saveBoard() -> URL? {
    guard let png = boardView.pngData() else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let url = capturesFolder.appendingPathComponent("YelPoint-board-\(formatter.string(from: Date())).png")
    do {
      try FileManager.default.createDirectory(at: capturesFolder, withIntermediateDirectories: true)
      try png.write(to: url)
      toast(tr("칠판을 PNG로 저장했어요 · ", "Board saved as PNG · ") + storage.capturesLabel)
      return url
    } catch {
      showMessage(tr("저장하지 못했어요", "Could not save"), error.localizedDescription)
      return nil
    }
  }
}
