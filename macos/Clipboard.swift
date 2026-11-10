import AppKit

/// Web-based editors often request PNG explicitly; NSImage's default writer only advertises TIFF.
/// Encode both eagerly so the clipboard remains usable without depending on a live image owner.
enum ImageClipboard {
  @discardableResult static func write(
    _ image: CGImage, size: CGSize, to pasteboard: NSPasteboard = .general
  ) -> Bool {
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = size
    guard let png = bitmap.representation(using: .png, properties: [:]),
      let tiff = bitmap.tiffRepresentation
    else { return false }
    let item = NSPasteboardItem()
    guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else { return false }
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  /// Uses a private, temporary pasteboard. Never reads or changes the user's clipboard.
  static func selfTest() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let context = CGContext(
      data: nil, width: 24, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    let image = context.makeImage()!
    precondition(write(image, size: CGSize(width: 12, height: 6), to: board))
    precondition(board.pasteboardItems?.count == 1)
    precondition(board.types?.contains(.png) == true && board.types?.contains(.tiff) == true)
    let png = board.data(forType: .png)!
    precondition(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    for type in [NSPasteboard.PasteboardType.png, .tiff] {
      let decoded = NSBitmapImageRep(data: board.data(forType: type)!)!
      precondition(decoded.pixelsWide == 24 && decoded.pixelsHigh == 12)
      precondition((decoded.colorAt(x: 3, y: 3)?.redComponent ?? 0) > 0.95)
      precondition((decoded.colorAt(x: 20, y: 3)?.alphaComponent ?? 1) < 0.05)
    }
    precondition(NSImage(pasteboard: board) != nil)
    // Repeated copies replace the item instead of accumulating stale image representations.
    precondition(write(image, size: CGSize(width: 12, height: 6), to: board))
    precondition(board.pasteboardItems?.count == 1 && board.data(forType: .png) == png)
    print("PASS: clipboard PNG + TIFF, pixel size, alpha, native image read and repeated copy (private pasteboard)")
  }
}
