// Paints the DMG window background: a pixel sundown, a drag arrow from the app to Applications, the Wrangler on the
// ground and the wordmark. 640 × 400 points, written at 1× and 2× for a Retina-aware TIFF.
//   swiftc Tools/make_dmg_background.swift -o make_dmg_background && ./make_dmg_background out/dir
// Icons sit at (170, 190) and (470, 190) (see Tools/dmg_settings.py); their labels land on the terracotta band,
// readable in Finder's light (black) and dark (white) label colours.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let unit: CGFloat = 10  // one art pixel = 10 points; the scene is 64 × 40 art pixels

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Art rows (top-down) for each sky band, then the ground.
let bands: [(Int, Int, UInt32)] = [
    (0, 8, 0x2A2140), (8, 6, 0x43294A), (14, 6, 0x6B3A52), (20, 5, 0x9A4E55),
    (25, 4, 0xC96A57), (29, 2, 0xE8915F), (31, 2, 0xF2B46A), (33, 7, 0x1F1A15),
]

// The Wrangler, busking (same grid as Sources/VoiceTools/UI/WranglerArt.swift).
let palette: [Character: UInt32] = [
    "a": 0x18140F, "b": 0x8A5A3C, "c": 0x4A3F35, "d": 0x8FB8D6, "e": 0x5E3D29, "f": 0xB97C5C, "g": 0xB8A88E,
    "h": 0xE3A983, "i": 0xE0694A, "j": 0xD8D0C0, "k": 0xEC8F7C, "l": 0xC3A3D4, "m": 0x5C4030, "n": 0x8F74A3,
    "o": 0xE8C26A, "p": 0xA9BF8A, "q": 0x3D5873, "r": 0x2C4257, "s": 0x7A4B30, "t": 0xC99A6E,
]
let wrangler = [
    "......aaaaaaaa......", ".....abbbbbbbba.....", ".....abcddcddca.....", ".....aeeeeeeeea.....",
    ".aaaabbbbbbbbbbaaaa.", "abbbbbbbbbbbbbbbbbba", ".aaaaaaaaaaaaaaaaaa.", ".....affffffffa.....",
    "....gahahhhhaha.....", "....gahhhhfhhha.....", "....gaheeeeeeha.....", "....ggijjjjjjjjja...",
    ".....aaajajajaja....", "....akkkkkkkkkka....", "...allakkkkkkalla...", "..allmmmakkammmlla..",
    ".alllmmmllllmmmllla.", ".allammmllllmmmalla.", ".allammmlnllmmmalla.", ".ahhammmllllmmmahha.",
    ".ahhaaaaooooaaaahha.", ".ppaqqqqqqqqqqagg...", ".p.aqqqqqrqqqqag....", "...aqqqqaaqqqqa.....",
    "...aqqqa..aqqqa.....", "...asssa..asssa.....", "...astsa..astsa.....", "..assssa..assssa....",
    ".asssssaj.jasssssa..", "aaaaa.aa..aa.aaaaa..",
]

func render(scale: CGFloat) -> NSBitmapImageRep {
    let size = NSSize(width: 640, height: 400)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .none
    context.shouldAntialias = false
    // Flip so y runs down, like the art.
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: size.height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UInt32) {
        hex(color).setFill()
        NSRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit).fill()
    }

    for (row, height, color) in bands { px(0, CGFloat(row), 64, CGFloat(height), color) }
    // Stars and the sun low on the horizon.
    px(6, 3, 0.4, 0.4, 0xF0E4CC); px(51, 5, 0.4, 0.4, 0xF0E4CC); px(30, 2, 0.4, 0.4, 0xC3A3D4); px(14, 9, 0.4, 0.4, 0xF0E4CC)
    px(9, 29, 4, 1, 0xF6D58A); px(8, 30, 6, 3, 0xF6D58A)

    // The drag arrow between the icons, in bone, built from whole 10-point pixels: a dashed shaft and a head.
    for x in stride(from: 25, through: 34, by: 3) { px(CGFloat(x), 18.5, 2, 1, 0xF0E4CC) }
    px(36, 17.5, 1, 3, 0xF0E4CC); px(37, 18, 1, 2, 0xF0E4CC); px(38, 18.5, 1, 1, 0xF0E4CC)

    // The Wrangler on the ground, right of Applications, at 3× (each art pixel 3 points).
    let s: CGFloat = 3, originX: CGFloat = 560, originY: CGFloat = 330 - 30 * s
    for (y, row) in wrangler.enumerated() {
        for (x, key) in row.enumerated() {
            guard let color = palette[key] else { continue }
            hex(color).setFill()
            NSRect(x: originX + CGFloat(x) * s, y: originY + CGFloat(y) * s, width: s, height: s).fill()
        }
    }

    // Text on the ground: the wordmark, then the instruction (drawn unflipped).
    NSGraphicsContext.saveGraphicsState()
    flip.invert()
    flip.concat()
    context.shouldAntialias = true
    let mono = { (size: CGFloat, weight: NSFont.Weight) in NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
    let word = NSMutableAttributedString(string: "voice | pipes", attributes: [.font: mono(18, .semibold), .foregroundColor: hex(0xF0E4CC)])
    word.addAttribute(.foregroundColor, value: hex(0xEC8F7C), range: NSRange(location: 6, length: 1))
    word.draw(at: NSPoint(x: 28, y: 400 - 372))
    NSAttributedString(string: "drag to Applications to install", attributes: [.font: mono(12, .regular), .foregroundColor: hex(0xB8A88E)])
        .draw(at: NSPoint(x: 200, y: 400 - 369))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    try render(scale: scale).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
print("wrote background.png, background@2x.png")
