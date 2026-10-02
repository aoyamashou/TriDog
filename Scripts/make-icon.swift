// アプリアイコン（リサイクルマーク）の .iconset を作る。使い方: swift Scripts/make-icon.swift <出力ディレクトリ>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
  let s = CGFloat(size)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  // macOS 標準の角丸スクエア（余白 10%）
  let inset = s * 0.1
  let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
  NSGradient(
    starting: NSColor(srgbRed: 0.20, green: 0.78, blue: 0.45, alpha: 1),
    ending: NSColor(srgbRed: 0.05, green: 0.52, blue: 0.33, alpha: 1))!
    .draw(in: path, angle: -90)

  let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.55, weight: .bold)
    .applying(.init(paletteColors: [.white]))
  let symbol = NSImage(systemSymbolName: "arrow.3.trianglepath", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
  let size = symbol.size
  symbol.draw(in: NSRect(
    x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
    width: size.width, height: size.height))

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
  try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
  try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
