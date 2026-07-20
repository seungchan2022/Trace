import XCTest
@testable import Trace

final class AppTabTests: XCTestCase {
    func test_탭은_코스_러닝_순서로_두_개다() {
        XCTAssertEqual(AppTab.allCases, [.course, .run])
        XCTAssertEqual(AppTab.course.title, "코스")
        XCTAssertEqual(AppTab.run.title, "러닝")
        XCTAssertEqual(AppTab.course.systemImage, "map")
        XCTAssertEqual(AppTab.run.systemImage, "figure.run")
    }

    // 킥오프 §2.2: 러닝 시작~요약 화면을 닫을 때까지 탭바 숨김 — idle에서만 보인다.
    func test_탭바는_idle에서만_보인다() {
        XCTAssertFalse(AppTab.isTabBarHidden(runState: .idle))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .countingDown))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .acquiring))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .tracking))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .paused))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .summary))
    }
}
