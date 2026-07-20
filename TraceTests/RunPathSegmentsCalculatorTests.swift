import XCTest
@testable import Trace

final class RunPathSegmentsCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(offset: TimeInterval, lat: Double) -> SavedRunSample {
        SavedRunSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat, longitude: 127.0,
            altitudeMeters: 10, speedMetersPerSecond: 3
        )
    }

    private func waypoint(offset: TimeInterval, lat: Double) -> RunWaypoint {
        RunWaypoint(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat, longitude: 127.0, totalDistanceMeters: offset
        )
    }

    func test_포인트가_없으면_빈_배열이다() {
        // 뷰가 단일색 폴백으로 그리도록 빈 배열을 준다(ui-direction §6)
        let samples = [sample(offset: 0, lat: 37.50), sample(offset: 10, lat: 37.51)]
        XCTAssertEqual(RunPathSegmentsCalculator.segments(samples: samples, waypoints: []), [])
    }

    func test_포인트_1개는_구간_2개로_나뉜다() {
        let samples = (0...4).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let segments = RunPathSegmentsCalculator.segments(
            samples: samples, waypoints: [waypoint(offset: 20, lat: 37.52)]
        )
        XCTAssertEqual(segments.map(\.index), [1, 2])
    }

    func test_이웃_구간은_경계_좌표를_공유해_선이_끊기지_않는다() {
        let samples = (0...4).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let segments = RunPathSegmentsCalculator.segments(
            samples: samples, waypoints: [waypoint(offset: 20, lat: 37.52)]
        )
        XCTAssertEqual(segments[0].coordinates.last, segments[1].coordinates.first)
    }

    func test_구간_번호는_구간_표와_같은_1기반_번호다() {
        // 지도 색과 표 색이 대응하려면 RunWaypointSegmentsCalculator와 번호 체계가 같아야 한다
        let samples = (0...6).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let waypoints = [waypoint(offset: 20, lat: 37.52), waypoint(offset: 40, lat: 37.54)]
        let paths = RunPathSegmentsCalculator.segments(samples: samples, waypoints: waypoints)
        let rows = RunWaypointSegmentsCalculator.segments(waypoints: waypoints, totalDistanceMeters: 60)
        XCTAssertEqual(paths.map(\.index), rows.map(\.index))
    }

    func test_샘플이_2개_미만이면_빈_배열이다() {
        XCTAssertEqual(
            RunPathSegmentsCalculator.segments(
                samples: [sample(offset: 0, lat: 37.5)], waypoints: [waypoint(offset: 0, lat: 37.5)]
            ),
            []
        )
    }
}
