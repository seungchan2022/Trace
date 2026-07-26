import SwiftUI

/// 기록 탭 전용 표면·차트 대비 정책.
/// 다른 화면의 테두리 토큰을 바꾸지 않아 기존 화면의 시각 밀도를 보존한다.
struct HistoryPageAppearance: Equatable {
    enum Background: Equatable {
        case surface2
    }

    let background: Background
    let chartGridOpacity: Double

    static let standard = Self(background: .surface2, chartGridOpacity: 0.72)

    var backgroundColor: Color {
        switch background {
        case .surface2: return DesignToken.Color.surface2
        }
    }

    var chartGridColor: Color {
        DesignToken.Color.ink2.opacity(chartGridOpacity)
    }
}
