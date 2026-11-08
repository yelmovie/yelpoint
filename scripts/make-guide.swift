// Renders the YelPoint usage video. Layout numbers match macos/Toolbar.swift.
// Usage: make-guide <out.mp4> [--windows]   |   make-guide --sheet <out.png> [--windows]
import AVFoundation
import AppKit
import CoreImage
import CoreText

let W: CGFloat = 1280
let H: CGFloat = 720
let fps = 30
let args = CommandLine.arguments
let onWindows = args.contains("--windows")
let english = args.contains("--english")
func T(_ korean: String, _ other: String) -> String { english ? other : korean }
let ctrlName = onWindows ? "Ctrl" : "Control"
let comboName = onWindows ? "Ctrl+Alt" : "Control+Option"
let passName = onWindows ? "Alt" : "Option"
let scrollName = onWindows ? T("휠", "wheel") : T("스크롤", "scroll")

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let dock = NSColor(srgbRed: 0.125, green: 0.17, blue: 0.145, alpha: 1)
let lime = NSColor(srgbRed: 0.84, green: 0.94, blue: 0.67, alpha: 1)
let paper = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)
let red = NSColor(srgbRed: 0.90, green: 0.12, blue: 0.12, alpha: 1)
let inks = [rgb(0xED684F), rgb(0x3179DD), rgb(0x259567)]
let deskTop = rgb(0xDCE6F2)
let deskBottom = rgb(0xC4D3E6)
let slate = rgb(0x24303F)
let muted = rgb(0x5B6B7E)

// Nanum Gothic is SIL OFL, so the rendered video may ship on any platform.
func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
  let heavy = weight == .bold || weight == .semibold
  guard let font = NSFont(name: heavy ? "NanumGothicBold" : "NanumGothic", size: size) else {
    fatalError("Nanum Gothic is not available")
  }
  return font
}

// Motion tokens from the design skill: ease-out to enter, ease-in-out to travel.
func unit(_ x: Double) -> Double { min(1, max(0, x)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - unit(x), 4) }
func easeInOut(_ x: Double) -> Double {
  let v = unit(x)
  return v < 0.5 ? 4 * v * v * v : 1 - pow(-2 * v + 2, 3) / 2
}
func enter(_ t: Double, _ start: Double, _ duration: Double = 0.25) -> CGFloat {
  CGFloat(easeOut((t - start) / duration))
}
func mix(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }
func mix(_ a: CGPoint, _ b: CGPoint, _ p: CGFloat) -> CGPoint {
  CGPoint(x: mix(a.x, b.x, p), y: mix(a.y, b.y, p))
}

var ctx: CGContext!

func fill(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
  color.setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func oval(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor) {
  color.setFill()
  NSBezierPath(
    ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
  ).fill()
}
func ring(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor, _ width: CGFloat) {
  color.setStroke()
  let path = NSBezierPath(
    ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
  path.lineWidth = width
  path.stroke()
}
enum Align { case left, center, right }
@discardableResult func text(
  _ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
  color: NSColor = slate, align: Align = .left, mono: Bool = false
) -> CGFloat {
  let font = uiFont(size, weight)
  let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
  let measured = string.size(withAttributes: attributes)
  let left = align == .left ? x : align == .center ? x - measured.width / 2 : x - measured.width
  string.draw(at: CGPoint(x: left, y: y - measured.height / 2), withAttributes: attributes)
  return measured.width
}
/// Drawn here on an 18-unit grid. SF Symbols may not ship in a video, least of all a Windows one.
func symbol(_ name: String, _ rect: CGRect, _ color: NSColor) {
  let unit = min(rect.width, rect.height) / 18
  ctx.saveGState()
  ctx.translateBy(x: rect.midX - 9 * unit, y: rect.midY - 9 * unit)
  ctx.scaleBy(x: unit, y: unit)
  color.setStroke()
  color.setFill()
  func stroke(_ path: NSBezierPath) {
    path.lineWidth = 1.6
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
  }
  func poly(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for p in points.dropFirst() { path.line(to: CGPoint(x: p.0, y: p.1)) }
    if closed { path.close() }
    return path
  }
  func line(_ points: (CGFloat, CGFloat)...) { stroke(poly(points)) }
  func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: x, y: y, width: w, height: h))
  }
  func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(rect: CGRect(x: x, y: y, width: w, height: h))
  }
  func corners() {
    line((2, 6), (2, 2), (6, 2))
    line((12, 2), (16, 2), (16, 6))
    line((16, 12), (16, 16), (12, 16))
    line((6, 16), (2, 16), (2, 12))
  }
  switch name {
  case "cursorarrow", "cursorarrow.rays":
    poly([(4, 2), (4, 15), (7.5, 12), (10, 17), (12, 16), (9.6, 11), (14, 11)], closed: true).fill()
  case "magnifyingglass":
    stroke(round(2.5, 2.5, 10, 10))
    line((11.5, 11.5), (16, 16))
  case "pencil":
    stroke(poly([(3, 15), (4, 11), (12, 3), (15, 6), (7, 14)], closed: true))
    line((10.5, 4.5), (13.5, 7.5))
  case "timer":
    stroke(round(2.5, 3.5, 13, 13))
    line((9, 10), (9, 6.5))
    line((7, 1.5), (11, 1.5))
  case "camera.viewfinder":
    corners()
    stroke(round(6, 6, 6, 6))
  case "viewfinder": corners()
  case "circle.dashed":
    let dashed = round(2, 2, 14, 14)
    dashed.setLineDash([3, 2.5], count: 2, phase: 0)
    stroke(dashed)
  case "slider.horizontal.3":
    for (i, x) in [CGFloat(5), 11, 7].enumerated() {
      let y = 4 + CGFloat(i) * 5
      line((2, y), (16, y))
      round(x - 2, y - 2, 4, 4).fill()
    }
  case "eye.slash":
    stroke(round(2, 5, 14, 8))
    stroke(round(7, 7, 4, 4))
    line((3, 15), (15, 3))
  case "arrow.uturn.backward":
    line((7, 3), (3, 7), (7, 11))
    line((3, 7), (12, 7), (15, 10), (12, 14), (7, 14))
  case "trash":
    stroke(box(5, 5, 8, 11))
    line((3, 4), (15, 4))
    line((7, 2), (11, 2))
  case "play.fill": poly([(5, 3), (15, 9), (5, 15)], closed: true).fill()
  case "pause.fill":
    box(4, 3, 4, 12).fill()
    box(10, 3, 4, 12).fill()
  case "arrow.counterclockwise":
    let arc = NSBezierPath()
    arc.appendArc(
      withCenter: CGPoint(x: 9, y: 10), radius: 6, startAngle: 300, endAngle: 240, clockwise: true)
    stroke(arc)
    line((12, 1.5), (12, 5.5), (16, 5.5))
  case "doc.on.clipboard":
    stroke(box(4, 4, 10, 12))
    stroke(box(7, 2, 4, 3))
  case "square.and.arrow.down":
    line((9, 2), (9, 11))
    line((5, 7), (9, 11), (13, 7))
    line((3, 12), (3, 16), (15, 16), (15, 12))
  case "record.circle":
    stroke(round(2, 2, 14, 14))
    round(6, 6, 6, 6).fill()
  case "stop.fill": box(4, 4, 10, 10).fill()
  case "rectangle": stroke(box(2, 4, 14, 10))
  case "circle": stroke(round(2, 2, 14, 14))
  case "checkmark.circle.fill":
    round(1.5, 1.5, 15, 15).fill()
    lime.setStroke()
    let tick = poly([(5, 9.5), (8, 12.5), (13, 6)], closed: false)
    tick.lineWidth = 2
    tick.stroke()
  case "oval": stroke(round(1, 4, 16, 10))
  case "xmark":
    line((4, 4), (14, 14))
    line((14, 4), (4, 14))
  case "checkmark": line((3, 9), (7, 13), (15, 5))
  case "textformat":
    line((3, 4), (15, 4))
    line((9, 4), (9, 15))
  case "arrow.up":
    line((9, 16), (9, 3))
    line((4, 8), (9, 3), (14, 8))
  case "arrow.down":
    line((9, 2), (9, 15))
    line((4, 10), (9, 15), (14, 10))
  case "phone":
    stroke(round(5, 1.5, 8, 15))
    line((8, 14), (10, 14))
  case "camera":
    stroke(box(1.5, 5, 15, 10))
    stroke(round(6, 7, 6, 6))
    line((6, 5), (7.5, 2.5), (10.5, 2.5), (12, 5))
  case "rotate":
    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: 9, y: 9), radius: 6, startAngle: 300, endAngle: 240, clockwise: false)
    stroke(arc)
    line((12, 1.5), (12.5, 4.5), (9.5, 5))
  case "light":
    stroke(poly([(5, 2), (13, 2), (12, 7), (11, 8), (11, 16), (7, 16), (7, 8), (6, 7)], closed: true))
    line((9, 10), (9, 12))
  case "captions.bubble":
    stroke(box(1.5, 3, 15, 11))
    line((4, 7.5), (8, 7.5))
    line((10, 7.5), (14, 7.5))
    line((4, 10.5), (11, 10.5))
  case "qrcode":
    for (x, y) in [(1.0, 1.0), (11.0, 1.0), (1.0, 11.0)] { stroke(box(CGFloat(x), CGFloat(y), 6, 6)) }
    for (x, y) in [(3.0, 3.0), (13.0, 3.0), (3.0, 13.0), (11.0, 11.0), (15.0, 11.0), (13.0, 13.0), (11.0, 15.0), (15.0, 15.0)] {
      box(CGFloat(x), CGFloat(y), 2, 2).fill()
    }
  case "board":
    stroke(box(1.5, 3, 15, 10))
    line((4, 7), (9, 7))
    line((4, 10), (12, 10))
    line((5, 15.5), (13, 15.5))
  case "power":
    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: 9, y: 10), radius: 6.5, startAngle: 300, endAngle: 240, clockwise: false)
    stroke(arc)
    line((9, 1.5), (9, 8.5))
  case "shield":
    stroke(poly([(9, 1.5), (16, 4), (15, 11), (9, 16.5), (3, 11), (2, 4)], closed: true))
    line((9, 5.5), (9, 10))
    round(8.1, 12, 1.8, 1.8).fill()
  case "school":
    stroke(poly([(1.5, 7.5), (9, 2), (16.5, 7.5)]))
    stroke(box(3.5, 7, 11, 9))
    stroke(box(7.5, 11, 3, 5))
  case "info":
    stroke(round(2, 2, 14, 14))
    line((9, 8), (9, 13))
    round(8.1, 4.6, 1.8, 1.8).fill()
  default: fatalError("no icon named \(name)")
  }
  ctx.restoreGState()
}
func alpha(_ value: CGFloat, _ body: () -> Void) {
  ctx.saveGState()
  ctx.setAlpha(value)
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)
  body()
  ctx.endTransparencyLayer()
  ctx.restoreGState()
}

// ---- The lesson slide every scene works on ----
let slideRect = CGRect(x: 60, y: 112, width: 1160, height: 452)
let planet = CGPoint(x: 880, y: 340)
func drawSlide() {
  fill(slideRect, .white, radius: 18)
  text(T("태양계 행성", "The Solar System"), 110, 170, size: 40, weight: .bold)
  text(T("지구는 태양에서 세 번째 행성입니다.", "Earth is the third planet from the Sun."), 110, 244, size: 24)
  text(T("물이 액체로 있어 생명이 살 수 있습니다.", "Liquid water lets life thrive here."), 110, 290, size: 24)
  text(T("달은 지구 둘레를 한 달에 한 번 돕니다.", "The Moon circles Earth about once a month."), 110, 336, size: 24)
  text(T("참고: 지구 지름 12,742km · 달까지 거리 384,400km", "Note: Earth diameter 12,742 km · Distance to Moon 384,400 km"), 110, 400, size: 14, color: muted)
  text(T("공전 주기 365.25일 · 자전 주기 23시간 56분", "Orbit 365.25 days · Rotation 23 h 56 min"), 110, 424, size: 14, color: muted)
  rgb(0xB9C8DA).setStroke()
  for radius in [CGFloat(90), 150] {
    let orbit = NSBezierPath(
      ovalIn: CGRect(
        x: planet.x - radius, y: planet.y - radius, width: radius * 2, height: radius * 2))
    orbit.lineWidth = 2
    orbit.stroke()
  }
  oval(planet, 44, rgb(0xF2B84B))
  oval(CGPoint(x: planet.x + 90, y: planet.y), 16, rgb(0x3179DD))
  oval(CGPoint(x: planet.x - 106, y: planet.y - 106), 22, rgb(0x7FB7A6))
  text(T("태양", "Sun"), planet.x, planet.y, size: 16, weight: .bold, color: slate, align: .center)
  text(T("지구", "Earth"), planet.x + 90, planet.y + 30, size: 14, color: muted, align: .center)
}
func drawDesk() {
  NSGradient(starting: deskTop, ending: deskBottom)?.draw(
    in: CGRect(x: 0, y: 0, width: W, height: H), angle: 90)
  drawSlide()
}

// ---- Toolbar and panels ----
let toolbarOrigin = CGPoint(x: (W - 866) / 2, y: H - 74)
let tools: [(id: String, title: String, symbol: String, x: CGFloat, w: CGFloat)] = [
  ("highlight", T("강조", "Highlight"), "cursorarrow", 20, 84), ("zoom", T("돋보기", "Zoom"), "magnifyingglass", 106, 86),
  ("pen", T("펜", "Pen"), "pencil", 194, 64), ("timer", T("타이머", "Timer"), "timer", 260, 86),
  ("capture", T("캡처", "Capture"), "camera.viewfinder", 348, 88), ("spot", T("스팟", "Spot"), "circle.dashed", 438, 76),
  ("phone", T("폰", "Phone"), "phone", 516, 70),
  ("qr", "QR", "qrcode", 588, 60), ("board", T("칠판", "Board"), "board", 650, 70),
  ("settings", "", "slider.horizontal.3", 732, 38), ("hide", "", "eye.slash", 772, 38),
  ("quit", "", "power", 812, 38),
]
func tool(_ id: String) -> CGPoint {
  let item = tools.first { $0.id == id }!
  let iconOnly = item.title.isEmpty
  return CGPoint(x: toolbarOrigin.x + item.x + item.w / 2, y: toolbarOrigin.y + (iconOnly ? 21 : 28))
}
func button(
  _ rect: CGRect, title: String, symbolName: String, selected: Bool, pressed: CGFloat = 0
) {
  ctx.saveGState()
  let scale = 1 - 0.03 * pressed
  ctx.translateBy(x: rect.midX, y: rect.midY)
  ctx.scaleBy(x: scale, y: scale)
  ctx.translateBy(x: -rect.midX, y: -rect.midY)
  if selected { fill(rect.insetBy(dx: 1, dy: 1), lime, radius: 11) }
  let color = selected ? dock : paper
  let font = uiFont(13, .medium)
  let width = title.size(withAttributes: [.font: font]).width
  let total = 18 + (title.isEmpty ? 0 : width + 7)
  let left = rect.midX - total / 2
  symbol(symbolName, CGRect(x: left, y: rect.midY - 9, width: 18, height: 18), color)
  if !title.isEmpty {
    text(title, left + 25, rect.midY, size: 13, weight: .medium, color: color)
  }
  ctx.restoreGState()
}
func drawToolbar(selected: Set<String> = [], pressed: [String: CGFloat] = [:], titles: [String: String] = [:], reveal: CGFloat = 1) {
  let frame = CGRect(origin: toolbarOrigin, size: CGSize(width: 866, height: 56))
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: rgb(0x000000, 0.28).cgColor)
  fill(frame, dock, radius: 18)
  ctx.restoreGState()
  for (i, item) in tools.enumerated() {
    let appear = reveal >= 1 ? 1 : CGFloat(easeOut(Double(reveal) * 8 - Double(i) * 0.8))
    alpha(appear) {
      button(
        CGRect(x: frame.minX + item.x, y: frame.minY + (item.title.isEmpty ? 4 : 6) + (1 - appear) * 12, width: item.w, height: item.title.isEmpty ? 34 : 44),
        title: titles[item.id] ?? item.title, symbolName: item.symbol,
        selected: selected.contains(item.id), pressed: pressed[item.id] ?? 0)
    }
  }
  fill(CGRect(x: frame.minX + 726, y: frame.minY + 17, width: 1, height: 22), rgb(0xFFFFFF, 0.18))
  // © mark centered under the power button, as in the app.
  text("© yelsam.lab", frame.minX + 829, frame.minY + 46, size: 10, weight: .semibold, color: rgb(0xFFFFFF, 0.72), align: .center)
}
func panelFrame(_ width: CGFloat) -> CGRect {
  CGRect(x: (W - width) / 2, y: toolbarOrigin.y - 57, width: width, height: 48)
}
func panel(_ width: CGFloat, opened: Double, closed: Double = .infinity, at t: Double, _ body: (CGRect) -> Void) {
  guard t >= opened, t < closed else { return }
  let p = enter(t, opened)
  let frame = panelFrame(width)
  alpha(p) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: (1 - p) * 16)
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 14, color: rgb(0x000000, 0.25).cgColor)
    fill(frame, dock, radius: 14)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: 0, y: (1 - p) * 16)
    body(frame)
    ctx.restoreGState()
  }
}

// ---- Pointer ----
typealias Key = (t: Double, p: CGPoint)
func pointer(_ keys: [Key], _ t: Double) -> CGPoint {
  guard let first = keys.first else { return .zero }
  if t <= first.t { return first.p }
  for (a, b) in zip(keys, keys.dropFirst()) where t < b.t {
    return mix(a.p, b.p, CGFloat(easeInOut((t - a.t) / (b.t - a.t))))
  }
  return keys.last!.p
}
func drawCursor(_ p: CGPoint) {
  let points: [(CGFloat, CGFloat)] = [
    (0, 0), (0, 22), (5.4, 17), (9.6, 26), (13, 24.4), (8.8, 15.6), (16, 15.6),
  ]
  let path = NSBezierPath()
  path.move(to: CGPoint(x: p.x, y: p.y))
  for (x, y) in points.dropFirst() { path.line(to: CGPoint(x: p.x + x, y: p.y + y)) }
  path.close()
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: rgb(0x000000, 0.35).cgColor)
  NSColor.black.setFill()
  path.fill()
  ctx.restoreGState()
  NSColor.white.setStroke()
  path.lineWidth = 1.5
  path.stroke()
}
func clickRing(_ p: CGPoint, _ t: Double, at start: Double, _ color: NSColor = lime) {
  guard t >= start, t < start + 0.45 else { return }
  let q = CGFloat((t - start) / 0.45)
  ring(p, 10 + q * 26, color.withAlphaComponent(0.9 * (1 - q)), 3)
}
func press(_ t: Double, at start: Double) -> CGFloat {
  guard t >= start, t < start + 0.15 else { return 0 }
  return 1
}
func tag(_ string: String, _ center: CGPoint, _ t: Double, from: Double, to: Double, color: NSColor = dock) {
  guard t >= from, t < to else { return }
  let p = min(enter(t, from), 1 - enter(t, to - 0.15, 0.15))
  alpha(p) {
    let width = (string as NSString).size(
      withAttributes: [.font: uiFont(17, .semibold)]
    ).width + 28
    let rect = CGRect(
      x: center.x - width / 2, y: center.y - 18 + (1 - p) * 10, width: width, height: 36)
    fill(rect, color, radius: 12)
    text(string, rect.midX, rect.midY, size: 17, weight: .semibold, color: paper, align: .center)
  }
}
func toast(_ string: String, _ t: Double, from: Double, to: Double) {
  let width = (string as NSString).size(
    withAttributes: [.font: uiFont(20, .medium)]
  ).width + 32
  // Top right, clear of the toolbar, which now spans most of the bottom edge.
  tagBox(string, CGRect(x: W - width - 40, y: 34, width: width, height: 44), t, from: from, to: to)
}
func tagBox(_ string: String, _ rect: CGRect, _ t: Double, from: Double, to: Double) {
  guard t >= from, t < to else { return }
  let p = min(enter(t, from), 1 - enter(t, to - 0.15, 0.15))
  alpha(p) {
    fill(rect, dock, radius: 12)
    text(string, rect.minX + 16, rect.midY, size: 20, weight: .medium, color: paper)
  }
}
@discardableResult func chip(_ string: String, _ right: CGFloat, _ y: CGFloat) -> CGFloat {
  let width = (string as NSString).size(
    withAttributes: [.font: uiFont(18, .semibold)]
  ).width + 26
  let rect = CGRect(x: right - width, y: y, width: width, height: 38)
  fill(rect, .white, radius: 10)
  dock.setStroke()
  let outline = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
  outline.lineWidth = 2
  outline.stroke()
  text(string, rect.midX, rect.midY, size: 18, weight: .semibold, align: .center)
  return width
}
func wheelImage(_ diameter: Int) -> NSImage {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: diameter, pixelsHigh: diameter, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: diameter * 4, bitsPerPixel: 32)!
  let radius = Double(diameter) / 2
  for y in 0..<diameter {
    for x in 0..<diameter {
      let dx = Double(x) + 0.5 - radius
      let dy = radius - Double(y) - 0.5
      let distance = hypot(dx, dy)
      var hue = atan2(dy, dx) / (2 * .pi)
      if hue < 0 { hue += 1 }
      let edge = min(1, max(0, radius - distance))
      let color = NSColor(
        hue: hue, saturation: min(1, distance / radius), brightness: 1, alpha: 1
      ).usingColorSpace(.deviceRGB)!
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      color.getRed(&r, green: &g, blue: &b, alpha: nil)
      let i = (y * diameter + x) * 4
      rep.bitmapData![i] = UInt8(r * 255 * edge)
      rep.bitmapData![i + 1] = UInt8(g * 255 * edge)
      rep.bitmapData![i + 2] = UInt8(b * 255 * edge)
      rep.bitmapData![i + 3] = UInt8(255 * edge)
    }
  }
  let image = NSImage(size: CGSize(width: diameter, height: diameter))
  image.addRepresentation(rep)
  return image
}
let wheel = wheelImage(336)
func drawWheel(_ rect: CGRect) {
  wheel.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

// ---- Scenes ----
struct Scene {
  let title: String
  let line: String
  let duration: Double
  let draw: (Double) -> Void
}
func outline(_ rect: CGRect, oval isOval: Bool, drawn: CGFloat = 1) {
  let path =
    isOval
    ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
  red.setStroke()
  path.lineWidth = 3
  if drawn < 1 {
    let flat = path.flattened
    var length: CGFloat = 0
    var points: [NSPoint] = [NSPoint](repeating: .zero, count: 3)
    var last = NSPoint.zero
    for i in 0..<flat.elementCount {
      let kind = flat.element(at: i, associatedPoints: &points)
      if kind != .moveTo { length += hypot(points[0].x - last.x, points[0].y - last.y) }
      last = points[0]
    }
    path.setLineDash([length * drawn, length], count: 2, phase: 0)
  }
  path.stroke()
}

let intro = Scene(title: "", line: "", duration: 3.5) { t in
  drawDesk()
  fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x1E2A38, 0.72 * (1 - enter(t, 2.9, 0.4))))
  alpha(1 - enter(t, 2.9, 0.3)) {
    let words = [T("수업", "Highlight"), T("화면을", "your"), T("바로", "lesson"), T("강조하는", "screen"), T("도구", "instantly")]
    let p = enter(t, 0.1, 0.4)
    alpha(p) {
      text("YelPoint", W / 2, 270 + (1 - p) * 24, size: 84, weight: .bold, color: .white, align: .center)
    }
    var x: CGFloat = W / 2 - (english ? 232 : 215)
    for (i, word) in words.enumerated() {
      let q = enter(t, 0.6 + Double(i) * 0.08, 0.25)
      alpha(q) {
        x += text(word, x, 352 + (1 - q) * 16, size: 30, weight: .medium, color: lime) + 12
      }
    }
  }
  drawToolbar(reveal: CGFloat(unit((t - 1.0) / 1.0)))
}

let highlight = Scene(title: T("강조", "Highlight"), line: T("커서 주변을 표시하고, 왼쪽·오른쪽 클릭을 색으로 보여 드립니다", "Marks the pointer and shows left and right clicks in color"), duration: 6) { t in
  let keys: [Key] = [
    (0, CGPoint(x: 700, y: 430)), (0.9, tool("highlight")), (1.9, CGPoint(x: 340, y: 250)),
    (3.3, CGPoint(x: 340, y: 250)), (3.9, CGPoint(x: 700, y: 300)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  if t >= 0.9 { oval(p, 20, NSColor.systemYellow.withAlphaComponent(0.34)) }
  if t >= 2.5, t < 3.05 {
    let q = CGFloat((t - 2.5) / 0.55)
    ring(p, 15 + q * 30, NSColor.systemOrange.withAlphaComponent(0.85 * (1 - q)), 3)
  }
  if t >= 4.5, t < 5.05 {
    let q = CGFloat((t - 4.5) / 0.55)
    ring(p, 15 + q * 30, NSColor.systemBlue.withAlphaComponent(0.85 * (1 - q)), 3)
  }
  drawToolbar(selected: t >= 0.9 ? ["highlight"] : [], pressed: ["highlight": press(t, at: 0.9)])
  clickRing(tool("highlight"), t, at: 0.9)
  tag(T("왼쪽 클릭 = 주황", "Left click = orange"), CGPoint(x: 340, y: 195), t, from: 2.5, to: 3.6, color: rgb(0xC9681C))
  tag(T("오른쪽 클릭 = 파랑", "Right click = blue"), CGPoint(x: 700, y: 245), t, from: 4.5, to: 5.7, color: rgb(0x2F66B8))
  drawCursor(p)
}

let zoomScene = Scene(title: T("돋보기", "Zoom"), line: T("배율을 고르고 작은 글씨 위로 가져가면 크게 보입니다", "Choose a level and hover small text to enlarge it live"), duration: 6) { t in
  let bar = panelFrame(286)
  let level = CGPoint(x: bar.minX + 8 + 54 * 2.5, y: bar.midY)
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 480)), (0.8, tool("zoom")), (1.4, level), (2.3, CGPoint(x: 170, y: 402)),
    (3.9, CGPoint(x: 400, y: 402)), (4.8, CGPoint(x: 300, y: 426)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  if t >= 1.7 {
    let q = enter(t, 1.7, 0.3)
    let size = CGSize(width: 340, height: 196)
    let lens = CGRect(
      x: min(W - size.width - 20, p.x + 30), y: max(120, p.y - size.height - 24), width: size.width,
      height: size.height)
    ctx.saveGState()
    ctx.translateBy(x: lens.midX, y: lens.midY)
    ctx.scaleBy(x: 0.95 + 0.05 * q, y: 0.95 + 0.05 * q)
    ctx.translateBy(x: -lens.midX, y: -lens.midY)
    alpha(q) {
      ctx.saveGState()
      NSBezierPath(roundedRect: lens, xRadius: 17, yRadius: 17).addClip()
      fill(lens, .white)
      ctx.translateBy(x: lens.midX, y: lens.midY)
      ctx.scaleBy(x: 3, y: 3)
      ctx.translateBy(x: -p.x, y: -p.y)
      drawSlide()
      ctx.restoreGState()
      lime.setStroke()
      let border = NSBezierPath(roundedRect: lens, xRadius: 17, yRadius: 17)
      border.lineWidth = 3
      border.stroke()
    }
    ctx.restoreGState()
  }
  drawToolbar(selected: t >= 0.8 ? ["zoom", "highlight"] : ["highlight"], pressed: ["zoom": press(t, at: 0.8)])
  panel(286, opened: 0.8, at: t) { frame in
    for (i, label) in ["1.5×", "2×", "3×", "4×", "5×"].enumerated() {
      let cell = CGRect(x: frame.minX + 8 + CGFloat(i) * 54, y: frame.minY + 7, width: 54, height: 34)
      let picked = i == (t >= 1.4 ? 2 : 1)
      if picked { fill(cell, lime, radius: 10) }
      text(label, cell.midX, cell.midY, size: 13, weight: .semibold, color: picked ? dock : paper, align: .center)
    }
  }
  clickRing(tool("zoom"), t, at: 0.8)
  clickRing(level, t, at: 1.4)
  tag(T("배율 선택", "Choose a level"), CGPoint(x: level.x, y: bar.minY - 26), t, from: 1.4, to: 2.3)
  drawCursor(p)
}

let penWidth: CGFloat = 407
func drawPenBar(_ frame: CGRect, width: CGFloat, custom: Bool, wheelPressed: CGFloat) {
  for i in 0..<3 {
    oval(CGPoint(x: frame.minX + 24 + CGFloat(i) * 35, y: frame.midY), 11, inks[i])
  }
  let wheelRect = CGRect(x: frame.minX + 115, y: frame.minY + 10.5, width: 27, height: 27)
  drawWheel(wheelRect.insetBy(dx: wheelPressed, dy: wheelPressed))
  oval(CGPoint(x: wheelRect.midX, y: wheelRect.midY), 6, custom ? red : inks[0])
  ring(
    CGPoint(x: frame.minX + (custom ? 128.5 : 24), y: frame.midY), 16, lime, 1)
  let start = frame.minX + 166
  let end = frame.minX + 266
  fill(CGRect(x: start, y: frame.midY - 1.5, width: end - start, height: 3), rgb(0xFFFFFF, 0.3), radius: 1.5)
  let x = start + (width - 1) / 29 * (end - start)
  oval(CGPoint(x: x, y: frame.midY), max(6, width / 2), custom ? red : inks[0])
  ring(CGPoint(x: x, y: frame.midY), max(6, width / 2), paper, 2)
  text(String(Int(width.rounded())), frame.minX + 296, frame.midY, size: 13, weight: .semibold, color: paper, align: .right, mono: true)
  symbol("arrow.uturn.backward", CGRect(x: frame.minX + 326, y: frame.midY - 8, width: 18, height: 16), rgb(0xFFFFFF, 0.8))
  symbol("trash", CGRect(x: frame.minX + 371, y: frame.midY - 8, width: 18, height: 16), rgb(0xFFFFFF, 0.8))
}
let penScene = Scene(title: T("펜", "Pen"), line: T("색상환으로 색을 고르고, 슬라이더를 끌어 굵기를 맞춥니다", "Pick any color on the wheel and drag the slider for width"), duration: 8) { t in
  let bar = panelFrame(penWidth)
  let wheelButton = CGPoint(x: bar.minX + 128.5, y: bar.midY)
  let wheelPick = CGPoint(x: W / 2 + 80, y: bar.minY - 142)
  let sliderStart = CGPoint(x: bar.minX + 176, y: bar.midY)
  let sliderEnd = CGPoint(x: bar.minX + 216, y: bar.midY)
  func stroke(_ q: Double) -> CGPoint {
    let angle = -2.6 + q * 6.0
    return CGPoint(x: 268 + 176 * cos(angle), y: 168 + 46 * sin(angle))
  }
  let drawStart = 4.5
  let drawEnd = 6.2
  var keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.8, tool("pen")), (1.5, wheelButton), (2.2, wheelButton),
    (2.6, wheelPick), (3.0, wheelPick), (3.25, sliderStart), (3.4, sliderStart), (3.95, sliderEnd),
    (4.3, stroke(0)),
  ]
  keys.append((drawStart, stroke(0)))
  let drawing = t >= drawStart && t <= drawEnd
  let q = unit((t - drawStart) / (drawEnd - drawStart))
  let p = drawing ? stroke(easeInOut(q)) : t > drawEnd ? stroke(1) : pointer(keys, t)
  let custom = t >= 2.75
  let width: CGFloat = t < 3.4 ? 4 : mix(4, 12, CGFloat(easeInOut((t - 3.4) / 0.55)))
  drawDesk()
  if t >= drawStart {
    let path = NSBezierPath()
    path.lineWidth = 12
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: stroke(0))
    let steps = Int(easeInOut(q) * 90)
    if steps > 0 { for i in 1...steps { path.line(to: stroke(Double(i) / 90)) } }
    red.setStroke()
    path.stroke()
  }
  drawToolbar(selected: t >= 0.8 ? ["pen"] : ["highlight"], pressed: ["pen": press(t, at: 0.8)])
  panel(penWidth, opened: 0.8, at: t) { frame in
    drawPenBar(frame, width: width, custom: custom, wheelPressed: press(t, at: 1.5) * 1)
  }
  if t >= 1.55, t < 3.05 {
    let open = enter(t, 1.55)
    let close = 1 - enter(t, 2.85, 0.15)
    alpha(min(open, close)) {
      let rect = CGRect(x: W / 2 - 98, y: bar.minY - 240, width: 196, height: 232)
      ctx.saveGState()
      ctx.translateBy(x: rect.midX, y: rect.maxY)
      ctx.scaleBy(x: 0.95 + 0.05 * open, y: 0.95 + 0.05 * open)
      ctx.translateBy(x: -rect.midX, y: -rect.maxY)
      fill(rect, dock, radius: 16)
      drawWheel(CGRect(x: rect.minX + 14, y: rect.minY + 14, width: 168, height: 168))
      NSGradient(starting: .black, ending: red)?.draw(
        in: NSBezierPath(
          roundedRect: CGRect(x: rect.minX + 14, y: rect.minY + 198, width: 168, height: 18),
          xRadius: 9, yRadius: 9), angle: 0)
      if t >= 2.6 { ring(wheelPick, 7, .white, 2) }
      ctx.restoreGState()
    }
  }
  clickRing(tool("pen"), t, at: 0.8)
  clickRing(wheelButton, t, at: 1.5)
  clickRing(wheelPick, t, at: 2.6)
  tag(T("빨강 선택", "Red picked"), CGPoint(x: W / 2 + 190, y: bar.minY - 142), t, from: 2.6, to: 3.2)
  tag(T("끌어서 굵기 조절", "Drag for width"), CGPoint(x: bar.minX + 216, y: bar.minY - 26), t, from: 3.35, to: 4.3)
  tag(T("\(passName) 키를 누르는 동안은 필기 대신 클릭이 통과합니다", "Hold \(passName) to click through instead of drawing"), CGPoint(x: 640, y: 520), t, from: 6.4, to: 7.9)
  drawCursor(p)
}

func timerBadge(_ string: String, alert: Bool, _ appear: CGFloat) {
  alpha(appear) {
    let rect = CGRect(x: W - 220, y: 18 - (1 - appear) * 12, width: 196, height: 76)
    fill(rect, alert ? inks[0] : dock, radius: 16)
    text(string, rect.midX, rect.midY, size: 40, weight: .semibold, color: paper, align: .center, mono: true)
  }
}
let timerScene = Scene(title: T("타이머", "Timer"), line: T("1~60분을 맞추면 남은 시간이 화면 오른쪽 위에 표시됩니다", "Set 1 to 60 minutes and the time left shows at the top right"), duration: 7) { t in
  let bar = panelFrame(388)
  let ten = CGPoint(x: bar.minX + 195, y: bar.midY)
  let play = CGPoint(x: bar.minX + 321, y: bar.midY)
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.8, tool("timer")), (1.5, ten), (2.2, play), (3.0, CGPoint(x: 720, y: 460)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  drawToolbar(selected: t >= 0.8 ? ["timer"] : ["highlight"], pressed: ["timer": press(t, at: 0.8)])
  panel(388, opened: 0.8, at: t) { frame in
    text("−", frame.minX + 23, frame.midY, size: 15, weight: .medium, color: t >= 2.2 ? rgb(0xFFFFFF, 0.35) : paper, align: .center)
    text(t >= 1.5 ? T("10분", "10 min") : T("5분", "5 min"), frame.minX + 66, frame.midY, size: 14, weight: .semibold, color: paper, align: .center)
    text("+", frame.minX + 109, frame.midY, size: 15, weight: .medium, color: t >= 2.2 ? rgb(0xFFFFFF, 0.35) : paper, align: .center)
    for (i, value) in [5, 10, 30, 60].enumerated() {
      text(String(value), frame.minX + 155 + CGFloat(i) * 40, frame.midY, size: 14, weight: .medium, color: t >= 2.2 ? rgb(0xFFFFFF, 0.35) : paper, align: .center)
    }
    symbol(t >= 2.2 ? "pause.fill" : "play.fill", CGRect(x: frame.minX + 312, y: frame.midY - 9, width: 18, height: 18), paper)
    symbol("arrow.counterclockwise", CGRect(x: frame.minX + 352, y: frame.midY - 9, width: 18, height: 18), paper)
  }
  clickRing(tool("timer"), t, at: 0.8)
  clickRing(ten, t, at: 1.5)
  clickRing(play, t, at: 2.2)
  if t >= 2.2 {
    let elapsed: Double
    if t < 3.6 {
      elapsed = t - 2.2
    } else {
      elapsed = 1.4 + easeInOut((t - 3.6) / 1.3) * (600 - 1.4)
    }
    if t < 4.9 {
      let left = Int(max(0, 600 - elapsed).rounded(.up))
      timerBadge(String(format: "%02d:%02d", left / 60, left % 60), alert: false, enter(t, 2.2))
    } else {
      timerBadge(T("시간 끝!", "Time's up!"), alert: Int((t - 4.9) * 2) % 2 == 0, 1)
    }
  }
  tag(T("빨리 감기", "Fast forward"), CGPoint(x: W - 122, y: 118), t, from: 3.6, to: 4.9)
  tag(T("끝나면 소리와 함께 깜빡입니다", "It chimes and flashes at the end"), CGPoint(x: W - 180, y: 118), t, from: 5.0, to: 6.8)
  drawCursor(p)
}

let selection = CGRect(x: 716, y: 170, width: 330, height: 330)
func drawCrop(in rect: CGRect) {
  ctx.saveGState()
  NSBezierPath(rect: rect).addClip()
  ctx.translateBy(x: rect.minX, y: rect.minY)
  ctx.scaleBy(x: rect.width / selection.width, y: rect.height / selection.height)
  ctx.translateBy(x: -selection.minX, y: -selection.minY)
  drawSlide()
  ctx.restoreGState()
}
let captureScene = Scene(title: T("캡처", "Capture"), line: T("영역을 끌어 복사하고, 화면에 붙이고, 저장하고, 녹화합니다", "Drag to copy an area, paste it on screen, save, and record"), duration: 9) { t in
  let bar = panelFrame(516)
  func item(_ i: Int) -> CGPoint { CGPoint(x: bar.minX + 58 + CGFloat(i) * 100, y: bar.midY) }
  let dragStart = CGPoint(x: selection.minX, y: selection.minY)
  let dragEnd = CGPoint(x: selection.maxX, y: selection.maxY)
  let stickerFrom = CGPoint(x: 340, y: 330)
  let stickerTo = CGPoint(x: 470, y: 300)
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.7, tool("capture")), (1.0, tool("capture")), (1.8, dragStart),
    (2.0, dragStart), (2.9, dragEnd), (3.6, item(1)), (4.1, item(1)), (4.5, stickerFrom),
    (4.7, stickerFrom), (5.4, stickerTo), (5.9, item(2)), (6.6, item(2)), (6.9, item(3)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  let selecting = t >= 0.7 && t < 3.0
  if t >= 3.9 {
    let pop = enter(t, 3.9, 0.3)
    let center = t < 4.7 ? stickerFrom : mix(stickerFrom, stickerTo, CGFloat(easeInOut((t - 4.7) / 0.7)))
    let size: CGFloat = 240 * (0.95 + 0.05 * pop)
    let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    alpha(pop) {
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0x000000, 0.3).cgColor)
      fill(rect, .white)
      ctx.restoreGState()
      drawCrop(in: rect)
      lime.setStroke()
      let border = NSBezierPath(rect: rect)
      border.lineWidth = 2
      border.stroke()
      oval(CGPoint(x: rect.maxX - 16, y: rect.minY + 16), 12, dock)
      text("✕", rect.maxX - 16, rect.minY + 16, size: 12, color: paper, align: .center)
      // The labelled buttons that ride under every pinned capture, as in the app.
      let bar = CGRect(x: rect.minX, y: rect.maxY + 6, width: 418, height: 44)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgb(0x000000, 0.25).cgColor)
      fill(bar, dock, radius: 12)
      ctx.restoreGState()
      let barItems: [(String, String)] = [
        (T("복사됨", "Copied"), "checkmark"), (T("저장", "Save"), "square.and.arrow.down"), (T("글자", "Text"), "textformat"),
        (T("붙여넣기", "Paste"), "doc.on.clipboard"), (T("닫기", "Close"), "xmark"),
      ]
      for (i, entry) in barItems.enumerated() {
        button(CGRect(x: bar.minX + 4 + CGFloat(i) * 82, y: bar.minY + 2, width: 82, height: 40), title: entry.0, symbolName: entry.1, selected: i == 0)
      }
    }
  }
  if selecting {
    let shade = NSBezierPath(rect: CGRect(x: 0, y: 0, width: W, height: H))
    var box: CGRect?
    if t >= 2.0 {
      let corner = t < 2.9 ? p : dragEnd
      box = CGRect(x: dragStart.x, y: dragStart.y, width: corner.x - dragStart.x, height: corner.y - dragStart.y)
      shade.append(NSBezierPath(rect: box!))
    }
    shade.windingRule = .evenOdd
    rgb(0x000000, 0.28).setFill()
    shade.fill()
    if let box {
      lime.setStroke()
      let line = NSBezierPath(rect: box)
      line.lineWidth = 2
      line.stroke()
    }
  }
  if t >= 2.95, t < 3.2 {
    fill(selection, rgb(0xFFFFFF, 0.85 * (1 - CGFloat((t - 2.95) / 0.25))))
  }
  let recording = t >= 6.9
  drawToolbar(
    selected: t >= 0.7 ? ["capture"] : ["highlight"], pressed: ["capture": press(t, at: 0.7)],
    titles: recording ? ["capture": T("녹화중", "Recording")] : [:])
  panel(516, opened: 3.0, at: t) { frame in drawCaptureBar(frame, t, recording: recording) }
  clickRing(tool("capture"), t, at: 0.7)
  tag(T("캡처를 누르면 바로 영역 지정 · 한 번 클릭하면 메뉴", "Capture goes straight to choosing an area · click once for the menu"), CGPoint(x: 640, y: 150), t, from: 0.8, to: 2.8)
  clickRing(item(1), t, at: 3.8)
  clickRing(item(2), t, at: 5.9)
  clickRing(item(3), t, at: 6.9)
  toast(T("캡처해서 복사했습니다 · ⌘V로 바로 붙여넣기", "Captured and copied · paste with ⌘V"), t, from: 3.0, to: 4.6)
  tag(T("아래 버튼으로 저장 · 글자 · 붙여넣기 · 닫기, 끌어서 옮기고 필기도 합니다", "Buttons below: save, text, paste, close · drag it and write on it"), CGPoint(x: 470, y: 150), t, from: 4.7, to: 5.8)
  toast(T("저장했습니다", "Saved"), t, from: 5.95, to: 6.8)
  toast(T("녹화 시작 · 마이크 켜짐", "Recording · Mic on"), t, from: 7.0, to: 8.8)
  tag(onWindows ? T("녹화를 마치면 자막: 영상을 보며 자막을 넣고 SRT로 저장", "After recording: add subtitles while watching, save as SRT") : T("녹화를 마치면 자막: 영상 아래 칸에 쓰고 Enter (말소리 자동 초안도 가능)", "After recording: type subtitles under the video and press Enter (or draft from speech)"), CGPoint(x: 640, y: 150), t, from: 7.2, to: 8.95)
  drawCursor(p)
}
func drawCaptureBar(_ frame: CGRect, _ t: Double, recording: Bool) {
  let items: [(String, String)] = [
    (T("다시 캡처", "Capture"), "viewfinder"), (T("그림 붙이기", "Paste"), "doc.on.clipboard"), (T("PNG 저장", "Save PNG"), "square.and.arrow.down"),
    (recording ? T("녹화 정지", "Stop") : T("화면 녹화", "Record"), recording ? "stop.fill" : "record.circle"),
    (T("내 영상", "My Videos"), "captions.bubble"),
  ]
  for (i, entry) in items.enumerated() {
    button(
      CGRect(x: frame.minX + 8 + CGFloat(i) * 100, y: frame.minY + 4, width: 100, height: 40),
      title: entry.0, symbolName: entry.1, selected: i == 3 && recording)
  }
}

func drawSpotBar(_ frame: CGRect, selected: Int) {
  let items: [(String, String)] = [
    (T("사각", "Rect"), "rectangle"), (T("원", "Circle"), "circle"), (T("타원", "Ellipse"), "oval"), (T("끄기", "Off"), "xmark"),
  ]
  for (i, entry) in items.enumerated() {
    button(
      CGRect(x: frame.minX + 8 + CGFloat(i) * 86, y: frame.minY + 4, width: 86, height: 40),
      title: entry.0, symbolName: entry.1, selected: i == selected)
  }
}
let spotScene = Scene(title: T("스팟", "Spot"), line: T("사각·원·타원으로 끌면 빨간 선이 남습니다. 선을 끌면 크기가 바뀝니다", "Drag a shape to leave a red line. Drag the line to resize"), duration: 8.5) { t in
  let bar = panelFrame(360)
  func item(_ i: Int) -> CGPoint { CGPoint(x: bar.minX + 51 + CGFloat(i) * 86, y: bar.midY) }
  let start = CGPoint(x: 100, y: 214)
  let end = CGPoint(x: 490, y: 306)
  let rim = CGPoint(x: 490, y: 260)
  let rimTo = CGPoint(x: 590, y: 260)
  let inside = CGPoint(x: 330, y: 260)
  let insideTo = CGPoint(x: 330, y: 306)
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.7, tool("spot")), (1.3, item(2)), (1.8, start), (2.0, start),
    (2.9, end), (3.2, rim), (3.4, rim), (4.0, rimTo), (4.4, inside), (4.6, inside), (5.1, insideTo),
    (5.6, item(0)), (6.2, item(0)), (6.7, CGPoint(x: 660, y: 520)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  var rect = CGRect(x: start.x, y: start.y, width: 0, height: 0)
  if t >= 2.0 {
    let corner = t < 2.9 ? p : end
    rect.size = CGSize(width: corner.x - start.x, height: corner.y - start.y)
  }
  if t >= 3.4 { rect.size.width += 100 * CGFloat(easeInOut((t - 3.4) / 0.6)) }
  if t >= 4.6 { rect.origin.y += 46 * CGFloat(easeInOut((t - 4.6) / 0.5)) }
  if t >= 2.0 { outline(rect, oval: t < 5.6) }
  drawToolbar(selected: t >= 0.7 ? ["spot"] : ["highlight"], pressed: ["spot": press(t, at: 0.7)])
  panel(360, opened: 0.7, at: t) { frame in
    drawSpotBar(frame, selected: t < 1.3 ? -1 : t < 5.6 ? 2 : t < 6.7 ? 0 : -1)
  }
  clickRing(tool("spot"), t, at: 0.7)
  clickRing(item(2), t, at: 1.3)
  clickRing(item(0), t, at: 5.6)
  clickRing(CGPoint(x: 660, y: 520), t, at: 6.7)
  tag(T("끌어서 그리기", "Drag to draw"), CGPoint(x: 300, y: 370), t, from: 2.0, to: 3.0)
  tag(T("선을 끌면 크기 조절", "Drag the line to resize"), CGPoint(x: 660, y: 200), t, from: 3.3, to: 4.2)
  tag(T("안쪽을 끌면 이동", "Drag inside to move"), CGPoint(x: 420, y: 440), t, from: 4.5, to: 5.3)
  tag(T("도형 버튼으로 모양 변경", "Change the shape with its button"), CGPoint(x: 640, y: 520), t, from: 5.6, to: 6.5)
  tag(T("바깥을 클릭하면 완료됩니다. 아래 앱을 그대로 쓸 수 있습니다", "Click outside to finish. The app below keeps working"), CGPoint(x: 640, y: 480), t, from: 6.8, to: 8.3)
  drawCursor(p)
}

func mouseIcon(_ center: CGPoint, _ t: Double, up: Bool) {
  let rect = CGRect(x: center.x - 34, y: center.y - 50, width: 68, height: 100)
  fill(rect, .white, radius: 32)
  dock.setStroke()
  let body = NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32)
  body.lineWidth = 3
  body.stroke()
  let shift = CGFloat(sin(t * 9)) * 5
  fill(CGRect(x: center.x - 5, y: center.y - 36 + shift, width: 10, height: 24), red, radius: 5)
  symbol(
    up ? "arrow.up" : "arrow.down",
    CGRect(x: center.x + 48, y: center.y - 22 + (up ? -abs(shift) : abs(shift)), width: 36, height: 44), red)
}
let sizeScene = Scene(title: T("크기 조절", "Resize"), line: T("\(ctrlName)을 누른 채 \(scrollName)을 위로 하면 커지고, 아래로 하면 작아집니다", "Hold \(ctrlName) and \(scrollName) up for larger, down for smaller"), duration: 7) { t in
  drawDesk()
  let grow = CGFloat(easeInOut((t - 0.8) / 1.5))
  let shrink = CGFloat(easeInOut((t - 3.0) / 1.5))
  let scale = 1 + 0.5 * grow - 0.8 * shrink
  let base = CGSize(width: 230, height: 120)
  let center = CGPoint(x: 300, y: 270)
  let size = CGSize(width: base.width * scale, height: base.height * scale)
  outline(
    CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
    oval: true)
  if t < 5 {
    mouseIcon(CGPoint(x: 640, y: 350), t, up: t < 2.8)
    tag(t < 2.8 ? T("위로 = 크게", "Up = larger") : T("아래로 = 작게", "Down = smaller"), CGPoint(x: 640, y: 450), t, from: 0.3, to: 4.9)
  }
  tag(T("순서: 스팟 → 주변 어둡게 원 → 포인터", "Order: spot → dim circle → pointer"), CGPoint(x: 640, y: 510), t, from: 5.0, to: 6.9)
  drawToolbar(selected: ["highlight"])
  let keyWidth = chip(scrollName, W - 60, 40)
  text("+", W - 60 - keyWidth - 17, 59, size: 22, weight: .bold, align: .center)
  chip(ctrlName, W - 60 - keyWidth - 34, 40)
}

func drawStandingToolbar(_ origin: CGPoint) {
  let frame = CGRect(origin: origin, size: CGSize(width: 92, height: 536))
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: rgb(0x000000, 0.28).cgColor)
  fill(frame, dock, radius: 18)
  ctx.restoreGState()
  for (i, item) in tools.prefix(9).enumerated() {
    button(
      CGRect(x: frame.minX + 6, y: frame.minY + 16 + CGFloat(i) * 45, width: 80, height: 43),
      title: item.title, symbolName: item.symbol, selected: item.id == "highlight")
  }
  fill(CGRect(x: frame.minX + 12, y: frame.minY + 424, width: 68, height: 1), rgb(0xFFFFFF, 0.18))
  button(
    CGRect(x: frame.minX + 6, y: frame.minY + 430, width: 38, height: 40), title: "",
    symbolName: "slider.horizontal.3", selected: false)
  button(
    CGRect(x: frame.minX + 48, y: frame.minY + 430, width: 38, height: 40), title: "",
    symbolName: "eye.slash", selected: false)
  button(
    CGRect(x: frame.minX + 27, y: frame.minY + 476, width: 38, height: 38), title: "",
    symbolName: "power", selected: false)
  text("© yelsam.lab", frame.minX + 46, frame.minY + 522, size: 10, weight: .semibold, color: rgb(0xFFFFFF, 0.72), align: .center)
}
let barScene = Scene(title: T("도구막대", "Toolbar"), line: T("끌면 어디든 옮겨지고, 양쪽 끝에서는 세로로 서고, 눈 버튼으로 숨길 수 있습니다", "Drag it anywhere. It stands up at the sides. The eye button hides it"), duration: 9) { t in
  let lift: CGFloat = -440
  let grip = CGPoint(x: toolbarOrigin.x + 12, y: toolbarOrigin.y + 34)
  let raised = CGPoint(x: grip.x, y: grip.y + lift)
  let eye = CGPoint(x: tool("hide").x, y: tool("hide").y + lift)
  let mini = CGPoint(x: toolbarOrigin.x + 23, y: toolbarOrigin.y + 34 + lift)
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.7, grip), (0.9, grip), (2.0, raised), (2.8, eye), (3.1, eye),
    (3.8, mini), (4.6, mini), (5.1, raised), (5.3, raised), (6.5, CGPoint(x: 24, y: raised.y + 150)),
    (7.3, CGPoint(x: 400, y: 420)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  if t >= 6.5 {
    alpha(enter(t, 6.5)) { drawStandingToolbar(CGPoint(x: 8, y: 100)) }
  } else if t < 3.1 || t >= 4.6 {
    ctx.saveGState()
    let across = CGFloat(easeInOut((t - 5.3) / 1.2))
    ctx.translateBy(x: (24 - grip.x) * across, y: lift * CGFloat(easeInOut((t - 0.9) / 1.1)) + 150 * across)
    drawToolbar(selected: ["highlight"], pressed: ["hide": press(t, at: 3.0)])
    ctx.restoreGState()
  } else {
    let q = enter(t, 3.1)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: rgb(0x000000, 0.28).cgColor)
    oval(mini, 23 * (0.95 + 0.05 * q), dock)
    ctx.restoreGState()
    symbol("cursorarrow.rays", CGRect(x: mini.x - 11, y: mini.y - 11, width: 22, height: 22), lime)
  }
  clickRing(eye, t, at: 3.0)
  clickRing(mini, t, at: 4.6)
  tag(T("막대를 끌면 위아래 좌우 어디든", "Drag the bar anywhere"), CGPoint(x: 640, y: 480), t, from: 0.9, to: 2.7)
  tag(T("눈 버튼 = 숨기기", "Eye button = hide"), CGPoint(x: 880, y: 330), t, from: 3.0, to: 4.4)
  tag(T("작은 동그라미를 누르면 다시 보입니다", "Click the dot to bring it back"), CGPoint(x: 560, y: 330), t, from: 4.6, to: 5.5)
  tag(T("숨겨도 필기·타이머·스팟은 그대로입니다", "Ink, timer and spot stay while hidden"), CGPoint(x: 640, y: 480), t, from: 3.2, to: 4.5)
  tag(T("왼쪽·오른쪽 끝에 닿으면 바로 세로로 섭니다", "Touch a side edge and it stands up"), CGPoint(x: 640, y: 480), t, from: 5.4, to: 8.9)
  drawCursor(p)
}

let outro = Scene(title: "", line: "", duration: 5) { t in
  drawDesk()
  fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x1E2A38, 0.82 * enter(t, 0, 0.4)))
  let rows: [(String, String)] = [
    ("1", T("강조", "Highlight")), ("2", T("돋보기", "Zoom")), ("3", T("펜", "Pen")), ("4", T("타이머", "Timer")), ("5", T("캡처", "Capture")), ("6", T("스팟", "Spot")),
  ]
  let head = enter(t, 0.2, 0.3)
  alpha(head) {
    text(T("단축키", "Shortcuts"), W / 2, 118 + (1 - head) * 16, size: 42, weight: .bold, color: .white, align: .center)
    text(T("\(comboName) + 숫자", "\(comboName) + number"), W / 2, 170 + (1 - head) * 16, size: 24, weight: .medium, color: lime, align: .center)
  }
  for (i, row) in rows.enumerated() {
    let q = enter(t, 0.5 + Double(i) * 0.08, 0.25)
    let column = CGFloat(i % 3)
    let line = CGFloat(i / 3)
    let rect = CGRect(x: 266 + column * 256, y: 224 + line * 106 + (1 - q) * 16, width: 236, height: 86)
    alpha(q) {
      fill(rect, rgb(0xFFFFFF, 0.1), radius: 16)
      oval(CGPoint(x: rect.minX + 44, y: rect.midY), 24, lime)
      text(row.0, rect.minX + 44, rect.midY, size: 24, weight: .bold, color: dock, align: .center)
      text(row.1, rect.minX + 84, rect.midY, size: 26, weight: .semibold, color: .white)
    }
  }
  let end = enter(t, 1.3, 0.3)
  alpha(end) {
    text(T("0 = 도구막대 숨기기 · Esc = 조작 모드로 돌아오기", "0 = hide toolbar · Esc = back to normal use"), W / 2, 490 + (1 - end) * 16, size: 28, weight: .semibold, color: .white, align: .center)
    text(T("© yelsam.lab · 전원 버튼 아래 ©를 누르면 블로그 둘러보기 · 제안하기", "© yelsam.lab · Click © under the power button for the blog or a suggestion"), W / 2, 560, size: 16, color: rgb(0xFFFFFF, 0.7), align: .center)
    text(T("글꼴: 나눔고딕 (SIL OFL)", "Font: Nanum Gothic (SIL OFL)"), W / 2, 584, size: 12, color: rgb(0xFFFFFF, 0.5), align: .center)
  }
  drawToolbar(selected: ["highlight"])
}


// ---- Android phone: screen, then the camera as a document camera ----
func drawPhoneBar(_ frame: CGRect, status: String, selected: Int, light: Bool) {
  text(status, frame.minX + 14, frame.minY + 19, size: 14, weight: .semibold, color: paper)
  let items: [(String, String)] = [
    (T("화면", "Screen"), "phone"), (T("카메라", "Camera"), "camera"), (T("회전", "Rotate"), "rotate"),
    (T("조명", "Light"), "light"), (T("멈춤", "Freeze"), "pause.fill"), (T("녹화", "Record"), "record.circle"),
    (T("끄기", "Close"), "xmark"),
  ]
  // The "open when plugged in" toggle, on: a lime pill as in the app.
  button(CGRect(x: frame.maxX - 200, y: frame.minY + 5, width: 190, height: 30), title: T("꽂으면 바로 띄우기", "Open when plugged in"), symbolName: "checkmark.circle.fill", selected: true)
  for (i, entry) in items.enumerated() {
    button(
      CGRect(x: frame.minX + 8 + CGFloat(i) * 86, y: frame.minY + 36, width: 84, height: 40),
      title: entry.0, symbolName: entry.1, selected: i == selected || (i == 3 && light))
  }
  button(CGRect(x: frame.minX + 606, y: frame.minY + 36, width: 128, height: 40), title: T("영상 가져오기", "Get Videos"), symbolName: "square.and.arrow.down", selected: false)
}
func phoneApps(_ rect: CGRect) {
  fill(rect, rgb(0x2F5E8C))
  NSGradient(starting: rgb(0x3E7CB8), ending: rgb(0x7B5FB2))?.draw(in: rect, angle: -60)
  text("10:24", rect.midX, rect.minY + 34, size: 26, weight: .bold, color: .white, align: .center)
  let colors = [0xF2B84B, 0x5CC48B, 0xED684F, 0x6FA8FF, 0xF7F7F2, 0xB07FE0, 0x4BC3C9, 0xFF9F5A]
  for i in 0..<8 {
    let x = rect.minX + 26 + CGFloat(i % 4) * ((rect.width - 52) / 3.6)
    let y = rect.minY + 90 + CGFloat(i / 4) * 66
    fill(CGRect(x: x, y: y, width: 40, height: 40), rgb(colors[i]), radius: 11)
  }
  fill(CGRect(x: rect.minX + 20, y: rect.maxY - 70, width: rect.width - 40, height: 44), rgb(0xFFFFFF, 0.2), radius: 22)
}
func notebookPage(_ rect: CGRect) {
  fill(rect, rgb(0xFBF8EE))
  rgb(0xA9C3E0).setStroke()
  var y = rect.minY + 40
  while y < rect.maxY - 10 {
    let l = NSBezierPath()
    l.move(to: CGPoint(x: rect.minX + 16, y: y))
    l.line(to: CGPoint(x: rect.maxX - 16, y: y))
    l.lineWidth = 1
    l.stroke()
    y += 30
  }
  text(T("3 × 4 = 12", "3 × 4 = 12"), rect.minX + 34, rect.minY + 55, size: 24, weight: .bold, color: rgb(0x2F3B4C))
  text(T("4 × 5 = 20", "4 × 5 = 20"), rect.minX + 34, rect.minY + 115, size: 24, weight: .bold, color: rgb(0x2F3B4C))
  text(T("6 × 7 = 43", "6 × 7 = 43"), rect.minX + 34, rect.minY + 175, size: 24, weight: .bold, color: rgb(0x2F3B4C))
  rgb(0x2F3B4C).setStroke()
  let tri = NSBezierPath()
  tri.move(to: CGPoint(x: rect.maxX - 120, y: rect.minY + 180))
  tri.line(to: CGPoint(x: rect.maxX - 60, y: rect.minY + 80))
  tri.line(to: CGPoint(x: rect.maxX - 30, y: rect.minY + 180))
  tri.close()
  tri.lineWidth = 3
  tri.stroke()
}
let phoneScene = Scene(title: T("폰 연결", "Phone"), line: T("안드로이드 폰·태블릿을 USB로 꽂으면 화면이 뜨고, 카메라는 실물화상기가 됩니다", "Plug in an Android phone or tablet to show its screen, or use its camera as a document camera"), duration: 13) { t in
  let barFrame = CGRect(x: (W - 790) / 2, y: toolbarOrigin.y - 95, width: 790, height: 86)
  func item(_ i: Int) -> CGPoint { CGPoint(x: barFrame.minX + 50 + CGFloat(i) * 86, y: barFrame.minY + 56) }
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.7, tool("phone")), (2.6, tool("phone")), (3.1, item(0)), (4.9, item(0)),
    (5.4, item(1)), (6.9, item(1)), (7.4, item(2)), (8.3, item(2)), (8.8, item(4)), (9.2, item(4)),
    (9.7, CGPoint(x: 818, y: 344)), (10.9, CGPoint(x: 818, y: 344)), (11.6, CGPoint(x: 900, y: 470)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  // The scrcpy window, drawn as YelPoint's floating phone window.
  let windowRect = CGRect(x: 700, y: 128, width: 440, height: 420)
  if t >= 3.0 {
    let q = enter(t, 3.0, 0.35)
    alpha(q) {
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: rgb(0x000000, 0.3).cgColor)
      fill(windowRect, rgb(0x1E2A38), radius: 12)
      ctx.restoreGState()
      let camera = t >= 5.3
      text(camera ? T("YelPoint · 실물화상기", "YelPoint · Document camera") : "YelPoint · Galaxy", windowRect.midX, windowRect.minY + 15, size: 12, weight: .medium, color: rgb(0xFFFFFF, 0.8), align: .center)
      let content = windowRect.insetBy(dx: 10, dy: 0).offsetBy(dx: 0, dy: 15).insetBy(dx: 0, dy: 20)
      ctx.saveGState()
      NSBezierPath(roundedRect: content, xRadius: 8, yRadius: 8).addClip()
      if camera {
        let turn = CGFloat(easeInOut((t - 7.4) / 0.6))
        ctx.translateBy(x: content.midX, y: content.midY)
        // Sideways at first; the Rotate button stands the page up.
        ctx.rotate(by: -.pi / 2 * (1 - turn))
        ctx.translateBy(x: -content.midX, y: -content.midY)
        fill(content.insetBy(dx: -80, dy: -80), rgb(0x8C6E52))
        notebookPage(content.insetBy(dx: 18, dy: 18))
      } else {
        let screen = CGRect(x: content.midX - 110, y: content.minY + 8, width: 220, height: content.height - 16)
        fill(content, rgb(0x111820))
        phoneApps(screen)
      }
      ctx.restoreGState()
      if t >= 8.9 {
        ring(CGPoint(x: content.midX, y: content.midY), 0, lime, 0)
        let border = NSBezierPath(roundedRect: content.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10)
        lime.setStroke()
        border.lineWidth = 4 * enter(t, 8.9, 0.2)
        border.stroke()
      }
      if t >= 9.7 {
        let q = CGFloat(easeInOut((t - 9.7) / 1.1))
        let circle = NSBezierPath()
        circle.appendArc(withCenter: CGPoint(x: 850, y: 356), radius: 36, startAngle: 200, endAngle: 200 - 360 * q, clockwise: true)
        red.setStroke()
        circle.lineWidth = 5
        circle.lineCapStyle = .round
        circle.stroke()
      }
    }
  }
  // Left: the phone on its cable.
  alpha(enter(t, 0.2, 0.4)) {
    let phone = CGRect(x: 150, y: 190, width: 120, height: 220)
    fill(phone, rgb(0x24303F), radius: 18)
    fill(phone.insetBy(dx: 8, dy: 14), rgb(0x3E7CB8), radius: 8)
    rgb(0x24303F).setStroke()
    let cable = NSBezierPath()
    cable.move(to: CGPoint(x: phone.midX, y: phone.maxY))
    cable.curve(to: CGPoint(x: 420, y: 560), controlPoint1: CGPoint(x: phone.midX, y: 500), controlPoint2: CGPoint(x: 300, y: 560))
    cable.lineWidth = 6
    cable.lineCapStyle = .round
    cable.stroke()
    text(T("USB 케이블", "USB cable"), 330, 520, size: 15, weight: .semibold, color: muted, align: .center)
  }
  if t >= 0.8 {
    let open = enter(t, 0.8)
    alpha(open) {
      ctx.saveGState()
      ctx.translateBy(x: 0, y: (1 - open) * 16)
      ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 14, color: rgb(0x000000, 0.25).cgColor)
      fill(barFrame, dock, radius: 14)
      ctx.restoreGState()
      ctx.saveGState()
      ctx.translateBy(x: 0, y: (1 - open) * 16)
      let status = t < 1.6 ? T("폰에 뜬 ‘USB 디버깅 허용’에서 ‘허용’을 눌러 주세요", "Tap Allow on the phone")
        : t < 3.0 ? T("Galaxy 연결됨 · 화면이나 카메라를 누르세요", "Galaxy connected · choose Screen or Camera")
        : t < 5.3 ? T("Galaxy 화면을 보여 주는 중입니다", "Showing Galaxy")
        : T("카메라를 실물화상기로 쓰는 중입니다", "Document camera on")
      drawPhoneBar(barFrame, status: status, selected: t >= 8.9 ? 4 : t >= 5.3 ? 1 : t >= 3.0 ? 0 : -1, light: false)
      ctx.restoreGState()
    }
  }
  drawToolbar(selected: ["highlight", "phone"], pressed: ["phone": press(t, at: 0.7)])
  clickRing(tool("phone"), t, at: 0.7)
  clickRing(item(0), t, at: 3.0)
  clickRing(item(1), t, at: 5.3)
  clickRing(item(2), t, at: 7.3)
  clickRing(item(4), t, at: 8.8)
  tag(T("처음 한 번: 폰 설정에서 ‘USB 디버깅’ 켜기", "First time only: turn on USB debugging"), CGPoint(x: 330, y: 150), t, from: 0.9, to: 5.2)
  tag(T("★ 폰마다 방법이 달라요 · ‘내 폰 이름 + USB 디버깅’ 검색", "★ Every phone differs · search “your phone + USB debugging”"), CGPoint(x: 330, y: 196), t, from: 1.2, to: 5.2, color: rgb(0xD9534F))
  tag(T("꽂으면 폰 화면이 바로 뜹니다", "The phone screen opens when you plug in"), CGPoint(x: 920, y: 100), t, from: 3.1, to: 5.2)
  tag(T("카메라 = 실물화상기 · 공책을 그대로 비춥니다", "Camera = document camera"), CGPoint(x: 920, y: 100), t, from: 5.4, to: 7.2)
  tag(T("회전 · 조명으로 맞춥니다", "Rotate and light to adjust"), CGPoint(x: 920, y: 100), t, from: 7.4, to: 8.7)
  tag(T("멈춤을 누르면 그 위에 바로 필기합니다", "Freeze, then write on it"), CGPoint(x: 920, y: 100), t, from: 8.9, to: 12.9)
  tag(T("녹화 = 폰 화면만 MP4로 저장", "Record = save just the phone as an MP4"), CGPoint(x: 920, y: 146), t, from: 10.0, to: 12.9)
  tag(T("영상 가져오기 = 폰 갤러리 영상을 원본 그대로 가져와 자막", "Get Videos = copy a gallery video and add subtitles"), CGPoint(x: 920, y: 192), t, from: 10.6, to: 12.9)
  drawCursor(p)
}

// ---- Chalkboard and QR code ----
// The app's chalk handwriting font (Nanum Pen Script, SIL OFL 1.1).
let chalkFontLoaded: Bool = {
  let root = ProcessInfo.processInfo.environment["YELPOINT_ROOT"] ?? FileManager.default.currentDirectoryPath
  return CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: root + "/vendor/fonts/NanumPenScript-Regular.ttf") as CFURL, .process, nil)
}()
let videoQR: NSImage? = {
  guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
  filter.setValue(Data("https://blog.naver.com/yelsam_lab".utf8), forKey: "inputMessage")
  filter.setValue("M", forKey: "inputCorrectionLevel")
  guard let code = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
    let cg = CIContext().createCGImage(code, from: code.extent)
  else { return nil }
  return NSImage(cgImage: cg, size: code.extent.size)
}()
func chalkGrains(_ from: CGPoint, _ to: CGPoint, _ q: CGFloat, color: NSColor, seed: Int) {
  var r = UInt64(seed)
  func unit() -> CGFloat { r = r &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(r >> 40) / CGFloat(1 << 24) }
  let steps = Int(hypot(to.x - from.x, to.y - from.y) / 2 * q)
  for s in 0..<max(0, steps) {
    let t = CGFloat(s) / max(1, CGFloat(steps)) * q
    let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    for _ in 0..<12 where unit() > 0.2 {
      let a = unit() * .pi * 2, d = 3.5 * sqrt(unit()), g = 0.6 + unit() * 1.5
      color.withAlphaComponent(0.3 + unit() * 0.6).setFill()
      CGRect(x: p.x + cos(a) * d, y: p.y + sin(a) * d, width: g, height: g).fill()
    }
  }
}
let boardScene = Scene(title: T("칠판 · QR", "Board · QR"), line: T("분필로 쓰는 큰 칠판, 주소를 넣으면 크게 뜨는 QR 코드", "A big chalkboard, and a big QR code from any address"), duration: 10) { t in
  let keys: [Key] = [
    (0, CGPoint(x: 640, y: 470)), (0.6, tool("board")), (1.4, CGPoint(x: 240, y: 250)), (3.0, CGPoint(x: 560, y: 260)),
    (3.4, CGPoint(x: 260, y: 360)), (5.2, CGPoint(x: 600, y: 360)), (5.7, tool("qr")), (7.0, CGPoint(x: 760, y: 610)), (9.9, CGPoint(x: 900, y: 470)),
  ]
  let p = pointer(keys, t)
  drawDesk()
  if t >= 0.7 && t < 5.6 {
    let open = enter(t, 0.7, 0.35)
    alpha(open) {
      let frame = CGRect(x: 54, y: 104, width: 1172, height: 482)
      fill(frame, rgb(0x7A4A2A), radius: 14)
      let board = frame.insetBy(dx: 18, dy: 18).offsetBy(dx: 0, dy: -18)
      NSGradient(starting: rgb(0x34614F), ending: rgb(0x264D40))?.draw(in: CGRect(x: board.minX, y: board.minY, width: board.width, height: board.height - 20), angle: -70)
      let tray = CGRect(x: frame.minX + 6, y: frame.maxY - 46, width: frame.width - 12, height: 40)
      fill(tray, rgb(0x8C5530), radius: 8)
      for (i, c) in [0xF5F2E8, 0xF7DB6B, 0xF5A8BA, 0x9ED4F0, 0xBAE3A1].enumerated() {
        fill(CGRect(x: tray.minX + 24 + CGFloat(i) * 64, y: tray.minY + (i == 0 ? 10 : 15), width: 50, height: 14), rgb(c), radius: 7)
      }
      for (i, title) in [T("글씨", "Text"), T("손글씨", "Handwriting"), T("지우개", "Eraser"), T("되돌리기", "Undo"), T("PNG 저장", "Save PNG"), T("닫기", "Close")].enumerated() {
        let r = CGRect(x: tray.maxX - 564 + CGFloat(i) * 94, y: tray.minY + 6, width: 86, height: 28)
        fill(r, rgb(0x000000, 0.22), radius: 9)
        text(title, r.midX, r.midY, size: 13, weight: .bold, color: rgb(0xFFFFFF, 0.92), align: .center)
      }
      chalkGrains(CGPoint(x: 240, y: 250), CGPoint(x: 560, y: 260), CGFloat(unit((t - 1.4) / 1.6)), color: rgb(0xF5F2E8), seed: 3)
      let write = CGFloat(unit((t - 3.4) / 1.8))
      if write > 0 {
        let words = T("지구는 태양을 돌아요", "Earth goes round the Sun")
        let shown = String(words.prefix(Int(CGFloat(words.count) * write + 0.5)))
        _ = chalkFontLoaded
        let font = NSFont(name: "NanumPen", size: 54) ?? uiFont(40, .bold)
        (shown as NSString).draw(at: CGPoint(x: 260, y: 330), withAttributes: [.font: font, .foregroundColor: rgb(0xF7DB6B, 0.95)])
      }
    }
  }
  if t >= 5.8 {
    panel(560, opened: 5.8, closed: 7.2, at: t) { frame in
      fill(CGRect(x: frame.minX + 12, y: frame.minY + 12, width: 392, height: 24), rgb(0xFFFFFF, 0.12), radius: 4)
      text("https://blog.naver.com/yelsam_lab", frame.minX + 20, frame.midY, size: 14, color: paper)
      button(CGRect(x: frame.minX + 412, y: frame.minY + 4, width: 100, height: 40), title: T("크게 보기", "Show"), symbolName: "qrcode", selected: false)
    }
    if t >= 7.1 {
      let q = enter(t, 7.1, 0.35)
      alpha(q) {
        let card = CGRect(x: 440, y: 112 + (1 - q) * 20, width: 400, height: 460)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: rgb(0x000000, 0.3).cgColor)
        fill(card, .white, radius: 22)
        ctx.restoreGState()
        NSGraphicsContext.current?.imageInterpolation = .none
        videoQR?.draw(in: CGRect(x: card.minX + 40, y: card.minY + 30, width: 320, height: 320))
        text("blog.naver.com/yelsam_lab", card.midX, card.maxY - 60, size: 20, weight: .semibold, color: dock, align: .center)
      }
    }
  }
  drawToolbar(selected: Set(["highlight"]).union(t >= 0.7 && t < 5.6 ? ["board"] : t >= 5.8 ? ["qr"] : []), pressed: ["board": press(t, at: 0.6), "qr": press(t, at: 5.7)])
  clickRing(tool("board"), t, at: 0.6)
  clickRing(tool("qr"), t, at: 5.7)
  tag(T("분필을 고르고 그리면 진짜 분필처럼 써집니다", "Pick a chalk and draw"), CGPoint(x: 640, y: 150), t, from: 1.3, to: 3.3)
  tag(T("글씨: 손글씨·고딕·명조, 한글·영어 모두", "Text: handwriting, sans or serif, Korean or English"), CGPoint(x: 640, y: 150), t, from: 3.4, to: 5.5)
  tag(T("주소를 넣고 Enter → 크게 뜹니다", "Type an address, press Enter"), CGPoint(x: 640, y: 92), t, from: 6.0, to: 9.9)
  drawCursor(p)
}

// 나눠 쓰기 전에 알아 둘 것: 첫 실행 경고, 학교 PC, 녹화, 책임 문구.
let noticeScene = Scene(title: "", line: "", duration: 10) { t in
  drawDesk()
  fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x1E2A38, 0.86 * enter(t, 0, 0.4)))
  let head = enter(t, 0.2, 0.3)
  alpha(head) {
    text(T("이용 안내", "Before You Use It"), W / 2, 92 + (1 - head) * 16, size: 40, weight: .bold, color: .white, align: .center)
    text(T("나눠 쓰기 전에 꼭 알아 두세요", "Good to know before you share it"), W / 2, 138 + (1 - head) * 16, size: 20, weight: .medium, color: lime, align: .center)
  }
  let firstRun: [String] = onWindows
    ? [T("‘Windows의 PC 보호’ 창이 뜨면", "On “Windows protected your PC”,"), T("‘추가 정보’ → ‘실행’을 눌러 주세요", "choose More info → Run anyway")]
    : [T("시스템 설정 → 개인정보 보호 및 보안에서", "Open System Settings → Privacy & Security"), T("‘그래도 열기’를 눌러 주세요", "and click Open Anyway")]
  let cards: [(String, String, [String])] = [
    ("shield", T("처음 실행할 때 경고가 뜨면", "If a warning appears at first launch"), firstRun),
    ("school", T("학교 PC에 설치할 때", "On school computers"), [T("설치 전에 학교 정보 담당 선생님께", "Check with your school’s IT staff"), T("확인해 주세요", "before installing")]),
    ("record.circle", T("화면을 녹화할 때", "When recording"), [T("학생이 나오는 녹화는", "If students appear, follow"), T("학교 지침을 따라 주세요", "your school’s recording rules")]),
    ("info", T("무료 프로그램 이용 안내", "Free to use"), [T("무료로 제공하며, 사용 중 생기는", "Provided as is. We can’t guarantee"), T("문제는 보증하지 않습니다", "against problems that arise in use")]),
  ]
  for (i, card) in cards.enumerated() {
    let q = enter(t, 0.6 + Double(i) * 0.45, 0.35)
    let rect = CGRect(x: 100 + CGFloat(i % 2) * 550, y: 182 + CGFloat(i / 2) * 178 + (1 - q) * 18, width: 530, height: 158)
    alpha(q) {
      fill(rect, rgb(0xFFFFFF, 0.1), radius: 18)
      oval(CGPoint(x: rect.minX + 50, y: rect.minY + 52), 28, lime)
      symbol(card.0, CGRect(x: rect.minX + 36, y: rect.minY + 38, width: 28, height: 28), dock)
      text(card.1, rect.minX + 96, rect.minY + 52, size: 24, weight: .bold, color: .white)
      for (j, line) in card.2.enumerated() {
        text(line, rect.minX + 96, rect.minY + 98 + CGFloat(j) * 30, size: 19, weight: .medium, color: rgb(0xFFFFFF, 0.82))
      }
    }
  }
  alpha(enter(t, 2.2, 0.4)) {
    let note = T("★ 폰 연결·실물화상기: 폰마다 설정이 달라요. ‘내 폰 이름 + USB 디버깅’으로 검색해 보세요", "★ Phone and document camera: every phone differs. Search “your phone + USB debugging”")
    let width = (note as NSString).size(withAttributes: [.font: uiFont(18, .bold)]).width + 36
    fill(CGRect(x: W / 2 - width / 2, y: 532, width: width, height: 38), rgb(0xD9534F), radius: 12)
    text(note, W / 2, 551, size: 18, weight: .bold, color: .white, align: .center)
  }
  alpha(enter(t, 2.6, 0.4)) {
    text(T("© yelsam.lab · 전원 버튼 아래 ©를 누르면 블로그 둘러보기 · 제안하기", "© yelsam.lab · Click © under the power button for the blog or a suggestion"), W / 2, 598, size: 16, color: rgb(0xFFFFFF, 0.7), align: .center)
  }
  drawToolbar(selected: ["highlight"])
}

let scenes = [
  intro, highlight, zoomScene, penScene, timerScene, captureScene, spotScene, sizeScene, barScene, phoneScene, boardScene, outro, noticeScene,
]
let total = scenes.reduce(0) { $0 + $1.duration }

func drawCaption(_ scene: Scene, index: Int, _ t: Double) {
  guard !scene.title.isEmpty else { return }
  let p = enter(t, 0.05, 0.4)
  alpha(p) {
    let x = 60 + (1 - p) * 24
    oval(CGPoint(x: x + 22, y: 60), 22, dock)
    text(String(index), x + 22, 60, size: 22, weight: .bold, color: lime, align: .center)
    let w = text(scene.title, x + 58, 42, size: 30, weight: .bold)
    _ = w
    text(scene.line, x + 58, 80, size: 19, weight: .medium, color: muted)
  }
}
func render(at time: Double, into context: CGContext) {
  ctx = context
  ctx.saveGState()
  ctx.translateBy(x: 0, y: H)
  ctx.scaleBy(x: 1, y: -1)
  let previous = NSGraphicsContext.current
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  var start = 0.0
  for (index, scene) in scenes.enumerated() {
    if time < start + scene.duration || index == scenes.count - 1 {
      let t = time - start
      scene.draw(t)
      drawCaption(scene, index: index, t)
      let edge = min(t, scene.duration - t)
      if edge < 0.15 {
        fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x1E2A38, CGFloat(1 - edge / 0.15) * 0.8))
      }
      break
    }
    start += scene.duration
  }
  NSGraphicsContext.current = previous
  ctx.restoreGState()
}

func makeContext(_ data: UnsafeMutableRawPointer?, _ width: Int, _ height: Int, _ row: Int) -> CGContext {
  CGContext(
    data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: row,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

if let flag = args.firstIndex(of: "--sheet") {
  let times = stride(from: 0.0, to: total, by: total / 40).map { $0 + 0.4 }
  let cell = CGSize(width: 320, height: 180)
  let columns = 5
  let rows = (times.count + columns - 1) / columns
  let sheet = makeContext(nil, Int(cell.width) * columns, Int(cell.height) * rows, 0)
  for (i, time) in times.enumerated() {
    let frame = makeContext(nil, Int(W), Int(H), 0)
    render(at: time, into: frame)
    let x = CGFloat(i % columns) * cell.width
    let y = CGFloat(rows - 1 - i / columns) * cell.height
    sheet.draw(frame.makeImage()!, in: CGRect(x: x, y: y, width: cell.width, height: cell.height))
  }
  let rep = NSBitmapImageRep(cgImage: sheet.makeImage()!)
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[flag + 1]))
  print("sheet \(times.count) frames, total \(total)s")
  exit(0)
}
if let flag = args.firstIndex(of: "--frame") {
  let frame = makeContext(nil, Int(W), Int(H), 0)
  render(at: Double(args[flag + 1])!, into: frame)
  let rep = NSBitmapImageRep(cgImage: frame.makeImage()!)
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[flag + 2]))
  exit(0)
}

let url = URL(fileURLWithPath: args[1])
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(
  mediaType: .video,
  outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [
      AVVideoAverageBitRateKey: 900_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
  ])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
  assetWriterInput: input,
  sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
  ])
writer.add(input)
writer.shouldOptimizeForNetworkUse = true
guard writer.startWriting() else { fatalError("writer: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
let frames = Int(total * Double(fps))
for index in 0..<frames {
  while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
  var buffer: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
  guard let buffer else { fatalError("pixel buffer") }
  CVPixelBufferLockBaseAddress(buffer, [])
  autoreleasepool {
    let frame = makeContext(
      CVPixelBufferGetBaseAddress(buffer), Int(W), Int(H), CVPixelBufferGetBytesPerRow(buffer))
    render(at: Double(index) / Double(fps), into: frame)
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("finish: \(String(describing: writer.error))") }
var offset = 0.0
print("chapters:", scenes.map { scene -> String in
  defer { offset += scene.duration }
  return "\(scene.title.isEmpty ? "-" : scene.title)@\(offset)"
}.joined(separator: " "), "total", total)
