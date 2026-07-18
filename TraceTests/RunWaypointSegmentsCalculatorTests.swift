import XCTest
@testable import Trace

final class RunWaypointSegmentsCalculatorTests: XCTestCase {
    private func waypoint(cumulativeMeters: Double) -> RunWaypoint {
        RunWaypoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + cumulativeMeters),
            latitude: 37.5, longitude: 127.0, totalDistanceMeters: cumulativeMeters
        )
    }

    func test_포인트가_없으면_빈_목록() {
        XCTAssertEqual(
            RunWaypointSegmentsCalculator.segments(waypoints: [], totalDistanceMeters: 5000),
            []
        )
    }

    func test_포인트_1개는_구간_2개다() {
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: [waypoint(cumulativeMeters: 1240)], totalDistanceMeters: 2000
        )
        XCTAssertEqual(segments, [
            RunWaypointSegment(index: 1, distanceMeters: 1240, endsAtFinish: false),
            RunWaypointSegment(index: 2, distanceMeters: 760, endsAtFinish: true)
        ])
    }

    func test_포인트_n개의_구간_합계는_총거리와_일치한다() {
        // 스펙 §2.5: 마지막 포인트~종료 구간까지 넣어 합계 = 총거리(telescoping)
        let waypoints = [
            waypoint(cumulativeMeters: 1240),
            waypoint(cumulativeMeters: 2110),
            waypoint(cumulativeMeters: 4580)
        ]
        let total = 5000.0
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: waypoints, totalDistanceMeters: total
        )
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.map(\.distanceMeters).reduce(0, +), total, accuracy: 1e-9)
        XCTAssertEqual(segments.last?.endsAtFinish, true)
        XCTAssertEqual(segments.map(\.index), [1, 2, 3, 4])
    }

    func test_연타로_같은_지점에_찍힌_0m_구간도_행으로_유지된다() {
        // 연타 방지 임계값 없음 — 0.00 km 구간 허용(스펙 §2.2)
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: [waypoint(cumulativeMeters: 500), waypoint(cumulativeMeters: 500)],
            totalDistanceMeters: 1000
        )
        XCTAssertEqual(segments.map(\.distanceMeters), [500, 0, 500])
    }
}
