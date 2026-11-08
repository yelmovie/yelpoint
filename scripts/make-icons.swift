import AppKit

// The YelPoint mark: a lime pointer sending out a click ripple on an electric gradient.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
  CGGradient(
    colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
/// Continuous corners, the shape macOS uses for app icons.
func squircle(_ rect: CGRect, exponent: Double = 5) -> CGPath {
  let path = CGMutablePath()
  for i in 0...360 {
    let t = Double(i) / 360 * 2 * .pi
    let c = cos(t)
    let s = sin(t)
    let x = pow(abs(c), 2 / exponent) * (c < 0 ? -1 : 1)
    let y = pow(abs(s), 2 / exponent) * (s < 0 ? -1 : 1)
    let p = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
  }
  path.closeSubpath()
  return path
}
func rounded(_ points: [CGPoint], radius: CGFloat) -> CGPath {
  let path = CGMutablePath()
  let count = points.count
  let start = CGPoint(
    x: (points[count - 1].x + points[0].x) / 2, y: (points[count - 1].y + points[0].y) / 2)
  path.move(to: start)
  for i in 0..<count {
    path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % count], radius: radius)
  }
  path.closeSubpath()
  return path
}

let size = 1024
let context = CGContext(
  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setShouldAntialias(true)
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(plate)

// Lift off the desktop.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x0B0630, 0.45))
context.addPath(shape)
context.setFillColor(color(0x2A10C8))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
context.drawLinearGradient(
  gradient([(0, color(0x2B12E0)), (0.52, color(0x7A22FF)), (1, color(0x00C2FF))]),
  start: CGPoint(x: 160, y: 960), end: CGPoint(x: 900, y: 80), options: [])

let tip = CGPoint(x: 322, y: 716)
// Light gathering where the pointer lands.
context.drawRadialGradient(
  gradient([(0, color(0xFFFFFF, 0.42)), (0.45, color(0xC9F7FF, 0.14)), (1, color(0xFFFFFF, 0))]),
  startCenter: tip, startRadius: 0, endCenter: tip, endRadius: 430, options: [])
// Click ripple.
for (radius, width, tint) in [
  (CGFloat(118), CGFloat(20), color(0xD6F871, 0.95)), (204, 14, color(0xFFFFFF, 0.5)),
  (296, 9, color(0xFFFFFF, 0.22)),
] {
  context.setStrokeColor(tint)
  context.setLineWidth(width)
  context.strokeEllipse(
    in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
}
// Sheen across the top of the glass.
context.drawLinearGradient(
  gradient([(0, color(0xFFFFFF, 0.26)), (1, color(0xFFFFFF, 0))]),
  start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
context.restoreGState()

// Pointer: a tail-less kite, mirrored about its diagonal.
let pointer = rounded(
  [
    tip, CGPoint(x: tip.x + 462, y: tip.y - 150), CGPoint(x: tip.x + 262, y: tip.y - 262),
    CGPoint(x: tip.x + 150, y: tip.y - 462),
  ], radius: 40)
context.saveGState()
context.setShadow(offset: CGSize(width: 10, height: -24), blur: 44, color: color(0x12044F, 0.6))
context.addPath(pointer)
context.setFillColor(color(0xD6F871))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(pointer)
context.clip()
context.drawLinearGradient(
  gradient([(0, color(0xFFFFFF)), (0.34, color(0xE9FF9C)), (1, color(0xA8F03C))]),
  start: tip, end: CGPoint(x: tip.x + 330, y: tip.y - 330), options: [])
context.restoreGState()
context.addPath(pointer)
context.setStrokeColor(color(0xFFFFFF, 0.8))
context.setLineWidth(5)
context.strokePath()

// Hairline that catches the edge of the plate.
context.saveGState()
context.addPath(shape)
context.clip()
context.addPath(shape)
context.setStrokeColor(color(0xFFFFFF, 0.3))
context.setLineWidth(6)
context.strokePath()
context.restoreGState()

let master = context.makeImage()!
for side in [16, 32, 48, 64, 128, 256, 512, 1024] {
  let small = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  small.interpolationQuality = .high
  small.draw(master, in: CGRect(x: 0, y: 0, width: side, height: side))
  let bitmap = NSBitmapImageRep(cgImage: small.makeImage()!)
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: directory.appendingPathComponent("icon-\(side).png"))
}
