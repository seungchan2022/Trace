import SwiftUI
import UIKit

enum SegmentPalette {
    static func color(at index: Int) -> UIColor {
        UIColor(named: "Seg\(index % 6)") ?? .systemBlue
    }

    /// SwiftUI Map/스와치용 — 기록 상세의 구간 폴리라인과 구간 표가 같은 색을 쓴다(ui-direction §6)
    static func swiftUIColor(at index: Int) -> Color {
        Color(uiColor: color(at: index))
    }
}
