import XCTest
@testable import Trace

final class RunPaceFormatterTests: XCTestCase {
    func test_초퍼km를_분초로_포맷한다() {
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 332), "5'32\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 600), "10'00\"")
    }

    func test_nil이나_비정상값은_대시로_표시한다() {
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: nil), "--'--\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 0), "--'--\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 3600), "--'--\"") // 60분/km 초과는 무의미
    }
}
