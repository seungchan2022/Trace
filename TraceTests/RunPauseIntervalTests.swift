import XCTest
@testable import Trace

final class RunPauseIntervalTests: XCTestCase {
    func test_duration은_끝에서_시작을_뺀_초다() {
        let start = Date(timeIntervalSince1970: 1_000)
        let interval = RunPauseInterval(start: start, end: start.addingTimeInterval(90))
        XCTAssertEqual(interval.duration, 90, accuracy: 0.001)
    }
}
