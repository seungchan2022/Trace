import XCTest
@testable import Trace

nonisolated final class SavedRunTests: XCTestCase {
    func test_평균페이스는_거리와_시간에서_계산된다() {
        let summary = SavedRunSummary(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1000),
            distanceMeters: 2000, duration: 720, elevationGainMeters: 5
        )
        // 720초 / 2km = 360초/km
        XCTAssertEqual(summary.averagePaceSecondsPerKm, 360)
    }

    func test_거리나_시간이_0이면_평균페이스는_nil() {
        let zeroDistance = SavedRunSummary(
            id: UUID(), startedAt: Date(), distanceMeters: 0, duration: 720, elevationGainMeters: 0
        )
        let zeroDuration = SavedRunSummary(
            id: UUID(), startedAt: Date(), distanceMeters: 2000, duration: 0, elevationGainMeters: 0
        )
        XCTAssertNil(zeroDistance.averagePaceSecondsPerKm)
        XCTAssertNil(zeroDuration.averagePaceSecondsPerKm)
    }

    func test_RunSample에서_변환시_정확도는_버려지고_5필드만_남는다() {
        let sample = RunSample(
            timestamp: Date(timeIntervalSince1970: 1000), latitude: 37.5, longitude: 127.0,
            altitudeMeters: 20, speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5, verticalAccuracyMeters: 8
        )
        let saved = SavedRunSample(sample)
        XCTAssertEqual(saved.timestamp, sample.timestamp)
        XCTAssertEqual(saved.latitude, 37.5)
        XCTAssertEqual(saved.longitude, 127.0)
        XCTAssertEqual(saved.altitudeMeters, 20)
        XCTAssertEqual(saved.speedMetersPerSecond, 3)
        XCTAssertEqual(saved.coordinate, CourseCoordinate(latitude: 37.5, longitude: 127.0))
    }
}
