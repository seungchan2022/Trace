import SwiftUI

/// 트래킹 중 하단 패널: 거리·경과 시간·현재 페이스 + 길게 눌러 종료 + 약신호 표시
struct RunStatsPanel: View {
    let viewModel: RunPageViewModel
    @State private var isPressingEnd = false

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.session.isSignalWeak {
                Text("GPS 신호 약함")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
            }
            HStack(spacing: 24) {
                stat(
                    value: String(format: "%.2f", viewModel.session.track.totalDistanceMeters / 1000),
                    unit: "km"
                )
                if let startedAt = viewModel.session.startedAt {
                    VStack(spacing: 2) {
                        Text(startedAt, style: .timer)
                            .font(DesignToken.Typography.segmentRowDistance)
                            .monospacedDigit()
                        Text("시간").font(DesignToken.Typography.sectionLabel)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                }
                stat(
                    value: RunPaceFormatter.string(
                        secondsPerKm: viewModel.session.track.currentPaceSecondsPerKm
                    ),
                    unit: "페이스"
                )
            }
            endButton
        }
        .padding(DesignToken.Size.sheetPadding)
        .frame(maxWidth: .infinity)
        .background(
            DesignToken.Color.surface,
            in: UnevenRoundedRectangle(topLeadingRadius: DesignToken.Corner.sheetTop,
                                       topTrailingRadius: DesignToken.Corner.sheetTop)
        )
        .overlay(alignment: .topTrailing) { recenterButton }
    }

    private var endButton: some View {
        Text("길게 눌러 종료")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DesignToken.Color.danger, in: Capsule())
            .scaleEffect(isPressingEnd ? 0.95 : 1)
            .onLongPressGesture(minimumDuration: 1.0) {
                viewModel.endRun()
            } onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.15)) { isPressingEnd = pressing }
            }
    }

    private var recenterButton: some View {
        Button { viewModel.recenter() } label: {
            Image(systemName: "location.fill")
        }
        .buttonStyle(GlassIconButtonStyle())
        .offset(y: -(DesignToken.Size.fab + 12))
        .padding(.trailing, DesignToken.Size.screenMargin)
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DesignToken.Typography.segmentRowDistance)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink)
            Text(unit)
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }
}

/// 종료 요약 패널: 총 거리·시간·평균 페이스·고도 상승 + 닫기 (+ DEBUG 전용 샘플 덤프 내보내기)
struct RunSummaryPanel: View {
    let viewModel: RunPageViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("러닝 요약").font(DesignToken.Typography.segmentRowTitle)
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    summaryItem(String(format: "%.2f km", viewModel.session.track.totalDistanceMeters / 1000), "거리")
                    summaryItem(durationText, "시간")
                }
                GridRow {
                    summaryItem(
                        RunPaceFormatter.string(secondsPerKm: viewModel.session.track.averagePaceSecondsPerKm),
                        "평균 페이스"
                    )
                    summaryItem(String(format: "%.0f m", viewModel.session.track.elevationGainMeters), "고도 상승")
                }
            }
            #if DEBUG
            if let dumpURL = try? writeDumpFile() {
                ShareLink(item: dumpURL) {
                    Label("샘플 덤프 내보내기 (DEBUG)", systemImage: "square.and.arrow.up")
                        .font(DesignToken.Typography.chip)
                }
            }
            #endif
            Button("닫기") { viewModel.closeSummary() }
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(DesignToken.Size.sheetPadding)
        .frame(maxWidth: .infinity)
        .background(
            DesignToken.Color.surface,
            in: UnevenRoundedRectangle(topLeadingRadius: DesignToken.Corner.sheetTop,
                                       topTrailingRadius: DesignToken.Corner.sheetTop)
        )
    }

    private var durationText: String {
        let total = Int(viewModel.session.track.duration)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    #if DEBUG
    private func writeDumpFile() throws -> URL {
        let session = viewModel.session
        let data = try RunSampleDumpEncoder.jsonData(
            entries: session.dumpEntries,
            startedAt: session.startedAt ?? Date()
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-dump-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url)
        return url
    }
    #endif

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DesignToken.Typography.segmentRowDistance).monospacedDigit()
            Text(label).font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }
}
