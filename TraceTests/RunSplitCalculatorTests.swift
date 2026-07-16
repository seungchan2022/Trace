import XCTest
@testable import Trace

final class RunSplitCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    /// 북쪽으로 meters만큼 이동한 지점의 t초 시점 샘플 (위도 1도 ≈ 111,320m)
    private func sample(t: TimeInterval, meters: Double) -> SavedRunSample {
        SavedRunSample(
            timestamp: base.addingTimeInterval(t),
            latitude: 37.5666 + meters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3
        )
    }

    private func pause(from: TimeInterval, to: TimeInterval) -> RunPauseInterval {
        RunPauseInterval(start: base.addingTimeInterval(from), end: base.addingTimeInterval(to))
    }

    func test_빈샘플과_단일샘플은_빈결과() {
        XCTAssertEqual(RunSplitCalculator.splits(samples: [], pauses: []), .empty)
        XCTAssertEqual(
            RunSplitCalculator.splits(samples: [sample(t: 0, meters: 0)], pauses: []),
            .empty
        )
    }

    func test_1km미만은_미완성구간만() throws {
        // 500m를 150초에 (5분/km 페이스)
        let samples = stride(from: 0.0, through: 500, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertTrue(result.completed.isEmpty)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.index, 1)
        XCTAssertEqual(partial.distanceMeters, 500, accuracy: 5)
        XCTAssertEqual(partial.durationSeconds, 150, accuracy: 2)
    }

    func test_일정속도_2km는_같은시간의_스플릿2개() throws {
        // 100m/30초 간격으로 2,050m (5분/km 일정 속도)
        let samples = stride(from: 0.0, through: 2050, by: 50).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 2)
        XCTAssertEqual(result.completed[0].index, 1)
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 3)
        XCTAssertEqual(result.completed[1].index, 2)
        XCTAssertEqual(result.completed[1].durationSeconds, 300, accuracy: 3)
        // 완성 구간의 페이스는 구간 시간과 같다(정확히 1km이므로)
        XCTAssertEqual(result.completed[0].paceSecondsPerKm, result.completed[0].durationSeconds)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 50, accuracy: 5)
    }

    func test_경계통과시각은_쌍안에서_거리비례로_보간된다() {
        // 950m까지 5분/km로 온 뒤, 마지막 쌍(900→1100m)이 60초 — 경계(1000m)는 쌍의 절반 지점
        var samples = stride(from: 0.0, through: 900, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        samples.append(sample(t: 900 * 0.3 + 60, meters: 1100))
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 1)
        // 270초(900m 도달) + 60초의 절반 = 300초 부근
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
    }

    func test_일시정지구간은_거리도_시간도_제외된다() throws {
        // 600m(t=0~180) → 일시정지 300초(t=180~480, 제자리) → 600m(t=480~660)
        var samples = stride(from: 0.0, through: 600, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        samples.append(sample(t: 480, meters: 600)) // 재개 직후 첫 샘플(제자리)
        samples.append(contentsOf: stride(from: 700.0, through: 1200, by: 100).map {
            sample(t: 480 + ($0 - 600) * 0.3, meters: $0)
        })
        let pauses = [pause(from: 180, to: 480)]
        let result = RunSplitCalculator.splits(samples: samples, pauses: pauses)
        XCTAssertEqual(result.completed.count, 1)
        // 1km 경계는 활동 시간 300초 지점 — 일시정지 300초가 끼어도 구간 시간은 300초
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 200, accuracy: 5)
        XCTAssertEqual(partial.durationSeconds, 60, accuracy: 5)
    }

    func test_한쌍이_여러경계를_넘으면_전부_보간된다() throws {
        // GPS 공백: 0m → 2,500m 단일 쌍이 750초 (일정 속도 가정으로 보간)
        let samples = [sample(t: 0, meters: 0), sample(t: 750, meters: 2500)]
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 2)
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
        XCTAssertEqual(result.completed[1].durationSeconds, 300, accuracy: 5)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 500, accuracy: 10)
    }

    func test_과거기록처럼_일시정지가_없으면_빈배열로_동작한다() {
        let samples = stride(from: 0.0, through: 1100, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 1)
    }
}
