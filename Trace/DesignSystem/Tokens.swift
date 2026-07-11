import SwiftUI

enum DesignToken {
    enum Color {
        static let ink = SwiftUI.Color("Ink")
        static let ink2 = SwiftUI.Color("Ink2")
        static let surface = SwiftUI.Color("Surface")
        static let surface2 = SwiftUI.Color("Surface2")
        static let border = SwiftUI.Color("Border")
        static let glass = SwiftUI.Color("Glass")
        static let glassBorder = SwiftUI.Color("GlassBorder")
        static let accent = SwiftUI.Color("AccentColor")
        static let accentInk = SwiftUI.Color("AccentInk")
        static let danger = SwiftUI.Color("Danger")
        static let locBlue = SwiftUI.Color("LocBlue")
        static let grabber = SwiftUI.Color("Grabber")
        static let markerFill = SwiftUI.Color("MarkerFill")
    }

    enum Corner {
        static let chrome: CGFloat = 15
        static let sheetTop: CGFloat = 26
        static let row: CGFloat = 15
    }

    enum Size {
        static let fab: CGFloat = 44
        static let topBarButton: CGFloat = 42
        static let screenMargin: CGFloat = 14
        static let sheetPadding: CGFloat = 20
    }

    enum Typography {
        static let distanceHeadline = Font.system(size: 44, weight: .bold, design: .rounded)
        static let distanceUnit = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let segmentRowDistance = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let segmentRowTitle = Font.system(size: 15, weight: .semibold)
        static let segmentRowSubtitle = Font.system(size: 12.5, weight: .medium)
        static let sectionLabel = Font.system(size: 12, weight: .semibold)
        static let chip = Font.system(size: 13, weight: .semibold)
        static let chipError = Font.system(size: 13, weight: .bold)
        static let subtitle = Font.system(size: 13.5, weight: .medium)
    }
}
