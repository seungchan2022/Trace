import SwiftUI

enum DesignToken {
    enum Color {
        static let ink = SwiftUI.Color("Ink")
        static let ink2 = SwiftUI.Color("Ink2")
        static let surface = SwiftUI.Color("Surface")
        static let surface2 = SwiftUI.Color("Surface2")
        // 현재 미사용 — 향후 마일스톤에서 소비될 수 있어 보류 (reserved for future use).
        static let border = SwiftUI.Color("Border")
        // 현재 미사용 — 실제 컴포넌트는 .ultraThinMaterial/.regularMaterial을 직접 써서 대체됨.
        static let glass = SwiftUI.Color("Glass")
        static let glassBorder = SwiftUI.Color("GlassBorder")
        static let accent = SwiftUI.Color("AccentColor")
        static let accentInk = SwiftUI.Color("AccentInk")
        static let danger = SwiftUI.Color("Danger")
        // 현재 미사용 — MKUserLocation 재색상은 안정적 공개 API가 없어 보류 (MapViewRepresentable 참고).
        static let locBlue = SwiftUI.Color("LocBlue")
        static let grabber = SwiftUI.Color("Grabber")
        // 현재 미사용 — 향후 마일스톤에서 소비될 수 있어 보류 (reserved for future use).
        static let markerFill = SwiftUI.Color("MarkerFill")
    }

    enum Corner {
        // 현재 미사용 — 향후 마일스톤에서 소비될 수 있어 보류 (reserved for future use).
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
        /// 러닝 트래킹 화면의 주인공 숫자(ui-direction §3) — monospacedDigit()과 함께 써서 자릿수 흔들림을 막는다
        static let runDistanceHero = Font.system(size: 84, weight: .bold, design: .rounded)
        static let runDistanceUnit = Font.system(size: 20, weight: .semibold, design: .rounded)
        /// 주인공 숫자 위 보조 행(시간·평균 페이스)
        static let runSecondaryStat = Font.system(size: 28, weight: .semibold, design: .rounded)
        /// 카운트다운 3-2-1
        static let runCountdown = Font.system(size: 160, weight: .heavy, design: .rounded)
        /// 대기 화면 대형 시작 버튼 라벨
        static let runStartButton = Font.system(size: 22, weight: .bold, design: .rounded)
    }
}
