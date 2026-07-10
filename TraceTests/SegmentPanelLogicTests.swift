import XCTest
@testable import Trace

nonisolated final class SegmentPanelLogicTests: XCTestCase {
    // MARK: - latestIndex (최신 = 생성 순번 최대, 배열 위치와 무관)

    @MainActor
    func testLatestIndexIsNilForEmptyKeys() {
        XCTAssertNil(SegmentPanelLogic.latestIndex(colorKeys: []))
    }

    @MainActor
    func testLatestIndexIsLastRowWhenOnlyAppended() {
        XCTAssertEqual(SegmentPanelLogic.latestIndex(colorKeys: [0, 1, 2]), 2)
    }

    @MainActor
    func testLatestIndexIsFirstRowWhenPrepended() {
        // 코스 시작점에 붙은 구간은 prepend되어 배열 맨 앞에 온다 (CourseEditSession.prepend)
        XCTAssertEqual(SegmentPanelLogic.latestIndex(colorKeys: [2, 0, 1]), 0)
    }

    // MARK: - shouldAutoScroll (채팅 앱 방식: 최신 근처를 보고 있을 때만 따라간다)

    @MainActor
    func testAutoScrollsWhenAnchorUnknown() {
        // 스크롤 정보가 없으면(목록이 짧아 스크롤 자체가 없을 때 등) 항상 따라간다
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: nil, previousLatestIndex: 5, tolerance: 3))
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 2, previousLatestIndex: nil, tolerance: 3))
    }

    @MainActor
    func testAutoScrollsWhenViewingNearLatest() {
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 9, previousLatestIndex: 11, tolerance: 3))
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 11, previousLatestIndex: 11, tolerance: 3))
    }

    @MainActor
    func testDoesNotAutoScrollWhenBrowsingOldSegments() {
        XCTAssertFalse(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 2, previousLatestIndex: 11, tolerance: 3))
    }

    @MainActor
    func testToleranceBoundaryIsInclusive() {
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 8, previousLatestIndex: 11, tolerance: 3))
        XCTAssertFalse(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 7, previousLatestIndex: 11, tolerance: 3))
    }
}
