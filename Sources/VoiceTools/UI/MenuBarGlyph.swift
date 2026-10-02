import AppKit

/// The menu bar icon: the Voice Pipes mark as a one-colour 18 × 18 pixel template (macOS tints it for light, dark
/// and highlighted menu bars). A `›` prompt, three organ pipes with their slits cut out, and the base pipe.
enum MenuBarGlyph {
    enum Variant { case idle, recording, update }

    static func image(_ variant: Variant) -> NSImage {
        if let cached = cache[variant] { return cached }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // The prompt.
            for (x, y) in [(1, 11), (2, 12), (3, 13), (2, 14), (1, 15)] { NSRect(x: x, y: y, width: 1, height: 1).fill() }
            // Three pipes standing on row 14; while recording they jump to a different chord.
            let tops = variant == .recording ? [9, 2, 8] : [7, 3, 6]
            for (column, top) in zip([6, 10, 14], tops) {
                pipe(x: column, top: top)
            }
            NSRect(x: 5, y: 15, width: 13, height: 1).fill()  // the base pipe
            if variant == .update { NSRect(x: 15, y: 0, width: 3, height: 3).fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Voice Pipes"
        cache[variant] = image
        return image
    }

    /// A 3-pixel-wide pipe from `top` to row 13, with a 1-pixel slit (the organ pipe's mouth) at row 10.
    private static func pipe(x: Int, top: Int) {
        for row in top...13 {
            if row == 10 && top < 10 {
                NSRect(x: x, y: row, width: 1, height: 1).fill()
                NSRect(x: x + 2, y: row, width: 1, height: 1).fill()
            } else {
                NSRect(x: x, y: row, width: 3, height: 1).fill()
            }
        }
    }

    nonisolated(unsafe) private static var cache: [Variant: NSImage] = [:]
}
