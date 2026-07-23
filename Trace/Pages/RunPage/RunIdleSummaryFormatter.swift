import Foundation

/// Domain의 3단 폴백 결과를 러닝 대기 화면 문구로 바꾼다.
enum RunIdleSummaryFormatter {
    /// 한국어 요약의 거리 소수점은 사용자 로케일과 무관하게 점으로 고정한다.
    static func string(for summary: RunIdleSummary) -> String {
        switch summary {
        case .thisWeek(let stats):
            return "이번 주 \(kilometerText(stats.totalDistanceMeters))km · "
                + "\(stats.runCount)회"
        case .lastRun(let last):
            return "지난 러닝 \(kilometerText(last.distanceMeters))km · "
                + dayText(last.daysAgo)
        case .noRuns:
            return "첫 러닝을 시작해보세요"
        }
    }

    private static func kilometerText(_ meters: Double) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            meters / 1000
        )
    }

    private static func dayText(_ daysAgo: Int) -> String {
        switch daysAgo {
        case 0: return "오늘"
        case 1: return "어제"
        default: return "\(daysAgo)일 전"
        }
    }
}
