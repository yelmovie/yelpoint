import AppKit

class QuietPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Takes typing without activating the app, so the lesson app stays in front.
final class TypingPanel: QuietPanel {
  override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
  weak var controller: AppController?
  let screen: NSScreen
  var strokes: [InkStroke] = []
  var activeStroke: InkStroke?
  var selection: (CGPoint, CGPoint)?
  /// A pinned image being moved by its grip while the pen layer is on top.
  private var stickerMove: (QuietPanel, CGVector)?
  var selectionRect: CGRect? {
    selection.map {
      CGRect(
        x: min($0.0.x, $0.1.x), y: min($0.0.y, $0.1.y), width: abs($0.0.x - $0.1.x),
        height: abs($0.0.y - $0.1.y))
    }
  }
  init(screen: NSScreen, controller: AppController) {
    self.screen = screen
    self.controller = controller
    super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
  }
  required init?(coder: NSCoder) { fatalError() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  func local(_ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill(using: .copy)
    guard let c = controller else { return }
    // A truly zero-alpha panel can be skipped during WindowServer hit testing.
    // Only drawing mode installs this nearly transparent input surface.
    if (c.pen && !c.passthrough || c.spotEditing) && !c.toolsSuspended {
      NSColor.white.withAlphaComponent(0.01).setFill()
      dirtyRect.fill()
    }
    if c.selecting && !c.toolsSuspended {
      let shade = NSBezierPath(rect: bounds)
      if let r = selectionRect { shade.append(NSBezierPath(rect: r)) }
      shade.windingRule = .evenOdd
      NSColor.black.withAlphaComponent(0.28).setFill()
      shade.fill()
      if selection == nil {
        drawHint(tr("드래그해서 캡처할 영역을 고르세요 · 한 번 클릭하면 붙이기·저장·녹화 메뉴 · Esc 취소", "Drag to choose an area to capture · Click once for paste, save and record · Esc to cancel"))
      }
    }
    // Picking a shape changes nothing on screen until a drag, so say what to do.
    if c.spotEditing && !c.toolsSuspended && c.spotDrag == nil {
      drawHint(
        c.spot == nil
          ? tr("드래그해서 보여 줄 곳을 그리세요 · Esc 취소", "Drag to draw the spot · Esc to cancel")
          : tr("빨간 선을 끌면 크기 조절 · 안쪽을 끌면 이동 · 바깥 클릭이나 Esc로 완료", "Drag the red line to resize · drag inside to move · click outside or Esc when done"))
    }
    let now = ProcessInfo.processInfo.systemUptime
    let point = local(c.pointer)
    let onScreen = screen.frame.contains(c.pointer)
    if c.preferences.spotlight {
      let shade = NSBezierPath(rect: bounds)
      if onScreen {
        let radius = c.preferences.dimmingRadius
        shade.appendOval(
          in: CGRect(
            x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
      }
      shade.windingRule = .evenOdd
      NSColor.black.withAlphaComponent(0.48).setFill()
      shade.fill()
    }
    for (index, stroke) in (strokes + (activeStroke.map { [$0] } ?? [])).enumerated() {
      guard let start = stroke.points.first else { continue }
      let path = NSBezierPath()
      path.lineWidth = stroke.width
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      path.move(to: start)
      if stroke.points.count == 1 { path.line(to: CGPoint(x: start.x + 0.1, y: start.y + 0.1)) }
      for p in stroke.points.dropFirst() { path.line(to: p) }
      stroke.color.withAlphaComponent(stroke.alpha(at: now, inProgress: index >= strokes.count))
        .setStroke()
      path.stroke()
    }
    if onScreen, c.preferences.highlight, !c.pen, !c.selecting, !c.spotEditing, !c.hideHalo {
      NSColor.systemYellow.withAlphaComponent(0.30).setFill()
      let radius = c.preferences.pointerRadius
      NSBezierPath(
        ovalIn: CGRect(
          x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
      ).fill()
    }
    for pulse in c.pulses where screen.frame.contains(pulse.point) {
      let progress = pulse.progress(at: now)
      let p = local(pulse.point)
      let r = 15 + progress * 30
      (pulse.right ? NSColor.systemBlue : NSColor.systemOrange).withAlphaComponent(
        0.85 * (1 - progress)
      ).setStroke()
      let path = NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
      path.lineWidth = 3
      path.stroke()
    }
    if onScreen, c.zoom {
      let global = clampedLens(center: c.pointer, screen: screen.frame)
      let r = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
      let path = NSBezierPath(roundedRect: r, xRadius: 17, yRadius: 17)
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
      shadow.shadowBlurRadius = 16
      shadow.shadowOffset = CGSize(width: 0, height: -4)
      shadow.set()
      Look.paper.setFill()
      path.fill()
      NSGraphicsContext.restoreGraphicsState()
      NSGraphicsContext.saveGraphicsState()
      path.addClip()
      if let frame = c.magnifiedImage {
        NSGraphicsContext.current?.cgContext.draw(frame, in: r.insetBy(dx: 3, dy: 3))
      } else {
        tr("확대 준비 중…", "Preparing…").draw(
          at: CGPoint(x: r.minX + 63, y: r.midY - 6),
          withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Look.dock])
      }
      NSGraphicsContext.restoreGraphicsState()
      Look.lime.setStroke()
      path.lineWidth = 3
      path.stroke()
      let badge = CGRect(x: r.maxX - 50, y: r.minY + 8, width: 40, height: 21)
      Look.dock.setFill()
      NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
      String(format: "%.1f×", Double(c.preferences.zoom)).draw(
        at: CGPoint(x: badge.minX + 7, y: badge.minY + 4),
        withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
    }
    if screen.displayID == c.toolbar.screen?.displayID, let text = c.keyText, now < c.keyUntil {
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: Look.paper,
      ]
      let size = text.size(withAttributes: attributes)
      let r = CGRect(x: 24, y: 30, width: size.width + 32, height: 44)
      Look.dock.setFill()
      NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
      text.draw(at: CGPoint(x: r.minX + 16, y: r.minY + 9), withAttributes: attributes)
    }
    if let region = c.spot, region.display == screen.displayID {
      Look.spotLine.setStroke()
      let outline = c.spotPath(region)
      outline.lineWidth = 3
      outline.stroke()
    }
    if let r = selectionRect {
      Look.lime.setStroke()
      let outline = NSBezierPath(rect: r)
      outline.lineWidth = 2
      outline.stroke()
    }
  }
  private func drawHint(_ hint: String) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Look.paper,
    ]
    let size = hint.size(withAttributes: attributes)
    let top = screen.visibleFrame.maxY - screen.frame.minY
    let pill = CGRect(
      x: bounds.midX - size.width / 2 - 20, y: top - 84, width: size.width + 40, height: 48)
    Look.dock.setFill()
    NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
    hint.draw(at: CGPoint(x: pill.minX + 20, y: pill.midY - size.height / 2), withAttributes: attributes)
  }
  override func resetCursorRects() {
    if controller?.pen == true || controller?.selecting == true
      || controller?.spotEditing == true
    { addCursorRect(bounds, cursor: .crosshair) }
  }
  override func mouseDown(with event: NSEvent) {
    if let c = controller, c.selecting, !c.toolsSuspended {
      let p = convert(event.locationInWindow, from: nil)
      selection = (p, p)
      needsDisplay = true
      return
    }
    if let c = controller, c.spotEditing, !c.toolsSuspended {
      c.spotMouseDown(display: screen.displayID, at: convert(event.locationInWindow, from: nil))
      return
    }
    guard let c = controller, c.pen, !c.passthrough, !c.toolsSuspended else { return }
    let local = convert(event.locationInWindow, from: nil)
    let global = CGPoint(x: screen.frame.minX + local.x, y: screen.frame.minY + local.y)
    if let (window, handle) = c.stickerHandle(at: global) {
      switch handle {
      case .close: c.removeSticker(window)
      case .move:
        stickerMove = (window, CGVector(dx: global.x - window.frame.minX, dy: global.y - window.frame.minY))
      }
      c.refreshTools()
      return
    }
    c.colorPanel.orderOut(nil)
    c.undoHistory.append(.display(screen.displayID))
    activeStroke = InkStroke(
      points: [convert(event.locationInWindow, from: nil)], color: c.inkColor,
      width: c.preferences.penWidth, created: ProcessInfo.processInfo.systemUptime,
      expires: c.preferences.fadingInk)
    needsDisplay = true
  }
  override func mouseDragged(with event: NSEvent) {
    if let (window, grab) = stickerMove {
      let local = convert(event.locationInWindow, from: nil)
      window.setFrameOrigin(
        CGPoint(x: screen.frame.minX + local.x - grab.dx, y: screen.frame.minY + local.y - grab.dy))
      return
    }
    if selection != nil {
      selection?.1 = convert(event.locationInWindow, from: nil)
      needsDisplay = true
      return
    }
    if let c = controller, c.spotDrag != nil {
      c.spotMouseDragged(to: convert(event.locationInWindow, from: nil))
      return
    }
    guard activeStroke != nil else { return }
    let p = convert(event.locationInWindow, from: nil)
    if let last = activeStroke?.points.last, hypot(last.x - p.x, last.y - p.y) < 0.8 { return }
    activeStroke?.points.append(p)
    needsDisplay = true
  }
  /// The pen layer sits over pasted captures, so it opens their menu for them.
  override func rightMouseDown(with event: NSEvent) {
    guard let c = controller else { return }
    let local = convert(event.locationInWindow, from: nil)
    let p = CGPoint(x: screen.frame.minX + local.x, y: screen.frame.minY + local.y)
    guard let view = c.sticker(at: p), let menu = view.menu else { return }
    view.menuPoint = view.convert(view.window?.convertPoint(fromScreen: p) ?? .zero, from: nil)
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }
  override func mouseUp(with event: NSEvent) {
    if stickerMove != nil {
      stickerMove = nil
      return
    }
    if let c = controller, let r = selectionRect {
      selection = nil
      needsDisplay = true
      if c.selecting { c.finishSelection(screen: screen, rect: r) }
      return
    }
    if let c = controller, c.spotDrag != nil {
      c.spotMouseUp()
      return
    }
    finishStroke()
  }
  func finishStroke(notify: Bool = true) {
    guard var stroke = activeStroke else { return }
    stroke.created = ProcessInfo.processInfo.systemUptime
    activeStroke = nil
    if controller?.adoptStroke(stroke, from: screen) != true { strokes.append(stroke) }
    needsDisplay = true
    if notify { controller?.refreshTools() }
  }
}
