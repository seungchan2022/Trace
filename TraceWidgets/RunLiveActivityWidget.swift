import ActivityKit
import SwiftUI
import WidgetKit

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metric(distanceText(context), label: "거리")
                }
                DynamicIslandExpandedRegion(.center) {
                    timeView(context, fontSize: 22)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    metric(paceText(context), label: "페이스")
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(distanceText(context)).monospacedDigit()
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        HStack(spacing: 20) {
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                .font(.title2)
            metric(distanceText(context), label: "거리")
            timeView(context, fontSize: 20)
            metric(paceText(context), label: "페이스")
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
            } else {
                Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            Text(context.state.isPaused ? "일시정지" : "시간")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // 주의: 앱 타깃의 RunDurationFormatter(Trace/Pages/RunPage/RunDurationFormatter.swift)와
    // 로직이 동일해야 한다 — 위젯 타깃은 앱 타깃 타입을 볼 수 없어 여기 중복 정의한다(paceText와
    // 같은 이유). 원본 포맷은 항상 "H:MM:SS"(1시간 미만도 시 자리 유지, 예: 65초 → "0:01:05") —
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func distanceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        String(format: "%.2fkm", context.state.distanceMeters / 1000)
    }

    // 주의: 앱 타깃의 RunPaceFormatter(Trace/Pages/RunPage/PolylineThrottle.swift)와 로직이
    // 동일해야 한다. 위젯 타깃은 앱 타깃 타입을 볼 수 없어(Target Membership 추가가 필요) 여기 중복
    // 정의한다. RunPaceFormatter.string(secondsPerKm:)을 고치면 이 함수도 같이 고칠 것.
    private func paceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        guard let pace = context.state.paceSecondsPerKm, pace > 0, pace < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(pace) / 60, Int(pace) % 60)
    }
}
