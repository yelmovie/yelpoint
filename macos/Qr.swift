import AppKit
import CoreImage

/// A crisp QR code for `text`, made by Core Image (error correction M), or nil when it does not fit.
func qrImage(_ text: String, side: CGFloat) -> NSImage? {
  guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
  filter.setValue(Data(text.utf8), forKey: "inputMessage")
  filter.setValue("M", forKey: "inputCorrectionLevel")
  guard let code = filter.outputImage, code.extent.width > 0 else { return nil }
  let scale = max(1, (side / code.extent.width).rounded(.down))
  let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
  guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
  return NSImage(cgImage: cg, size: scaled.extent.size)
}

/// Type or paste an address, press Enter, and it shows big in the middle of the screen.
final class QrView: NSView {
  weak var controller: AppController?
  let field = NSTextField(string: "")
  static let size = CGSize(width: 560, height: 48)
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(origin: .zero, size: QrView.size))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    field.frame = CGRect(x: 12, y: 12, width: 392, height: 24)
    field.placeholderString = tr("주소를 붙여넣고 Enter", "Paste an address and press Enter")
    field.font = .systemFont(ofSize: 14)
    field.textColor = Look.paper
    field.backgroundColor = NSColor.white.withAlphaComponent(0.12)
    field.drawsBackground = true
    field.isBordered = false
    field.focusRingType = .none
    field.lineBreakMode = .byTruncatingMiddle
    field.cell?.isScrollable = true
    field.target = self
    field.action = #selector(entered)
    // Only Enter or the button shows it, not leaving the field.
    field.cell?.sendsActionOnEndEditing = false
    field.setAccessibilityLabel(tr("QR로 만들 주소", "Address for the QR code"))
    addSubview(field)
    let show = ToolButton(frame: CGRect(x: 412, y: 4, width: 100, height: 40), title: tr("크게 보기", "Show"), symbol: "qrcode") {
      [weak self] in self?.entered()
    }
    show.toolTip = tr("QR 코드를 화면 가운데 크게 띄우기", "Show the QR code big in the middle of the screen")
    addSubview(show)
    let close = ToolButton(frame: CGRect(x: 514, y: 4, width: 40, height: 40), title: "", symbol: "xmark") {
      [weak controller] in controller?.closeQr()
    }
    close.toolTip = tr("QR 창 닫기", "Close the QR window")
    close.setAccessibilityLabel(tr("QR 창 닫기", "Close the QR window"))
    addSubview(close)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func entered() { controller?.showQr(field.stringValue) }
}

/// The big white card: the code, and the address under it for anyone who would rather type it.
final class QrCardView: NSView {
  weak var controller: AppController?
  var text = "" { didSet { image = qrImage(text, side: 1200); needsDisplay = true } }
  private var image: NSImage?
  private var grabbed: CGPoint?
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  var closeRect: CGRect { CGRect(x: bounds.maxX - 52, y: 12, width: 40, height: 40) }
  override func draw(_ dirtyRect: NSRect) {
    let card = NSBezierPath(roundedRect: bounds, xRadius: 26, yRadius: 26)
    NSColor.white.setFill()
    card.fill()
    let pad: CGFloat = 40
    let caption: CGFloat = 70
    let side = min(bounds.width - pad * 2, bounds.height - pad - caption - 10)
    let codeRect = CGRect(x: (bounds.width - side) / 2, y: pad, width: side, height: side)
    if let image {
      NSGraphicsContext.current?.imageInterpolation = .none
      image.draw(in: codeRect)
    }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byTruncatingMiddle
    let address = text.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    (address as NSString).draw(
      in: CGRect(x: pad, y: codeRect.maxY + 18, width: bounds.width - pad * 2, height: 36),
      withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: Look.dock, .paragraphStyle: style])
    // Close button.
    NSColor.black.withAlphaComponent(0.08).setFill()
    NSBezierPath(ovalIn: closeRect).fill()
    let x = NSBezierPath()
    x.move(to: CGPoint(x: closeRect.minX + 13, y: closeRect.minY + 13))
    x.line(to: CGPoint(x: closeRect.maxX - 13, y: closeRect.maxY - 13))
    x.move(to: CGPoint(x: closeRect.maxX - 13, y: closeRect.minY + 13))
    x.line(to: CGPoint(x: closeRect.minX + 13, y: closeRect.maxY - 13))
    x.lineWidth = 3
    x.lineCapStyle = .round
    Look.dock.setStroke()
    x.stroke()
  }
  override func mouseDown(with event: NSEvent) {
    if closeRect.contains(convert(event.locationInWindow, from: nil)) {
      controller?.closeQr()
      return
    }
    grabbed = event.locationInWindow
  }
  override func mouseDragged(with event: NSEvent) {
    guard let grabbed, let window else { return }
    let p = NSEvent.mouseLocation
    window.setFrameOrigin(CGPoint(x: p.x - grabbed.x, y: p.y - grabbed.y))
  }
  override func mouseUp(with event: NSEvent) { grabbed = nil }
}

extension AppController {
  func showQr(_ raw: String) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      toast(tr("주소를 먼저 넣어 주세요", "Type an address first"))
      return
    }
    guard text.utf8.count <= 1000, qrImage(text, side: 100) != nil else {
      showMessage(tr("QR을 만들지 못했어요", "Could not make the QR code"), tr("주소가 너무 길어요. 짧은 주소로 바꿔서 넣어 주세요.", "The address is too long. Try a shorter one."))
      return
    }
    preferences.qrText = text
    preferencesChanged()
    qrCard.text = text
    let screen = toolbar.screen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    let side = min(visible.height * 0.82, visible.width * 0.6, 900)
    let size = CGSize(width: side - 70, height: side)
    qrWindow.setFrame(
      CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 30, width: size.width, height: size.height),
      display: true)
    qrWindow.orderFrontRegardless()
    qrPanel.orderOut(nil)
    refreshTools()
    updateEscape()
  }
  func closeQr() {
    qrWindow.orderOut(nil)
    qrPanel.orderOut(nil)
    refreshTools()
    updateEscape()
  }
}
