import Foundation

/// 잠금화면 포인트 버튼 인텐트의 실제 동작(스펙 §2.3) — 세션 연산과 입력 채널을 분리해
/// 미래 워치 버튼도 같은 지점에 연결되게 한다(스펙 §2.1). ActivityKit 정리는 클로저로
/// 주입해 무세션 가드를 단위 테스트할 수 있게 한다.
@MainActor
struct RunWaypointIntentAction {
    let session: RunSession
    /// 활성 세션이 없는데 잠금화면 카드가 남은 경우(러닝 중 강제종료 등) 잔여 Activity 정리
    let endOrphanedActivities: @MainActor () -> Void

    func perform() {
        guard session.isActive else {
            endOrphanedActivities() // 무세션 가드: no-op + 잔여 카드 정리(스펙 §2.3)
            return
        }
        // 일시정지·샘플 미확보는 markWaypoint 내부 가드가 거른다(앱 내 버튼과 동일 규칙)
        session.markWaypoint()
    }
}
