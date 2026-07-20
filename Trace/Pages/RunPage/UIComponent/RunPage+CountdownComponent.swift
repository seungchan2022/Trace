import SwiftUI

/// 카운트다운 전체화면(ui-direction §3 연장 — 러닝 플로우는 시작부터 전체화면).
/// 세션이 `.countingDown`인 동안만 그려지고, 그 상태에서는 탭바가 이미 사라져 있어
/// 카운트다운 중 다른 탭으로 빠져나가는 경로 자체가 없다(run-fullscreen Task 1).
struct RunCountdownScreen: View {
    /// 3→2→1. nil이면 아직 정확도 게이트(시스템 프롬프트 포함)를 기다리는 준비 구간이다.
    let count: Int?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DesignToken.Color.surface2.ignoresSafeArea()
            if let count {
                Text("\(count)")
                    .font(DesignToken.Typography.runCountdown)
                    .foregroundStyle(DesignToken.Color.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: count)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("준비 중…")
                        .font(DesignToken.Typography.subtitle)
                        .foregroundStyle(DesignToken.Color.ink2)
                }
            }
            VStack {
                Spacer()
                Text("화면을 탭하면 취소돼요")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCancel) // 취소 = 화면 탭(스펙 §1.1)
        .accessibilityIdentifier("run.countdownScreen")
    }
}
