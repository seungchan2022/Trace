import Foundation

/// 포인트 경계에서 잘린 경로 구간 — 기록 상세 지도의 구간별 색상 폴리라인용(ui-direction §6).
/// `index`는 `RunWaypointSegment.index`와 같은 1-기반 번호라 지도와 구간 표가 같은 팔레트 색을 쓴다.
struct RunPathSegment: Equatable, Sendable {
    let index: Int
    let coordinates: [CourseCoordinate]
}

enum RunPathSegmentsCalculator {
    /// 샘플 스트림을 포인트 타임스탬프 경계에서 자른다.
    /// 경계 샘플은 앞뒤 구간이 함께 포함해(공유) 선이 끊겨 보이지 않는다.
    /// 포인트가 없으면 빈 배열 — 뷰가 현행 단일색 폴리라인으로 폴백한다(ui-direction §6).
    static func segments(samples: [SavedRunSample], waypoints: [RunWaypoint]) -> [RunPathSegment] {
        guard waypoints.isEmpty == false, samples.count >= 2 else { return [] }
        var result: [RunPathSegment] = []
        var startIndex = 0
        for (offset, waypoint) in waypoints.enumerated() {
            guard let endIndex = samples.lastIndex(where: { $0.timestamp <= waypoint.timestamp })
            else { continue }
            if endIndex > startIndex {
                result.append(RunPathSegment(
                    index: offset + 1,
                    coordinates: samples[startIndex...endIndex].map(\.coordinate)
                ))
            }
            startIndex = max(startIndex, endIndex)
        }
        // 마지막 포인트 → 종료 구간. 번호는 표의 마지막 행(waypoints.count + 1)과 일치한다.
        if startIndex < samples.count - 1 {
            result.append(RunPathSegment(
                index: waypoints.count + 1,
                coordinates: samples[startIndex...].map(\.coordinate)
            ))
        }
        return result
    }
}
