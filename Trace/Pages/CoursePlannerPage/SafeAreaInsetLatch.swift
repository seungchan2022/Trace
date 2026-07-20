import CoreGraphics

/// topSafeAreaInset ratchet(한 번 잡은 값보다 작은 값 무시 — 시트가 커질수록 시스템이 top
/// safe area를 더 작게 보고하는 피드백 루프 차단, docs/solutions/ui-bugs/
/// safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md)을 세로/가로 size class별로
/// 분리해 유지한다. 단일 ratchet은 "이 화면은 회전이 없다"는 전제 위의 장치였는데 가로 지원으로
/// 전제가 깨져, 세로 값(62)이 가로(진짜 0)에도 눌러앉는 stale 문제가 실측됐다(2026-07-20,
/// .git/sdd/task-landscape-layout-report.md). 각 키 안에서는 여전히 단조 증가만 허용하므로
/// 피드백 루프 차단은 그대로 유효하고, 회전 타이밍에 값이 잘못된 키에 latch되는 최악의
/// 경우에도 "시트가 짧아지는"(위로 뚫리는 게 아닌) 안전한 방향으로만 실패한다.
struct SafeAreaInsetLatch {
    private var values: [Bool: CGFloat] = [:]

    mutating func update(_ newValue: CGFloat, isVerticallyCompact: Bool) {
        if newValue > values[isVerticallyCompact, default: 0] {
            values[isVerticallyCompact] = newValue
        }
    }

    func value(isVerticallyCompact: Bool) -> CGFloat {
        values[isVerticallyCompact, default: 0]
    }
}
