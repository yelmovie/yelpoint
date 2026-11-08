import AppKit

enum SpotDrag {
  case move(CGVector)
  case resize(Int)
  case draw(CGPoint, SpotRegion?)
}

final class SpotView: NSView {
  weak var controller: AppController?
  var shapes: [SpotShape: ToolButton] = [:]
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(x: 0, y: 0, width: 360, height: 48))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    let items: [(SpotShape, String, String)] = [
      (.rectangle, tr("사각", "Rect"), "rectangle"), (.circle, tr("원", "Circle"), "circle"), (.ellipse, tr("타원", "Ellipse"), "oval"),
    ]
    for (i, (shape, title, symbol)) in items.enumerated() {
      let b = ToolButton(
        frame: CGRect(x: 8 + i * 86, y: 4, width: 86, height: 40), title: title, symbol: symbol
      ) { [weak controller] in controller?.beginSpot(shape) }
      b.toolTip = tr("\(title) 스팟 그리기", "Draw \(title) spot")
      shapes[shape] = b
      addSubview(b)
    }
    let off = ToolButton(
      frame: CGRect(x: 266, y: 4, width: 86, height: 40), title: tr("끄기", "Off"), symbol: "xmark"
    ) { [weak controller] in controller?.clearSpot() }
    off.toolTip = tr("스팟 끄기", "Turn spot off")
    addSubview(off)
  }
  required init?(coder: NSCoder) { fatalError() }
  func refresh() {
    guard let c = controller else { return }
    for (shape, button) in shapes { button.selected = c.spotShape == shape }
  }
}

extension AppController {
  var spotEditing: Bool { spotShape != nil }
  func beginSpot(_ shape: SpotShape) {
    guard !toolsSuspended else { return }
    finishStrokes()
    pen = false
    zoom = false
    capture.stop()
    capturedDisplay = nil
    magnifiedImage = nil
    spotShape = shape
    if var region = spot {
      region.shape = shape
      if shape == .circle {
        let side = max(region.rect.width, region.rect.height)
        region.rect = CGRect(
          x: region.rect.midX - side / 2, y: region.rect.midY - side / 2, width: side, height: side)
      }
      spot = region
    }
    refreshTools()
    invalidateAll()
  }
  func clearSpot() {
    spot = nil
    spotShape = nil
    spotDrag = nil
    refreshTools()
    invalidateAll()
  }
  func spotMouseDown(display: CGDirectDisplayID, at p: CGPoint) {
    guard let shape = spotShape else { return }
    if let region = spot, region.display == display {
      if let handle = spotHandle(at: p, shape: region.shape, rect: region.rect) {
        spotDrag = .resize(handle)
        return
      }
      if spotContains(region.shape, rect: region.rect, point: p) {
        spotDrag = .move(CGVector(dx: p.x - region.rect.minX, dy: p.y - region.rect.minY))
        return
      }
    }
    spotDrag = .draw(p, spot)
    spot = SpotRegion(shape: shape, rect: CGRect(origin: p, size: .zero), display: display)
    invalidateAll()
  }
  func spotMouseDragged(to p: CGPoint) {
    guard var region = spot, let drag = spotDrag else { return }
    switch drag {
    case .move(let offset): region.rect.origin = CGPoint(x: p.x - offset.dx, y: p.y - offset.dy)
    case .resize(let handle):
      region.rect = spotResized(
        region.rect, handle: handle, to: p, square: region.shape == .circle)
    case .draw(let start, _):
      region.rect = spotRect(from: start, to: p, square: region.shape == .circle)
    }
    spot = region
    invalidateAll()
  }
  /// A click outside the shape keeps the old spot and hands the mouse back to other apps.
  func spotMouseUp() {
    defer { spotDrag = nil }
    if case .draw(_, let previous) = spotDrag,
      let region = spot, min(region.rect.width, region.rect.height) < spotMinimumSize
    {
      spot = previous
      spotShape = nil
      refreshTools()
    }
    invalidateAll()
  }
  func spotPath(_ region: SpotRegion) -> NSBezierPath {
    region.shape == .rectangle
      ? NSBezierPath(rect: region.rect) : NSBezierPath(ovalIn: region.rect)
  }
}
