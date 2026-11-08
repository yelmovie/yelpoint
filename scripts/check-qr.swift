// Checks that the Windows QR encoder's matrices decode to the text they were made from.
// Usage: swift check-qr.swift <qr-samples.txt>   (written by tests/windows-model-tests.cs)
import AppKit
import CoreImage

let lines = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
  .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
var samples: [(String, [String])] = []
for line in lines {
  if line.hasPrefix("#") { samples.append((String(line.dropFirst()), [])) } else { samples[samples.count - 1].1.append(line) }
}
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
var failed = 0
for (text, rows) in samples {
  let size = rows.count, scale = 8, quiet = 4
  let side = (size + quiet * 2) * scale
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor.white.setFill()
  CGRect(x: 0, y: 0, width: side, height: side).fill()
  NSColor.black.setFill()
  for (y, row) in rows.enumerated() {
    for (x, c) in row.enumerated() where c == "1" {
      CGRect(x: (x + quiet) * scale, y: side - (y + quiet + 1) * scale, width: scale, height: scale).fill()
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  let found = detector.features(in: CIImage(bitmapImageRep: rep)!).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
  let ok = found.first == text
  if !ok { failed += 1 }
  print(ok ? "OK" : "FAIL", "v\((size - 17) / 4)", text, ok ? "" : "→ \(found)")
}
print(failed == 0 ? "PASS: \(samples.count) QR codes decode to their text" : "FAIL: \(failed) of \(samples.count)")
exit(failed == 0 ? 0 : 1)
