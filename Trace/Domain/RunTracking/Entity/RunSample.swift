import Foundation

/// 러닝 트래킹의 원시 단위 — "기록 = 타임스탬프 샘플 스트림" 원칙(스펙 §2).
/// 정확도 두 필드는 필터 판정 전용(전송용)이며 저장 대상이 아니다.
struct RunSample: Equatable, Sendable, Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    /// CLLocation.speed 그대로 — 유효하지 않으면 음수
    let speedMetersPerSecond: Double
    let horizontalAccuracyMeters: Double
    let verticalAccuracyMeters: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }
}
