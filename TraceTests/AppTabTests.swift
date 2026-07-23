import XCTest
@testable import Trace

final class AppTabTests: XCTestCase {
    func test_탭은_코스_러닝_기록_순서로_세_개다() {
        XCTAssertEqual(AppTab.allCases, [.course, .run, .history])
        XCTAssertEqual(AppTab.course.title, "코스")
        XCTAssertEqual(AppTab.run.title, "러닝")
        XCTAssertEqual(AppTab.history.title, "기록")
        XCTAssertEqual(AppTab.course.systemImage, "map")
        XCTAssertEqual(AppTab.run.systemImage, "figure.run")
        XCTAssertEqual(AppTab.history.systemImage, "chart.bar.xaxis")
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
