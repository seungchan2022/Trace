import XCTest
@testable import Trace

final class ScrollEdgeStateTests: XCTestCase {
    // 기준 상황: 뷰포트 289pt(중간 단계 리스트 높이 ≈ pageHeight 722 × 0.4), 콘텐츠 500pt,
    // 아래 콘텐츠 여백 12pt(뷰의 .contentMargins(.bottom, 12, for: .scrollContent)와 같은 값).
    // → 실제로 스크롤 가능한 거리는 500 + 12 - 289 = 223pt.
    private let viewport: CGFloat = 289
    private let content: CGFloat = 500
    private let bottomInset: CGFloat = 12

    private func edge(offset: CGFloat, content: CGFloat? = nil) -> ScrollEdgeState {
        ScrollEdgeState.make(
            scrollOffset: offset,
            contentHeight: content ?? self.content,
            viewportHeight: viewport,
            bottomInset: bottomInset
        )
    }

    func test_맨_위에_있으면_위쪽_끝으로만_판정한다() {
        XCTAssertTrue(edge(offset: 0).isAtTop)
        XCTAssertFalse(edge(offset: 0).isAtBottom)
    }

    func test_맨_아래에_있으면_아래쪽_끝으로만_판정한다() {
        XCTAssertFalse(edge(offset: 223).isAtTop)
        XCTAssertTrue(edge(offset: 223).isAtBottom)
    }

    func test_중간에서는_어느_끝도_아니다() {
        XCTAssertFalse(edge(offset: 100).isAtTop)
        XCTAssertFalse(edge(offset: 100).isAtBottom)
    }

    // 허용 오차 경계. 오차가 없으면 구간 5개 안팎(스크롤 여유 20pt 남짓)에서
    // 화면상 정지해 보이는 구간을 먼저 스크롤해야만 인계가 걸린다 — "아무 반응 없음"으로 읽힌다.
    func test_남은_여유가_오차_이내면_끝으로_인정한다() {
        XCTAssertTrue(edge(offset: 7).isAtTop)          // 위로 남은 여유 7pt
        XCTAssertTrue(edge(offset: 216).isAtBottom)     // 아래로 남은 여유 7pt
    }

    func test_남은_여유가_오차를_넘으면_끝이_아니다() {
        XCTAssertFalse(edge(offset: 9).isAtTop)         // 위로 남은 여유 9pt
        XCTAssertFalse(edge(offset: 214).isAtBottom)    // 아래로 남은 여유 9pt
    }

    // 아래 여백을 빼먹으면 판정이 12pt 어긋나 오차 8pt가 실질 20pt처럼 동작한다.
    // 그러면 이 테스트가 못박은 경계값이 실기기에서 재현되지 않는다.
    func test_아래_콘텐츠_여백만큼_스크롤_범위가_길어진다() {
        // 여백을 0으로 보면 offset 211이 이미 바닥이지만, 실제로는 12pt가 더 남아 있다.
        XCTAssertFalse(edge(offset: 211).isAtBottom)
        XCTAssertTrue(
            ScrollEdgeState.make(
                scrollOffset: 211, contentHeight: content, viewportHeight: viewport, bottomInset: 0
            ).isAtBottom
        )
    }

    // 바운스로 오프셋이 경계 바깥(음수)으로 나가도 끝이다.
    // 바운스는 인계를 시도하는 동작 그 자체라, 여기서 벗어난 것으로 처리하면 규칙이 자기를 부정한다.
    func test_맨_위_바운스_중_음수_오프셋도_위쪽_끝이다() {
        XCTAssertTrue(edge(offset: -40).isAtTop)
    }

    // 구간이 1~2개면 스크롤할 것이 없다 → 리스트 전체가 그래버처럼 동작한다.
    // 예외 처리가 아니라 같은 식에서 그대로 나온다.
    func test_콘텐츠가_뷰포트보다_짧으면_양끝이_동시에_참이다() {
        XCTAssertTrue(edge(offset: 0, content: 120).isAtTop)
        XCTAssertTrue(edge(offset: 0, content: 120).isAtBottom)
    }

    // 드래그 도중 한 번이라도 끝에서 벗어나면 그 끝은 죽는다 — 방향 반전 손동작을 거르는 장치.
    func test_드래그_도중_끝에서_벗어나면_인계_자격을_잃는다() {
        let atTop = ScrollEdgeState(isAtTop: true, isAtBottom: false)
        let scrolledAway = ScrollEdgeState(isAtTop: false, isAtBottom: false)
        XCTAssertEqual(
            atTop.intersected(with: scrolledAway),
            ScrollEdgeState(isAtTop: false, isAtBottom: false)
        )
    }

    func test_끝에_계속_붙어_있으면_인계_자격이_유지된다() {
        let atTop = ScrollEdgeState(isAtTop: true, isAtBottom: false)
        XCTAssertEqual(atTop.intersected(with: atTop), atTop)
    }
}
