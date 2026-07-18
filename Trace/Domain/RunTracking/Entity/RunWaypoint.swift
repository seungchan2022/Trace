import Foundation

/// 러닝 중 사용자가 찍은 포인트(스펙 §2.4) — 타임스탬프(원본 사실) + 좌표(지도 마커용,
/// 탭 시점의 마지막 유효 샘플 스냅샷) + 그 시점 누적 거리(표시용 캐시).
/// 구간 거리는 별도 계산 없이 누적 거리의 차분으로 파생된다 — 일시정지 제외·정확도 필터 등
/// 기존 적산 규칙을 자동 상속(스펙 §2.2).
struct RunWaypoint: Equatable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let totalDistanceMeters: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }
}

extension [RunWaypoint] {
    /// 마지막 포인트의 구간 거리(직전 포인트, 없으면 시작 기준) — 발화·카드·Live Activity 공용
    var lastSegmentMeters: Double? {
        guard let last else { return nil }
        return last.totalDistanceMeters - (dropLast().last?.totalDistanceMeters ?? 0)
    }
}
