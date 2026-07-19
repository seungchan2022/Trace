import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case course
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course: return "코스"
        case .run: return "러닝"
        }
    }

    var systemImage: String {
        switch self {
        case .course: return "map"
        case .run: return "figure.run"
        }
    }

    // 킥오프 §2.2: 러닝 플로우(시작~요약 닫기 전) 동안 앱 내 탭 전환 진입점 자체를 제거한다.
    // summary도 숨김 — 요약 화면을 닫아 idle로 돌아와야 탭바가 복귀한다.
    static func isTabBarHidden(runState: RunSession.State) -> Bool {
        runState != .idle
    }
}
