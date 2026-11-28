import AppKit
import QuartzCore

/// A made-up slide (a title, four bullets and a bar chart) to show the
/// pointer on: in the settings window's preview and in `--snapshot-spotlight`.
enum SampleSlide {
    /// The slide is drawn in this space, from its top left.
    static let size = CGSize(width: 640, height: 360)

    /// Just above the tallest bar, on white so a red laser shows: where the
    /// preview points when the mouse is elsewhere.
    static let aboveTallestBar = CGPoint(x: 568, y: 96)

    /// A layer `size` big with the slide in it. Its geometry is flipped, so
    /// points inside it are measured from the top left, like `aboveTallestBar`.
    static func makeLayer(title text: String, contentsScale: CGFloat) -> CALayer {
        let back = CALayer()
        back.bounds = CGRect(origin: .zero, size: size)
        back.isGeometryFlipped = true
        back.backgroundColor = NSColor.white.cgColor
        back.masksToBounds = true

        let title = CATextLayer()
        title.string = text
        title.fontSize = 30
        title.foregroundColor = NSColor(white: 0.1, alpha: 1).cgColor
        title.contentsScale = contentsScale
        title.frame = CGRect(x: 40, y: 28, width: 560, height: 40)
        back.addSublayer(title)

        for row in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor(white: 0.55, alpha: 1).cgColor
            bar.frame = CGRect(x: 40, y: 100 + CGFloat(row) * 44, width: [260, 220, 280, 180][row], height: 14)
            back.addSublayer(bar)
        }
        for col in 0..<4 {
            let h = [90, 140, 120, 190][col]
            let bar = CALayer()
            bar.backgroundColor = [NSColor.systemBlue, .systemGreen, .systemOrange, .systemRed][col].cgColor
            bar.frame = CGRect(x: 380 + CGFloat(col) * 56, y: 300 - CGFloat(h), width: 40, height: CGFloat(h))
            back.addSublayer(bar)
        }
        return back
    }
}
