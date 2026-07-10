import UIKit

nonisolated enum SegmentPalette {
    private static let colors: [UIColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal, .systemPink,
    ]

    static func color(at index: Int) -> UIColor {
        colors[index % colors.count]
    }
}
