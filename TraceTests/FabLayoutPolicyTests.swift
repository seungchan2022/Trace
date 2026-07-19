import XCTest
@testable import Trace

final class FabLayoutPolicyTests: XCTestCase {
    func test_투명도는_디텐트가_오를수록_줄어_풀에서_사라진다() {
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .collapsed), 1.0)
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .medium), 0.55)
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .full), 0.0)
    }

    // 방향 스펙 §2: 경로 없음 → 현위치만. 단 clear 직후처럼 경로는 없어도
    // 되돌릴 이력이 있으면 편집 그룹을 유지한다 (undo 가능성 보존).
    func test_편집그룹은_경로나_되돌릴_이력이_있을_때만_보인다() {
        XCTAssertFalse(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: false, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: true, canUndo: false, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: true, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: false, canRedo: true))
    }

    func test_버튼은_현재_시트_상단_위_16pt에_앵커된다() {
        // collapsed: 시트 = 그래버+헤더(예: 25+140)
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .collapsed, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 16
        )
        // medium: 시트 = collapsed + 리스트 높이
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .medium, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 300 + 16
        )
        // full: 숨김 상태(opacity 0) — 페이드 중 점프가 없도록 medium 위치를 유지한다
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .full, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 300 + 16
        )
    }
}
