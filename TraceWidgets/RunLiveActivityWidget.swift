import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isPreparing == false {
                        metric(distanceText(context), label: "거리")
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isPreparing {
                        Text("출발 준비 중…")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    } else {
                        timeView(context, fontSize: 22)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPreparing == false {
                        metric(paceText(context), label: "현재 페이스")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isPreparing == false {
                        metric(averagePaceText(context), label: "평균 페이스")
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                if context.state.isPreparing == false {
                    Text(distanceText(context)).monospacedDigit()
                }
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        if context.state.isPreparing {
            preparingView()
        } else {
            VStack(spacing: 10) {
                // 첫 행은 넷(아이콘·거리·시간·현재 페이스)만 둔다 — 일시정지·10km+ 같은 넓은
                // 상태에서 다섯 요소가 잘리는 것을 최종 브랜치 리뷰가 실측으로 확인했다. 평균
                // 페이스는 아래 둘째 행으로 내린다(플랜 Task 5 Step 4가 남긴 대비책).
                HStack(spacing: 14) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                        .font(.title2)
                    metric(distanceText(context), label: "거리")
                    timeView(context, fontSize: 20)
                    metric(paceText(context), label: "현재 페이스")
                }
                HStack {
                    // 평균 페이스는 항상 보인다(경유점과 달리 첫 포인트 전에도 값이 있다).
                    Text("평균 페이스 \(averagePaceText(context))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let waypoint = context.state.lastWaypoint {
                        // 첫 포인트 전에는 줄 자체를 표시하지 않는다(스펙 §2.3)
                        Text(String(format: "P%d · %.2f km", waypoint.index, waypoint.segmentMeters / 1000))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer()
                    Button(intent: MarkRunWaypointIntent()) {
                        Label("포인트", systemImage: "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    // 일시정지 중엔 잠금화면 버튼도 비활성 — 앱 내 버튼과 동일 규칙(스펙 §2.3).
                    .disabled(context.state.isPaused)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.6))
        }
    }

    /// 카운트다운~GPS 확보 중 표시 — 트래킹 전이라 수치도 포인트 버튼도 없다(run-fullscreen).
    private func preparingView() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2)
            Text("출발 준비 중…")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.6))
    }

    @ViewBuilder
    private func timeView(
        _ context: ActivityViewContext<RunActivityAttributes>, fontSize: CGFloat
    ) -> some View {
        VStack(spacing: 2) {
            if context.state.isPaused {
                Text(pausedElapsedText(context))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(context.state.isPaused ? "일시정지" : "시간")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // 주의: 앱 타깃의 RunDurationFormatter(Trace/DesignSystem/Formatter/RunDurationFormatter.swift)와
    // 로직이 동일해야 한다 — 이 파일은 위젯 타깃 멤버십을 받지 않아 여기 중복 정의한다.
    // (RunPaceFormatter는 pace-dedup에서 멤버십 예외로 공유했다 — 같은 방법으로 합칠 수 있고,
    //  pace-dedup 종료 체크리스트에 백로그 등록 대상으로 올라 있다.) 원본 포맷은 항상 "H:MM:SS"
    //  (1시간 미만도 시 자리 유지, 예: 65초 → "0:01:05") —
    // 원본을 고치면 같이 고칠 것.
    private func pausedElapsedText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        let total = Int(context.state.elapsedSecondsAtPause ?? 0)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func distanceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        String(format: "%.2fkm", context.state.distanceMeters / 1000)
    }

    private func paceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        RunPaceFormatter.string(secondsPerKm: context.state.paceSecondsPerKm)
    }

    private func averagePaceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        RunPaceFormatter.string(secondsPerKm: context.state.averagePaceSecondsPerKm)
    }
}
