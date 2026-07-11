import UIKit

enum SegmentPalette {
    static func color(at index: Int) -> UIColor {
        UIColor(named: "Seg\(index % 6)") ?? .systemBlue
    }
}
