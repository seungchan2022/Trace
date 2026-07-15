import XCTest
@testable import Trace

final class RunTrackTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// 위도 1도 ≈ 111,320m를 이용해 대략 100m 북쪽 이동 샘플을 만든다.
    private func sample(
        at seconds: TimeInterval,
        latOffsetMeters: Double = 0,
        altitude: Double = 10,
        speed: Double = 3,
        vAcc: Double = 5
    ) -> RunSample {
        RunSample(
            timestamp: base.addingTimeInterval(seconds),
            latitude: 37.5666 + latOffsetMeters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: altitude,
            speedMetersPerSecond: speed,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: vAcc
        )
    }

    func test_거리와_시간이_누적된다() {
        var track = RunTrack()
        track.append(sample(at: 0, latOffsetMeters: 0))
        track.append(sample(at: 10, latOffsetMeters: 30))
        track.append(sample(at: 20, latOffsetMeters: 60))
        XCTAssertEqual(track.totalDistanceMeters, 60, accuracy: 1)
        XCTAssertEqual(track.duration, 20, accuracy: 0.001)
    }

    func test_평균페이스는_전체거리와_시간으로_계산된다() {
        var track = RunTrack()
        track.append(sample(at: 0))
        track.append(sample(at: 60, latOffsetMeters: 200))
        // 200m를 60초 → 1km당 300초
        XCTAssertEqual(track.averagePaceSecondsPerKm ?? -1, 300, accuracy: 5)
    }

    func test_샘플이_하나이하면_평균페이스는_nil() {
        var track = RunTrack()
        XCTAssertNil(track.averagePaceSecondsPerKm)
        track.append(sample(at: 0))
        XCTAssertNil(track.averagePaceSecondsPerKm)
    }

    func test_현재페이스는_최근30초_유효속도의_평균이다() {
        var track = RunTrack()
        track.append(sample(at: 0, speed: 10))            // 윈도 밖(마지막 기준 40초 전)
        track.append(sample(at: 20, speed: -1))           // 음수 속도는 무시
        track.append(sample(at: 30, speed: 2))
        track.append(sample(at: 40, speed: 4))
        // 유효 속도 = [2, 4] → 평균 3m/s → 1000/3 ≈ 333초/km
        XCTAssertEqual(track.currentPaceSecondsPerKm ?? -1, 1000.0 / 3.0, accuracy: 1)
    }

    func test_현재페이스는_유효속도가_없으면_nil() {
        var track = RunTrack()
        track.append(sample(at: 0, speed: -1))
        XCTAssertNil(track.currentPaceSecondsPerKm)
    }

    func test_고도노이즈는_임계값미만이라_상승에_포함되지_않는다() {
        var track = RunTrack()
        // ±2m 진동 — 연속 상승 누적이 3m를 못 넘음
        for (i, alt) in [10.0, 12.0, 10.0, 12.0, 10.0].enumerated() {
            track.append(sample(at: Double(i * 10), altitude: alt))
        }
        XCTAssertEqual(track.elevationGainMeters, 0, accuracy: 0.001)
    }

    func test_임계값을_넘는_연속상승은_상승량에_누적된다() {
        var track = RunTrack()
        // 10 → 12 → 14.5: 연속 상승 4.5m ≥ 3m
        for (i, alt) in [10.0, 12.0, 14.5].enumerated() {
            track.append(sample(at: Double(i * 10), altitude: alt))
        }
        XCTAssertEqual(track.elevationGainMeters, 4.5, accuracy: 0.001)
    }

    func test_수직정확도가_나쁜_샘플은_고도계산에서_제외된다() {
        var track = RunTrack()
        track.append(sample(at: 0, altitude: 10))
        track.append(sample(at: 10, altitude: 100, vAcc: -1))   // 무효
        track.append(sample(at: 20, altitude: 100, vAcc: 50))   // 10m 초과
        XCTAssertEqual(track.elevationGainMeters, 0, accuracy: 0.001)
    }

    func test_markGap_후_첫_샘플은_거리를_가산하지_않는다() {
        var track = RunTrack()
        track.append(sample(at: 0, latOffsetMeters: 0))
        track.append(sample(at: 30, latOffsetMeters: 100))
        let beforeGap = track.totalDistanceMeters
        track.markGap()
        // 일시정지 중 500m 이동했다고 가정 — 이 구간은 거리에 안 들어가야 한다
        track.append(sample(at: 300, latOffsetMeters: 600))
        XCTAssertEqual(track.totalDistanceMeters, beforeGap, accuracy: 1.0)
        // gap 다음 샘플부터는 다시 정상 가산
        track.append(sample(at: 330, latOffsetMeters: 700))
        XCTAssertEqual(track.totalDistanceMeters, beforeGap + 100, accuracy: 2.0)
    }
}
