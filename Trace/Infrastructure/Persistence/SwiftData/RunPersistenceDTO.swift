import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (코스 DTO와 동일 원칙, 스펙 §2).
// 미래 심박·케이던스는 Run에 스트림 배열 하나를 옆에 추가 + version 증가로 끝난다(additive).
enum RunPersistenceDTO: Sendable {
    // v2: pauses 추가(additive). v1 blob은 pauses 부재 → 빈 배열로 해독(하위호환).
    static let currentVersion = 2

    struct Sample: Codable {
        let t: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double
    }

    struct Pause: Codable {
        let s: Date
        let e: Date
    }

    struct Run: Codable {
        let version: Int
        let samples: [Sample]
        let pauses: [Pause]?
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension RunPersistenceDTO.Sample {
    init(_ sample: SavedRunSample) {
        self.init(
            t: sample.timestamp, lat: sample.latitude, lon: sample.longitude,
            alt: sample.altitudeMeters, spd: sample.speedMetersPerSecond
        )
    }

    var domain: SavedRunSample {
        SavedRunSample(
            timestamp: t, latitude: lat, longitude: lon,
            altitudeMeters: alt, speedMetersPerSecond: spd
        )
    }
}

extension RunPersistenceDTO.Pause {
    init(_ interval: RunPauseInterval) {
        self.init(s: interval.start, e: interval.end)
    }

    var domain: RunPauseInterval {
        RunPauseInterval(start: s, end: e)
    }
}
