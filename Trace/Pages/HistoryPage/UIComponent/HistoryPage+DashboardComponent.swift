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
