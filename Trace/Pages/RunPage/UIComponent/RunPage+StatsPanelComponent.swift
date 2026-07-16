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
                VStack(spacing: 2) {
                    if viewModel.session.isPaused {
                        // 멈춘 시간 고정 표시 — activeElapsedSeconds는 일시정지 중 상수라 안전
                        Text(RunDurationFormatter.string(
                            seconds: viewModel.session.activeElapsedSeconds() ?? 0
                        ))
                        .font(DesignToken.Typography.segmentRowDistance)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink2)
                    } else if let timerStart = viewModel.session.displayTimerStart {
                        Text(timerInterval: timerStart...Date.distantFuture, countsDown: false)
                            .font(DesignToken.Typography.segmentRowDistance)
                            .monospacedDigit()
                    }
                    Text("시간").font(DesignToken.Typography.sectionLabel)
                        .foregroundStyle(DesignToken.Color.ink2)
                }
                stat(
                    value: RunPaceFormatter.string(
                        secondsPerKm: viewModel.session.track.currentPaceSecondsPerKm
                    ),
                    unit: "페이스"
                )
            }
            if viewModel.session.isPaused {
                Text("일시정지됨")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            HStack(spacing: 12) {
                pauseResumeButton
                endButton
            }
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

    private var pauseResumeButton: some View {
        Button {
            if viewModel.session.isPaused {
                viewModel.session.resume()
            } else {
                viewModel.session.pause()
            }
        } label: {
            Image(systemName: viewModel.session.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 52, height: 52)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .accessibilityIdentifier("run.pauseResumeButton")
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
            saveStatusLine
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    summaryItem(String(format: "%.2f km", viewModel.session.track.totalDistanceMeters / 1000), "거리")
                    summaryItem(durationText, "시간")
                }
                GridRow {
                    summaryItem(
                        RunPaceFormatter.string(secondsPerKm: viewModel.summaryAveragePaceSecondsPerKm),
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

    @ViewBuilder
    private var saveStatusLine: some View {
        switch viewModel.session.saveStatus {
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("저장 중…").font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
        case .saved:
            Label("기록 저장됨", systemImage: "checkmark.circle.fill")
                .font(DesignToken.Typography.chip)
                .foregroundStyle(DesignToken.Color.accent)
        case .failed:
            HStack(spacing: 8) {
                Label("저장 실패", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
                Button("다시 시도") { viewModel.session.retrySave() }
                    .font(DesignToken.Typography.chip)
            }
        case nil:
            EmptyView()
        }
    }

    private var durationText: String {
        // 트래킹 화면·Live Activity가 보여준 벽시계 경과 시간과 맞춘다(스펙 리뷰 Fix 2).
        // GPS 샘플 구간(`RunTrack.duration`)은 신호확보 공백·후행 필터링 샘플 때문에 실제보다 짧게 잡힐 수 있다.
        RunDurationFormatter.string(seconds: viewModel.summaryElapsedSeconds ?? viewModel.session.track.duration)
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
