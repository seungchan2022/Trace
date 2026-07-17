import Foundation

/// 목표 표시 라벨 — 발화(RunAnnouncementBuilder)와 달리 화면용 짧은 표기
enum RunGoalFormatter {
    /// .open은 nil(라벨 자체를 안 그린다), 5000 → "5 km 목표", 1800초 → "30분 목표"
    static func label(_ goal: RunGoal) -> String? {
        switch goal {
        case .open:
            return nil
        case .distance(let meters):
            return "\(distanceText(meters)) 목표"
        case .time(let seconds):
            return "\(Int(seconds / 60))분 목표"
        }
    }

    private static func distanceText(_ meters: Double) -> String {
        let km = meters / 1000
        if km == km.rounded() { return "\(Int(km)) km" }
        return String(format: "%.1f km", km)
    }
}
