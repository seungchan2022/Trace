import Foundation

// 구간 리스트가 스크롤 끝에 붙어 있는지의 판정. 뷰에서 분리한 순수 계산.
//
// 이 판정이 틀리면 스크롤만 하려던 손동작이 시트를 움직인다. 그리고 이 화면의 계산은
// 경고 하나 없이 조용히 틀렸던 이력이 있어(2026-07-21, 시트 예산에서 62pt가 소리 없이
// 사라짐) 뷰 안의 식으로 두지 않는다 — SheetHeightBudget·SegmentPanelLogic과 같은 자리.
struct ScrollEdgeState: Equatable {
    let isAtTop: Bool
    let isAtBottom: Bool

    /// 끝으로 인정할 여유. 구간 5개 안팎이면(행 ≈54pt + 간격 8pt) 중간 단계 리스트 높이
    /// ≈289pt를 근소하게 넘어 스크롤 여유가 20pt 남짓뿐이다. 오차가 없으면 사용자는
    /// 화면상 정지해 보이는 구간을 먼저 스크롤해 끝에 닿게 한 뒤 손을 떼고 다시 끌어야 한다.
    static let defaultTolerance: CGFloat = 8

    /// - Parameters:
    ///   - scrollOffset: 맨 위에서 아래로 스크롤한 거리. 맨 위 바운스 중에는 음수가 된다.
    ///   - contentHeight: 리스트 콘텐츠 전체 높이.
    ///   - viewportHeight: 리스트가 보이는 높이(`expandedListHeight`).
    ///   - bottomInset: 콘텐츠 아래에 붙은 스크롤 여백. 뷰의
    ///     `.contentMargins(.bottom, _, for: .scrollContent)`와 같은 값이어야 한다 —
    ///     그만큼 실제 스크롤 범위가 콘텐츠 높이보다 길다. 빠뜨리면 아래쪽 끝 판정만
    ///     그 크기만큼 일찍 참이 되어, 오차 8pt가 실질 20pt처럼 동작한다.
    static func make(
        scrollOffset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        bottomInset: CGFloat,
        tolerance: CGFloat = defaultTolerance
    ) -> ScrollEdgeState {
        let remainingBelow = contentHeight + bottomInset - viewportHeight - scrollOffset
        return ScrollEdgeState(
            isAtTop: scrollOffset <= tolerance,
            isAtBottom: remainingBelow <= tolerance
        )
    }

    /// 드래그가 진행되는 동안의 누적 판정 — 한 번이라도 그 끝에서 벗어나면 자격을 잃는다.
    ///
    /// 순간 스냅샷으로 판정할 수 없는 이유가 셋이다. ① `DragGesture(minimumDistance:)`에는
    /// 터치다운 콜백이 없어 "시작 순간"을 읽을 방법 자체가 없다. ② 종료 순간만 보면 리스트
    /// 중간에서 아래로 쓸어 맨 위에 도달한 손동작이 시트까지 내린다. ③ 시작 근처만 보면
    /// 맨 위에서 위로 쓸었다가 아래로 되돌리는 손동작에서 똑같이 틀린다.
    func intersected(with other: ScrollEdgeState) -> ScrollEdgeState {
        ScrollEdgeState(
            isAtTop: isAtTop && other.isAtTop,
            isAtBottom: isAtBottom && other.isAtBottom
        )
    }
}
