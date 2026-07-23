import Foundation
import Observation

/// 기록 탭 상태 — 기간 선택만 소유하고, 데이터는 공유 `RunHistoryViewModel`에서 읽는다.
/// 목록은 요약(캐시 컬럼)만 읽고, 집계는 그 배열에서 파생시킨다(스펙 §4).
/// 상세 진입 시에만 단건 blob을 읽는 기존 규칙은 그대로다.
@MainActor
@Observable
final class HistoryPageViewModel {
    /// 8주 — 스펙 §4.1. 기간 세그먼트와 무관하게 고정이다(§6).
    static let weeklyBarCount = 8

    let history: RunHistoryViewModel
    private let now: () -> Date
    private let calendar: Calendar

    var period: RunStatsPeriod = .thisWeek

    init(
        history: RunHistoryViewModel,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.history = history
        self.now = now
        self.calendar = calendar
    }

    var summaries: [SavedRunSummary] { history.summaries }

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
        await history.load()
    }

    /// 숨겨진 탭은 로드하지 않고, 기록 탭이 다시 활성화될 때만 공유 캐시를 새로고침한다.
    func loadWhenActivated(_ isActive: Bool) async {
        guard isActive else { return }
        await load()
    }
}
