import XCTest
@testable import Trace

@MainActor
final class HistoryPageViewModelTests: XCTestCase {
    // 2026-07-22(수) 12:00 KST. 실행 시점의 주·월 경계를 타지 않게 고정한다.
    private let now = Date(timeIntervalSince1970: 1_784_689_200)
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }()

    private func makeSummary(daysAgo: Int, distanceMeters: Double) -> SavedRunSummary {
        SavedRunSummary(
            id: UUID(),
            startedAt: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            distanceMeters: distanceMeters,
            duration: 1800,
            elevationGainMeters: 0
        )
    }

    private func makeRun(_ summary: SavedRunSummary) -> SavedRun {
        SavedRun(summary: summary, samples: [], pauses: [], goal: .open, waypoints: [])
    }

    private func makeViewModel(
        repository: MockRunRecordRepository
    ) -> HistoryPageViewModel {
        let now = now
        return HistoryPageViewModel(
            history: RunHistoryViewModel(repository: repository),
            now: { now },
            calendar: calendar
        )
    }

    func test_초기_기간은_이번_주다() {
        let viewModel = makeViewModel(repository: MockRunRecordRepository())
        XCTAssertEqual(viewModel.period, .thisWeek)
    }

    func test_기록이_없으면_isEmpty가_참이고_집계는_0이다() async {
        let viewModel = makeViewModel(repository: MockRunRecordRepository())
        await viewModel.load()
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.stats.runCount, 0)
    }

    func test_기록이_없어도_주간_막대는_8개다() async {
        // 스펙 6.2: 0건에서도 집계 영역은 그대로 렌더링한다
        let viewModel = makeViewModel(repository: MockRunRecordRepository())
        await viewModel.load()
        XCTAssertEqual(viewModel.weeklyBars.count, 8)
    }

    func test_기간을_바꾸면_집계가_다시_계산된다() async throws {
        let repository = MockRunRecordRepository()
        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))
        try await repository.save(makeRun(makeSummary(daysAgo: 200, distanceMeters: 9000)))

        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()

        viewModel.period = .thisWeek
        XCTAssertEqual(viewModel.stats.runCount, 1)

        viewModel.period = .all
        XCTAssertEqual(viewModel.stats.runCount, 2)
        XCTAssertEqual(viewModel.stats.totalDistanceMeters, 14000)
    }

    func test_로드하면_isEmpty가_거짓이_된다() async throws {
        let repository = MockRunRecordRepository()
        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))

        let viewModel = makeViewModel(repository: repository)
        await viewModel.load()

        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_기록_탭으로_다시_돌아와_로드하면_새_기록을_반영한다() async throws {
        let repository = MockRunRecordRepository()
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load()
        XCTAssertTrue(viewModel.isEmpty)

        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))
        await viewModel.load()

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.stats.runCount, 1)
        XCTAssertEqual(viewModel.stats.totalDistanceMeters, 5000)
    }

    func test_기록_탭을_재활성화하면_새_기록으로_공유_요약을_새로고침한다() async throws {
        let repository = MockRunRecordRepository()
        try await repository.save(makeRun(makeSummary(daysAgo: 1, distanceMeters: 3000)))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadWhenActivated(true)
        XCTAssertEqual(viewModel.summaries.count, 1)

        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))
        await viewModel.loadWhenActivated(false)
        XCTAssertEqual(viewModel.summaries.count, 1)

        await viewModel.loadWhenActivated(true)
        XCTAssertEqual(viewModel.summaries.count, 2)
        XCTAssertEqual(viewModel.stats.totalDistanceMeters, 8000)
    }

    func test_공유_기록_뷰모델을_로드하면_같은_요약_배열을_읽는다() async throws {
        let repository = MockRunRecordRepository()
        let history = RunHistoryViewModel(repository: repository)
        let now = now
        let viewModel = HistoryPageViewModel(
            history: history,
            now: { now },
            calendar: calendar
        )
        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))

        await viewModel.load()

        XCTAssertEqual(viewModel.summaries, history.summaries)
        XCTAssertEqual(history.summaries.count, 1)
    }
}
