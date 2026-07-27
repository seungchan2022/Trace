import XCTest
@testable import Trace

/// 저장된 러닝 기록 blob의 JSON 키를 고정한다.
///
/// `RunPersistenceDTO`의 필드 이름을 바꾸면 Swift는 조용히 JSON 키도 함께 바꾼다.
/// 그러면 사용자 기기에 이미 쌓인 기록을 못 읽게 되는데, 새로 설치한 환경에서는
/// 아무 증상이 없어서 눈으로는 절대 못 잡는다. 이 테스트가 그 경로를 막는다.
///
/// **이 테스트가 실패하면 이름을 되돌리거나 `CodingKeys`로 키를 보존할 것.**
/// 저장 포맷을 진짜로 바꾸려면 `currentVersion`을 올리고 마이그레이션을 설계해야 한다.
final class RunPersistenceDTOWireFormatTests: XCTestCase {

    /// v4 포맷으로 저장된 blob. 실제 앱이 써온 키 이름 그대로다.
    private let storedBlob = Data("""
    {
      "version": 4,
      "samples": [
        {"t": 700000000, "lat": 37.5665, "lon": 126.9780, "alt": 38.0, "spd": 2.5}
      ],
      "pauses": [
        {"s": 700000100, "e": 700000160}
      ],
      "goal": {"type": "distance", "value": 5000.0},
      "waypoints": [
        {"t": 700000200, "lat": 37.5670, "lon": 126.9785, "d": 1000.0}
      ]
    }
    """.utf8)

    func test_저장된_blob이_그대로_해독된다() throws {
        let decoder = JSONDecoder()
        let run = try decoder.decode(RunPersistenceDTO.Run.self, from: storedBlob)

        XCTAssertEqual(run.version, 4)

        let sample = try XCTUnwrap(run.samples.first)
        XCTAssertEqual(sample.domain.timestamp.timeIntervalSinceReferenceDate, 700_000_000, accuracy: 0.001)
        XCTAssertEqual(sample.domain.latitude, 37.5665, accuracy: 0.00001)
        XCTAssertEqual(sample.domain.altitudeMeters, 38.0, accuracy: 0.001)
        XCTAssertEqual(sample.domain.speedMetersPerSecond, 2.5, accuracy: 0.001)

        let pause = try XCTUnwrap(run.pauses?.first)
        XCTAssertEqual(pause.domain.start.timeIntervalSinceReferenceDate, 700_000_100, accuracy: 0.001)
        XCTAssertEqual(pause.domain.end.timeIntervalSinceReferenceDate, 700_000_160, accuracy: 0.001)

        let waypoint = try XCTUnwrap(run.waypoints?.first)
        XCTAssertEqual(waypoint.domain.timestamp.timeIntervalSinceReferenceDate, 700_000_200, accuracy: 0.001)
        XCTAssertEqual(waypoint.domain.totalDistanceMeters, 1000.0, accuracy: 0.001)
    }

    func test_새로_저장한_blob도_같은_키를_쓴다() throws {
        let run = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: [RunPersistenceDTO.Sample(
                SavedRunSample(
                    timestamp: Date(timeIntervalSinceReferenceDate: 700_000_000),
                    latitude: 37.5665, longitude: 126.9780,
                    altitudeMeters: 38.0, speedMetersPerSecond: 2.5
                )
            )],
            pauses: [RunPersistenceDTO.Pause(
                RunPauseInterval(
                    start: Date(timeIntervalSinceReferenceDate: 700_000_100),
                    end: Date(timeIntervalSinceReferenceDate: 700_000_160)
                )
            )],
            goal: RunPersistenceDTO.Goal(.distance(meters: 5000)),
            waypoints: [RunPersistenceDTO.Waypoint(
                RunWaypoint(
                    timestamp: Date(timeIntervalSinceReferenceDate: 700_000_200),
                    latitude: 37.5670, longitude: 126.9785,
                    totalDistanceMeters: 1000.0
                )
            )]
        )

        let encoded = try JSONEncoder().encode(run)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        let sample = try XCTUnwrap((json["samples"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(sample.keys), ["t", "lat", "lon", "alt", "spd"])

        let pause = try XCTUnwrap((json["pauses"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(pause.keys), ["s", "e"])

        let waypoint = try XCTUnwrap((json["waypoints"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(waypoint.keys), ["t", "lat", "lon", "d"])
    }
}
