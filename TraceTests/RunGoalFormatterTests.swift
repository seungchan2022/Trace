import XCTest
@testable import Trace

final class RunGoalFormatterTests: XCTestCase {
    func test_자유목표는_라벨이_없다() {
        XCTAssertNil(RunGoalFormatter.label(.open))
    }

    func test_거리목표_라벨() {
        XCTAssertEqual(RunGoalFormatter.label(.distance(meters: 5000)), "5 km 목표")
        XCTAssertEqual(RunGoalFormatter.label(.distance(meters: 7500)), "7.5 km 목표")
    }

    func test_시간목표_라벨() {
        XCTAssertEqual(RunGoalFormatter.label(.time(seconds: 1800)), "30분 목표")
    }
}
