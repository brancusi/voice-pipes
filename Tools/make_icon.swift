// Renders the app icon at every size macOS wants: an .iconset folder of PNGs, and the .icns built from them.
//   swiftc Tools/make_icon.swift -o make_icon && ./make_icon AppIcon.iconset AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: the tile sits inside a margin, with a continuous-corner rounded rectangle.
    let inset = size * 0.1
    let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()

    // Violet → blue gradient
    path.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.30, green: 0.16, blue: 0.62, alpha: 1),
                        NSColor(calibratedRed: 0.26, green: 0.36, blue: 0.86, alpha: 1),
                        NSColor(calibratedRed: 0.20, green: 0.58, blue: 0.96, alpha: 1)])!
        .draw(in: tile, angle: -60)

    // Top highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

    // Glyph: microphone over a waveform
    let glyphSize = tile.width * 0.62
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let scale = min(glyphSize / s.width, glyphSize / s.height)
        let w = s.width * scale, h = s.height * scale
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
        symbol.draw(in: CGRect(x: tile.midX - w / 2, y: tile.midY - h / 2 - tile.height * 0.01, width: w, height: h))
        ctx.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Each PNG into the iconset (for reference) and straight into an .icns container: "icns" + total length,
// then (4-char type, entry length, PNG bytes) per size. Avoids iconutil, which needs system services.
let entries: [(String, String, Int)] = [
    ("16x16", "icp4", 16), ("16x16@2x", "ic11", 32), ("32x32", "icp5", 32), ("32x32@2x", "ic12", 64),
    ("128x128", "ic07", 128), ("128x128@2x", "ic13", 256), ("256x256", "ic08", 256),
    ("256x256@2x", "ic14", 512), ("512x512", "ic09", 512), ("512x512@2x", "ic10", 1024),
]
func be32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).bigEndian) { Data($0) } }
var body = Data()
for (name, type, px) in entries {
    let png = render(px)
    try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
    body += type.data(using: .ascii)! + be32(8 + png.count) + png
}
let icns = "icns".data(using: .ascii)! + be32(8 + body.count) + body
let icnsPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon.icns"
try! icns.write(to: URL(fileURLWithPath: icnsPath))
print("wrote \(out) and \(icnsPath)")
