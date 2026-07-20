import XCTest
@testable import Trace

final class SafeAreaInsetLatchTests: XCTestCase {
    func test_같은_사이즈클래스에서는_큰_값만_래치되고_작아지는_값은_무시된다() {
        var latch = SafeAreaInsetLatch()
        latch.update(62, isVerticallyCompact: false)
        latch.update(40, isVerticallyCompact: false) // 피드백 루프가 만드는 축소 보고 — 무시돼야 함
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 62)
        latch.update(66, isVerticallyCompact: false)
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 66)
    }

    func test_사이즈클래스가_다르면_서로_다른_값을_독립적으로_유지한다() {
        var latch = SafeAreaInsetLatch()
        latch.update(62, isVerticallyCompact: false) // 세로에서 62 latch
        latch.update(0, isVerticallyCompact: true)   // 가로의 진짜 값 0
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 62) // 세로 값 유지
        XCTAssertEqual(latch.value(isVerticallyCompact: true), 0)   // 가로는 0 (기존 단일 ratchet은 여기서 62를 반환하는 게 버그였다)
    }

    func test_측정_전_기본값은_0이다() {
        let latch = SafeAreaInsetLatch()
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 0)
        XCTAssertEqual(latch.value(isVerticallyCompact: true), 0)
    }
}
