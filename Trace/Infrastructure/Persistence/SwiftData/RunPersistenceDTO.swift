import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (코스 DTO와 동일 원칙, 스펙 §2).
// 미래 심박·케이던스는 Run에 스트림 배열 하나를 옆에 추가 + version 증가로 끝난다(additive).
//
// ⚠️ 저장 키는 CodingKeys가 고정한다(용량을 아끼려 압축한 이름이다). 필드 이름은 자유롭게
// 바꿔도 되지만 CodingKeys의 문자열을 바꾸면 이미 저장된 기록을 못 읽는다.
// RunPersistenceDTOWireFormatTests가 이를 지킨다.
enum RunPersistenceDTO: Sendable {
    // v4: waypoints 추가(additive). v3 이하 blob은 waypoints 부재 → 빈 배열로 해독(하위호환).
    // v3: goal 추가(additive). v2 이하 blob은 goal 부재 → .open으로 해독(하위호환).
    static let currentVersion = 4

    struct Sample: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double

        // 저장된 blob의 키는 압축형이다. 필드 이름을 바꿔도 여기가 포맷을 고정한다.
        enum CodingKeys: String, CodingKey {
            case timestamp = "t"
            case lat, lon, alt, spd
        }
    }

    struct Pause: Codable {
        let start: Date
        let end: Date

        enum CodingKeys: String, CodingKey {
            case start = "s"
            case end = "e"
        }
    }

    struct Goal: Codable {
        let type: String // "distance" | "time"
        let value: Double
    }

    struct Waypoint: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        /// 탭 시점 누적 거리(m) — 표시용 캐시(스펙 §2.4)
        let distanceMeters: Double

        enum CodingKeys: String, CodingKey {
            case timestamp = "t"
            case lat, lon
            case distanceMeters = "d"
        }
    }

    struct Run: Codable {
        let version: Int
        let samples: [Sample]
        let pauses: [Pause]?
        let goal: Goal?
        let waypoints: [Waypoint]?
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension RunPersistenceDTO.Sample {
    init(_ sample: SavedRunSample) {
        self.init(
            timestamp: sample.timestamp, lat: sample.latitude, lon: sample.longitude,
            alt: sample.altitudeMeters, spd: sample.speedMetersPerSecond
        )
    }

    var domain: SavedRunSample {
        SavedRunSample(
            timestamp: timestamp, latitude: lat, longitude: lon,
            altitudeMeters: alt, speedMetersPerSecond: spd
        )
    }
}

extension RunPersistenceDTO.Pause {
    init(_ interval: RunPauseInterval) {
        self.init(start: interval.start, end: interval.end)
    }

    var domain: RunPauseInterval {
        RunPauseInterval(start: start, end: end)
    }
}

extension RunPersistenceDTO.Goal {
    init?(_ goal: RunGoal) {
        switch goal {
        case .open: return nil
        case .distance(let meters): self.init(type: "distance", value: meters)
        case .time(let seconds): self.init(type: "time", value: seconds)
        }
    }

    var domain: RunGoal {
        switch type {
        case "distance": .distance(meters: value)
        case "time": .time(seconds: value)
        default: .open // 알 수 없는 타입은 목표 표시만 포기(우아한 강등)
        }
    }
}

extension RunPersistenceDTO.Waypoint {
    init(_ waypoint: RunWaypoint) {
        self.init(timestamp: waypoint.timestamp, lat: waypoint.latitude,
                  lon: waypoint.longitude, distanceMeters: waypoint.totalDistanceMeters)
    }

    var domain: RunWaypoint {
        RunWaypoint(timestamp: timestamp, latitude: lat, longitude: lon,
                    totalDistanceMeters: distanceMeters)
    }
}
