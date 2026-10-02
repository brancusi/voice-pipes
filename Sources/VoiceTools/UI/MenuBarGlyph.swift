import AppKit

/// The menu bar icon: the Wrangler (the Voice Pipes mascot) as a one-colour 18 × 18 pixel template, which macOS
/// tints for light, dark and highlighted menu bars. Idle he's a bust in his hat; while recording he raises an arm
/// and swings a lasso over his hat, three stepped frames.
enum MenuBarGlyph {
    enum Variant: Hashable { case idle, update, lasso(Int) }

    static let lassoFrames = 3

    static func image(_ variant: Variant) -> NSImage {
        if let cached = cache[variant] { return cached }
        let rows: [String]
        switch variant {
        case .idle, .update: rows = idle
        case .lasso(let frame): rows = lasso[frame % lassoFrames]
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            if variant == .update { NSRect(x: 15, y: 0, width: 3, height: 3).fill() }  // an update is waiting
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Voice Pipes"
        cache[variant] = image
        return image
    }

    private static let idle = [
        "..................",
        "..................",
        "......######......",
        ".....########.....",
        ".....########.....",
        ".################.",
        ".....########.....",
        ".....#.####.#.....",
        ".....########.....",
        "......######......",
        ".......####.......",
        ".....########.....",
        "...############...",
        "..##############..",
        "..##############..",
        "..##############..",
        "..................",
        "..................",
    ]

    /// The loop swings left, overhead, right; the rope runs down to his raised hand.
    private static let lasso = [
        [
            "..######..........",
            ".#......#.........",
            "..########........",
            "..........##......",
            "....######..##....",
            "....######...#....",
            ".#############....",
            "....######...#....",
            "....#.##.#...#....",
            "....######...#....",
            ".....####....#....",
            "...########.#.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..................",
            "..................",
        ],
        [
            ".....#######......",
            "....#.......#.....",
            ".....########.....",
            "............#.....",
            "....######...#....",
            "....######...#....",
            ".#############....",
            "....######...#....",
            "....#.##.#...#....",
            "....######...#....",
            ".....####....#....",
            "...########.#.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..................",
            "..................",
        ],
        [
            "..........######..",
            ".........#......#.",
            "..........######..",
            "...........##.....",
            "....######...#....",
            "....######...#....",
            ".#############....",
            "....######...#....",
            "....#.##.#...#....",
            "....######...#....",
            ".....####....#....",
            "...########.#.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..###########.....",
            "..................",
            "..................",
        ],
    ]

    nonisolated(unsafe) private static var cache: [Variant: NSImage] = [:]
}
