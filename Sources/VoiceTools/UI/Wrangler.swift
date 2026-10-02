import SwiftUI

/// The Wrangler drawn at a whole-pixel scale (4×, 6×…), crisp: each art pixel is a filled square, nothing smoothed.
/// For the About window, empty states and celebrations only; never inside working controls.
struct Wrangler: View {
    var pose: WranglerArt.Pose = .busk
    var scale: Int = 4

    var body: some View {
        let rows = WranglerArt.rows(pose)
        let s = CGFloat(scale)
        Canvas(rendersAsynchronously: false) { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, key) in row.enumerated() {
                    guard let hex = WranglerArt.palette[key] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)),
                                 with: .color(Color(hex: hex)))
                }
            }
        }
        .frame(width: CGFloat(WranglerArt.width) * s, height: CGFloat(WranglerArt.height) * s)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        switch pose {
        case .busk: "The Wrangler, busking with a harmonica"
        case .sing: "The Wrangler, singing"
        case .done: "The Wrangler, winking"
        }
    }
}
