import Foundation
import Observation

/// 기록 탭 상태.
/// 목록은 요약(캐시 컬럼)만 읽고, 집계는 그 배열에서 파생시킨다(스펙 §4).
/// 상세 진입 시에만 단건 blob을 읽는 기존 규칙은 그대로다.
@MainActor
@Observable
final class HistoryPageViewModel {
    /// 8주 — 스펙 §4.1. 기간 세그먼트와 무관하게 고정이다(§6).
    static let weeklyBarCount = 8

    private let repository: RunRecordRepositoryProtocol
    private let now: () -> Date
    private let calendar: Calendar

    var period: RunStatsPeriod = .thisWeek
    private(set) var summaries: [SavedRunSummary] = []

    init(
        repository: RunRecordRepositoryProtocol,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.now = now
        self.calendar = calendar
    }

    var isEmpty: Bool { summaries.isEmpty }

    var stats: RunStats {
        RunStatsCalculator.stats(
            summaries: summaries,
            period: period,
            now: now(),
            calendar: calendar
        )
    }

    var weeklyBars: [RunWeeklyBar] {
        RunStatsCalculator.weeklyBars(
            summaries: summaries,
            weekCount: Self.weeklyBarCount,
            now: now(),
            calendar: calendar
        )
    }

    func load() async {
        summaries = await repository.fetchSummaries()
    }
}
