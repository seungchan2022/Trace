import XCTest
@testable import Trace

final class RunIdleSummaryFormatterTests: XCTestCase {
    func test_이번_주_집계_문구() {
        let result = RunIdleSummary.thisWeek(RunStats(
            totalDistanceMeters: 12400,
            runCount: 1,
            totalDuration: 3600
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "이번 주 12.40km · 1회"
        )
    }

    func test_이번_주_거리는_사용자_로케일과_무관하게_점으로_표시한다() {
        let result = RunIdleSummary.thisWeek(RunStats(
            totalDistanceMeters: 12400,
            runCount: 1,
            totalDuration: 3600
        ))

        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "이번 주 12.40km · 1회"
        )
    }

    func test_지난_러닝_문구() {
        let result = RunIdleSummary.lastRun(LastRunSummary(
            distanceMeters: 5200,
            daysAgo: 10
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "지난 러닝 5.20km · 10일 전"
        )
    }

    func test_어제_문구() {
        let result = RunIdleSummary.lastRun(LastRunSummary(
            distanceMeters: 5200,
            daysAgo: 1
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "지난 러닝 5.20km · 어제"
        )
    }

    func test_기록_없음_문구() {
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: .noRuns),
            "첫 러닝을 시작해보세요"
        )
    }
}
