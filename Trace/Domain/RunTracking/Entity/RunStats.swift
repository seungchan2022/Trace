import Foundation

/// 기간 집계 결과.
/// 기록 탭 대시보드와 러닝 탭 요약 줄이 같은 타입을 소비한다(스펙 §4).
struct RunStats: Equatable, Sendable {
    let totalDistanceMeters: Double
    let runCount: Int
    let totalDuration: TimeInterval

    static let empty = RunStats(totalDistanceMeters: 0, runCount: 0, totalDuration: 0)
}

/// 주간 추이 막대 하나. `weekStart`는 달력의 주 시작일(스펙 §4.2 — 로케일 기본값).
struct RunWeeklyBar: Equatable, Sendable {
    let weekStart: Date
    let distanceMeters: Double
}

enum RunStatsPeriod: CaseIterable, Hashable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case all

    var id: Self { self }
}

/// `[SavedRunSummary]`만 입력받는 순수 계산기 — 무거운 blob을 열지 않는다.
/// `now`/`calendar`를 주입받는 이유: 내부에서 `Date()`를 부르면 테스트가 실행 시점에
/// 따라 결과가 달라진다. 호출부가 `Date()`와 `Calendar.current`를 넘긴다.
enum RunStatsCalculator {
    static func stats(
        summaries: [SavedRunSummary],
        period: RunStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> RunStats {
        let filtered = summaries.filter { isInPeriod($0.startedAt, period: period, now: now, calendar: calendar) }
        guard filtered.isEmpty == false else { return .empty }
        return RunStats(
            totalDistanceMeters: filtered.reduce(0) { $0 + $1.distanceMeters },
            runCount: filtered.count,
            totalDuration: filtered.reduce(0) { $0 + $1.duration }
        )
    }

    /// 최근 `weekCount`주의 거리 합.
    /// 기록이 없는 주도 0으로 채워 항상 `weekCount`개를 돌려준다.
    /// 막대 개수가 데이터에 따라 흔들리면 화면 구조가 불안정해진다(스펙 §6.2).
    static func weeklyBars(
        summaries: [SavedRunSummary],
        weekCount: Int,
        now: Date,
        calendar: Calendar
    ) -> [RunWeeklyBar] {
        guard weekCount > 0, let thisWeekStart = weekStart(of: now, calendar: calendar) else { return [] }

        let starts: [Date] = (0..<weekCount).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeekStart)
        }

        var totals: [Date: Double] = [:]
        for summary in summaries {
            guard let start = weekStart(of: summary.startedAt, calendar: calendar) else { continue }
            totals[start, default: 0] += summary.distanceMeters
        }

        return starts.map { RunWeeklyBar(weekStart: $0, distanceMeters: totals[$0] ?? 0) }
    }

    static func lastRun(
        summaries: [SavedRunSummary],
    ) -> SavedRunSummary? {
        summaries.max(by: { $0.startedAt < $1.startedAt })
    }

    // MARK: - Private

    private static func isInPeriod(
        _ date: Date,
        period: RunStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch period {
        case .all:
            return true
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
    }

    private static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
