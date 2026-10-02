// Renders the app icon at every size macOS wants: an .iconset folder of PNGs, and the .icns built from them.
//   swiftc Tools/make_icon.swift -o make_icon && ./make_icon AppIcon.iconset AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// The Voice Pipes mark (design system → Assets → Logos): four organ pipes against a pixel sundown, drawn on a
// 32 × 32 grid and only ever scaled by whole pixels. 16 px has its own three-pipe drawing.
typealias Px = (x: Int, y: Int, w: Int, h: Int, rgb: UInt32)
let sundown32: [Px] = [
    (0, 0, 32, 5, 0x2A2140), (0, 5, 32, 4, 0x43294A), (0, 9, 32, 4, 0x6B3A52), (0, 13, 32, 3, 0x9A4E55),
    (0, 16, 32, 3, 0xC96A57), (0, 19, 32, 3, 0xE8915F), (0, 22, 32, 2, 0xF2B46A), (0, 24, 32, 8, 0x1F1A15),
    (28, 17, 2, 1, 0xF6D58A), (27, 18, 4, 3, 0xF6D58A), (28, 21, 2, 1, 0xF6D58A),
    (9, 12, 4, 14, 0x18140F), (14, 8, 4, 18, 0x18140F), (19, 5, 4, 21, 0x18140F), (24, 10, 4, 16, 0x18140F),
    (10, 18, 2, 1, 0xC96A57), (15, 18, 2, 1, 0xC96A57), (20, 18, 2, 1, 0xC96A57), (25, 18, 2, 1, 0xC96A57),
    (8, 26, 21, 1, 0xF0E4CC),
    (3, 24, 1, 1, 0xF0E4CC), (4, 25, 1, 1, 0xF0E4CC), (5, 26, 1, 1, 0xF0E4CC), (4, 27, 1, 1, 0xF0E4CC), (3, 28, 1, 1, 0xF0E4CC),
]
let sundown16: [Px] = [
    (0, 0, 16, 3, 0x2A2140), (0, 3, 16, 3, 0x6B3A52), (0, 6, 16, 3, 0xC96A57), (0, 9, 16, 3, 0xE8915F), (0, 12, 16, 4, 0x1F1A15),
    (14, 8, 2, 2, 0xF6D58A),
    (5, 6, 2, 7, 0x18140F), (8, 3, 2, 10, 0x18140F), (11, 5, 2, 8, 0x18140F),
    (4, 13, 11, 1, 0xF0E4CC), (1, 12, 1, 1, 0xF0E4CC), (2, 13, 1, 1, 0xF0E4CC), (1, 14, 1, 1, 0xF0E4CC),
]

func color(_ rgb: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // 64 px and below: the art fills the canvas. Larger: a tile on the macOS icon grid (about 80% of the canvas),
    // sized to a whole multiple of the art so every pixel stays square and sharp.
    let art = px <= 16 ? sundown16 : sundown32
    let grid = px <= 16 ? 16 : 32
    let scale = px <= 64 ? px / grid : Int(size * 0.805) / grid
    let side = CGFloat(grid * scale)
    let tile = CGRect(x: ((size - side) / 2).rounded(.down), y: ((size - side) / 2).rounded(.down), width: side, height: side)
    let shape = CGPath(roundedRect: tile, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)

    if px > 64 {  // soft drop shadow under the tile
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x18140F))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.setShouldAntialias(false)
    let unit = CGFloat(scale)
    for p in art {
        // The art's rows run top-down; Core Graphics' y runs bottom-up.
        ctx.setFillColor(color(p.rgb))
        ctx.fill(CGRect(x: tile.minX + CGFloat(p.x) * unit, y: tile.maxY - CGFloat(p.y + p.h) * unit,
                        width: CGFloat(p.w) * unit, height: CGFloat(p.h) * unit))
    }
    ctx.restoreGState()
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
