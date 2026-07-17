import XCTest
@testable import Trace

final class RunGoalTests: XCTestCase {
    func test_자유목표는_진행률이_없다() {
        XCTAssertNil(RunGoal.open.progressFraction(distanceMeters: 3000, activeSeconds: 900))
    }

    func test_거리목표_진행률은_거리_비율이다() {
        let goal = RunGoal.distance(meters: 5000)
        XCTAssertEqual(goal.progressFraction(distanceMeters: 2500, activeSeconds: 0), 0.5)
        XCTAssertEqual(goal.progressFraction(distanceMeters: 6000, activeSeconds: 0), 1.2)
    }

    func test_시간목표_진행률은_활동시간_비율이다() {
        let goal = RunGoal.time(seconds: 1800)
        XCTAssertEqual(goal.progressFraction(distanceMeters: 0, activeSeconds: 900), 0.5)
        XCTAssertEqual(goal.progressFraction(distanceMeters: 0, activeSeconds: 1800), 1.0)
    }

    func test_0이하_목표값은_진행률이_없다() {
        XCTAssertNil(RunGoal.distance(meters: 0).progressFraction(distanceMeters: 100, activeSeconds: 0))
        XCTAssertNil(RunGoal.time(seconds: 0).progressFraction(distanceMeters: 0, activeSeconds: 100))
    }
}
