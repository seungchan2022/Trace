import Charts
import SwiftUI

/// 집계 대시보드 — 기간 세그먼트 + "거리가 주인공" 숫자 블록.
/// 세그먼트는 이 숫자만 바꾼다. 그래프와 목록은 기간과 무관하다(스펙 §6).
struct HistoryDashboard: View {
    @Bindable var viewModel: HistoryPageViewModel

    var body: some View {
        VStack(spacing: 16) {
            Picker("기간", selection: $viewModel.period) {
                ForEach(RunStatsPeriod.allCases) { period in
                    Text(period.historyLabel).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("history.periodPicker")

            statBlock
            weeklyChart
        }
    }

    private var statBlock: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", viewModel.stats.totalDistanceMeters / 1000))
                    .font(DesignToken.Typography.runDistanceHero)
                Text("km")
                    .font(DesignToken.Typography.runDistanceUnit)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            .foregroundStyle(DesignToken.Color.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.period.historyLabel) 총 거리")
            .accessibilityValue(
                "\(String(format: "%.2f", viewModel.stats.totalDistanceMeters / 1000))킬로미터"
            )

            Text(
                "\(viewModel.stats.runCount)회 · "
                    + RunDurationFormatter.string(seconds: viewModel.stats.totalDuration)
            )
            .font(DesignToken.Typography.subtitle)
            .foregroundStyle(DesignToken.Color.ink2)
            .accessibilityIdentifier("history.secondaryStats")
        }
    }

    /// 최근 8주 거리 추이. 기간 세그먼트와 무관하게 항상 8주 고정이다(스펙 §6) —
    /// 추이는 고정된 창으로 봐야 주마다 비교가 되고,
    /// "전체"에서 몇 년치 막대를 그릴 수도 없다.
    private var weeklyChart: some View {
        Chart(viewModel.weeklyBars, id: \.weekStart) { bar in
            BarMark(
                x: .value("주", bar.weekStart, unit: .weekOfYear),
                y: .value("거리", bar.distanceMeters / 1000)
            )
            .foregroundStyle(DesignToken.Color.accent)
            .accessibilityLabel(Self.weekLabel(bar.weekStart))
            .accessibilityValue("\(String(format: "%.1f", bar.distanceMeters / 1000))킬로미터")
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(DesignToken.Color.border)
                AxisValueLabel()
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("최근 8주 주간 거리")
        .accessibilityIdentifier("history.weeklyChart")
    }

    private static func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day()) + " 주"
    }
}

/// 화면 문구는 Presentation 소유다. Domain의 `RunStatsPeriod`에는 현지화 문자열을 넣지 않는다.
private extension RunStatsPeriod {
    var historyLabel: String {
        switch self {
        case .thisWeek: return "이번 주"
        case .thisMonth: return "이번 달"
        case .all: return "전체"
        }
    }
}
