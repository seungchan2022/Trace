import Foundation

/// 기록 상세 포인트 구간 표의 한 행(스펙 §2.5) — "시작→① 1.24 km / ①→② 0.87 km / ③→종료 0.42 km"
struct RunWaypointSegment: Equatable, Sendable {
    /// 1부터 시작하는 구간 번호 — n번 구간 = (n−1)번 포인트(0이면 시작)→n번 포인트(또는 종료)
    let index: Int
    let distanceMeters: Double
    /// 마지막 구간(마지막 포인트→종료) 여부 — 라벨 표기용
    let endsAtFinish: Bool
}

/// 포인트 누적 거리의 차분으로 구간 목록 파생 — 합계는 항상 totalDistanceMeters와
/// 일치한다(telescoping, 스펙 §2.5). 포인트 삭제 후에도 같은 함수로 재계산하면 된다.
enum RunWaypointSegmentsCalculator {
    static func segments(
        waypoints: [RunWaypoint], totalDistanceMeters: Double
    ) -> [RunWaypointSegment] {
        guard waypoints.isEmpty == false else { return [] }
        var result: [RunWaypointSegment] = []
        var previousCumulative: Double = 0
        for (offset, waypoint) in waypoints.enumerated() {
            result.append(RunWaypointSegment(
                index: offset + 1,
                distanceMeters: waypoint.totalDistanceMeters - previousCumulative,
                endsAtFinish: false
            ))
            previousCumulative = waypoint.totalDistanceMeters
        }
        result.append(RunWaypointSegment(
            index: waypoints.count + 1,
            distanceMeters: totalDistanceMeters - previousCumulative,
            endsAtFinish: true
        ))
        return result
    }
}
