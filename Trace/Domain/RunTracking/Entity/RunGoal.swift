import Foundation

/// 러닝 목표 — 자유/거리/시간 3모드(스펙 §3.4). 달성해도 트래킹은 계속되고 종료는 사용자가 한다.
enum RunGoal: Equatable, Sendable {
    case open
    case distance(meters: Double)
    case time(seconds: TimeInterval)

    /// 진행률(0…, 1 초과 = 초과분) — open·0 이하 목표값은 nil.
    /// 시간 목표는 활동 시간(일시정지 제외, 스펙 §3.1) 기준.
    func progressFraction(distanceMeters: Double, activeSeconds: TimeInterval) -> Double? {
        switch self {
        case .open:
            return nil
        case .distance(let meters):
            guard meters > 0 else { return nil }
            return distanceMeters / meters
        case .time(let seconds):
            guard seconds > 0 else { return nil }
            return activeSeconds / seconds
        }
    }
}
