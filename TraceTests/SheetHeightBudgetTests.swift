import XCTest
@testable import Trace

final class SheetHeightBudgetTests: XCTestCase {
    // 이 테스트가 존재하는 이유(2026-07-21 회귀):
    // pageHeight는 GeometryReader가 보고하는 "부모가 제안한 크기"라 **이미 상단 안전영역이
    // 제외된 값**이다. 커밋 4772313이 예산 앵커를 mapHeight(안전영역 포함)에서 pageHeight로
    // 바꾸면서, mapHeight 시절에만 옳았던 `- topSafeAreaInset` 항을 그대로 남겨 안전영역을
    // 두 번 뺐다 — 풀시트가 62pt 짧아져 topBar를 덮지 못했다.
    // 실측(iPhone 17 Pro, 시뮬레이터): pageHeight 722 / safeTop 62 → 잘못된 값 649, 옳은 값 711.
    // 이 계산은 화면에 경고 하나 남기지 않고 조용히 틀리므로 테스트로 못박는다.
    func test_풀시트_예산은_페이지높이에서_상단여백만_뺀다() {
        XCTAssertEqual(SheetHeightBudget.maxSheetHeight(pageHeight: 722, topMargin: 11), 711)
    }

    func test_리스트_예산은_예산높이에서_그래버와_헤더를_뺀_나머지다() {
        let budget = SheetHeightBudget.maxSheetHeight(pageHeight: 722, topMargin: 11)
        XCTAssertEqual(
            SheetHeightBudget.listHeight(maxSheetHeight: budget, grabberHeight: 25, headerHeight: 86),
            600
        )
    }

    // 측정 전 기본값 조합에서 음수 프레임 경고가 나지 않도록 하는 가드.
    func test_예산이_그래버와_헤더보다_작아도_음수가_되지_않는다() {
        XCTAssertEqual(
            SheetHeightBudget.listHeight(maxSheetHeight: 10, grabberHeight: 25, headerHeight: 86),
            0
        )
    }
}
