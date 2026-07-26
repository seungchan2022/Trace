import XCTest
@testable import Trace

final class RunStatsCalculatorTests: XCTestCase {
    // 결정적 테스트를 위해 달력과 기준 시각을 고정한다.
    // 2026-07-22(수) 12:00 KST. 일요일 시작 달력에서 이번 주는 07-19(일)~07-25(토).
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        cal.firstWeekday = 1 // 일요일 시작 — 한국 로케일 기본값(스펙 4.2)
        return cal
    }()

    private let now = Date(timeIntervalSince1970: 1_784_689_200) // 2026-07-22 12:00 KST

    private func summary(daysAgo: Int, distanceMeters: Double, duration: TimeInterval) -> SavedRunSummary {
        summary(
            startedAt: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            distanceMeters: distanceMeters,
            duration: duration
        )
    }

    private func summary(
        startedAt: Date,
        distanceMeters: Double,
        duration: TimeInterval
    ) -> SavedRunSummary {
        SavedRunSummary(
            id: UUID(),
            startedAt: startedAt,
            distanceMeters: distanceMeters,
            duration: duration,
            elevationGainMeters: 0
        )
    }

    // MARK: - 기간 합계

    func test_빈_배열이면_전부_0이다() {
        let stats = RunStatsCalculator.stats(
            summaries: [], period: .thisWeek, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 0)
        XCTAssertEqual(stats.totalDistanceMeters, 0)
        XCTAssertEqual(stats.totalDuration, 0)
    }

    func test_이번_주는_일요일_시작부터_토요일_끝까지다() throws {
        let saturdayEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 25, hour: 23, minute: 59
        )))
        let sundayStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 19, hour: 0, minute: 0
        )))
        let previousSaturday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 23, minute: 59
        )))
        let summaries = [
            summary(startedAt: sundayStart, distanceMeters: 5000, duration: 1800),
            summary(startedAt: saturdayEnd, distanceMeters: 3000, duration: 1200),
            summary(startedAt: previousSaturday, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisWeek, now: saturdayEnd, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 8000)
        XCTAssertEqual(stats.totalDuration, 3000)
    }

    func test_이번_달은_1일_시작부터_말일_끝까지다() throws {
        let julyEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 31, hour: 23, minute: 59
        )))
        let julyStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 0, minute: 0
        )))
        let juneEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 30, hour: 23, minute: 59
        )))
        let summaries = [
            summary(startedAt: julyStart, distanceMeters: 5000, duration: 1800),
            summary(startedAt: julyEnd, distanceMeters: 3000, duration: 1200),
            summary(startedAt: juneEnd, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisMonth, now: julyEnd, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 8000)
    }

    func test_전체는_아무것도_거르지_않는다() {
        let summaries = [
            summary(daysAgo: 3, distanceMeters: 5000, duration: 1800),
            summary(daysAgo: 400, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .all, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 14000)
    }

    func test_자정을_넘긴_러닝은_시작_시각_기준으로_분류된다() {
        // 러닝 종료가 다음 날이어도 startedAt이 속한 기간으로 센다.
        // SavedRunSummary가 기간 분류에 필요한 startedAt만 갖는다.
        let summaries = [summary(daysAgo: 3, distanceMeters: 5000, duration: 7 * 3600)]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisWeek, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 1)
    }

    // MARK: - 8주 추이

    func test_주간_막대는_안_뛴_주도_0으로_채워_항상_요청한_개수만큼_나온다() {
        // 스펙 6.2: 공백을 숨기지 않는다 — 막대 개수가 데이터에 따라 흔들리면 안 된다
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [summary(daysAgo: 3, distanceMeters: 5000, duration: 1800)],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.count, 8)
        XCTAssertEqual(bars.filter { $0.distanceMeters == 0 }.count, 7)
    }

    func test_주간_막대는_과거에서_현재_순으로_정렬된다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [], weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars, bars.sorted { $0.weekStart < $1.weekStart })
    }

    func test_마지막_막대가_이번_주다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [summary(daysAgo: 3, distanceMeters: 5000, duration: 1800)],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.last?.distanceMeters, 5000)
    }

    func test_같은_주의_여러_러닝은_한_막대로_합산된다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [
                summary(daysAgo: 3, distanceMeters: 5000, duration: 1800),
                summary(daysAgo: 2, distanceMeters: 3000, duration: 1200)
            ],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.last?.distanceMeters, 8000)
    }

    // MARK: - 마지막 러닝

    func test_기록이_없으면_마지막_러닝은_nil이다() {
        XCTAssertNil(RunStatsCalculator.lastRun(summaries: []))
    }

    func test_마지막_러닝은_가장_최근_기록이다() {
        let summaries = [
            summary(daysAgo: 10, distanceMeters: 9000, duration: 3600),
            summary(daysAgo: 3, distanceMeters: 5200, duration: 1800)
        ]
        let last = RunStatsCalculator.lastRun(summaries: summaries)
        XCTAssertEqual(last?.distanceMeters, 5200)
        XCTAssertEqual(last?.startedAt, summaries[1].startedAt)
    }

}
