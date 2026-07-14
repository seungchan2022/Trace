import XCTest
@testable import Trace

nonisolated final class RunDurationFormatterTests: XCTestCase {
    func test_시분초_형식() {
        XCTAssertEqual(RunDurationFormatter.string(seconds: 3725), "1:02:05")
        XCTAssertEqual(RunDurationFormatter.string(seconds: 65), "0:01:05")
        XCTAssertEqual(RunDurationFormatter.string(seconds: 0), "0:00:00")
    }
}
