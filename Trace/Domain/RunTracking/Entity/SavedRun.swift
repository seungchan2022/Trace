import Foundation

/// 저장된 러닝 기록의 목록용 요약 — 전부 스토어 컬럼에서 나오며 blob을 디코드하지 않는다(스펙 §2).
/// Hashable은 목록→상세 navigationDestination(for:)의 요구사항.
struct SavedRunSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let distanceMeters: Double
    /// 벽시계 경과 시간(초) — 트래킹 화면·요약이 보여준 시간과 같은 기준
    let duration: TimeInterval
    let elevationGainMeters: Double

    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 0, duration > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }
}

/// 저장용 샘플 — `RunSample`에서 필터 판정 전용인 정확도 2필드를 뺀 5필드(스펙 §2).
/// `RunSample`을 재사용하지 않는 이유: 로드 시 가짜 정확도 값을 채워 넣는 왜곡을 피한다.
struct SavedRunSample: Equatable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let speedMetersPerSecond: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }

    init(
        timestamp: Date, latitude: Double, longitude: Double,
        altitudeMeters: Double, speedMetersPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }

    init(_ sample: RunSample) {
        self.init(
            timestamp: sample.timestamp, latitude: sample.latitude, longitude: sample.longitude,
            altitudeMeters: sample.altitudeMeters, speedMetersPerSecond: sample.speedMetersPerSecond
        )
    }
}

/// 저장된 러닝 기록 전체 — 상세 화면 단건 조회 전용(스펙 §2).
struct SavedRun: Equatable, Sendable {
    let summary: SavedRunSummary
    let samples: [SavedRunSample]
    /// 일시정지 구간(시각 쌍) — 샘플 간격에서 파생 불가(GPS 끊김과 구분 안 됨)라 명시 저장(MVP14 §4)
    let pauses: [RunPauseInterval]
    /// 이번 러닝의 목표 — 상세 화면 "목표 5 km" 표시용(스펙 §4-3). 자유 러닝은 .open
    let goal: RunGoal

    init(
        summary: SavedRunSummary, samples: [SavedRunSample],
        pauses: [RunPauseInterval] = [], goal: RunGoal = .open
    ) {
        self.summary = summary
        self.samples = samples
        self.pauses = pauses
        self.goal = goal
    }
}
