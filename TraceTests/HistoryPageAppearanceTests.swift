import XCTest
@testable import Trace

final class HistoryPageAppearanceTests: XCTestCase {
    func test_기록_탭은_surface2_배경과_대비있는_차트_기준선을_쓴다() {
        let appearance = HistoryPageAppearance.standard

        XCTAssertEqual(appearance.background, .surface2)
        XCTAssertEqual(appearance.chartGridOpacity, 0.72)
    }
}
