import XCTest
@testable import Trace

final class TapClassifierTests: XCTestCase {
    private let p1 = CGPoint(x: 100, y: 100)
    private let near = CGPoint(x: 110, y: 110)   // 40pt 이내
    private let far = CGPoint(x: 300, y: 300)    // 40pt 밖

    func testSingleTapConfirmsAfterWindow() {
        let sut = TapClassifier()
        XCTAssertEqual(sut.tapEnded(at: p1, time: 0), [.pending(p1)])
        XCTAssertEqual(sut.windowElapsed(time: 0.36), [.confirmed(p1)])
        XCTAssertFalse(sut.hasPending)
    }

    func testWindowNotElapsedYieldsNothing() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.windowElapsed(time: 0.2), [])
        XCTAssertTrue(sut.hasPending)
    }

    func testDoubleTapCancelsAndSwallowsSecondTap() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.15), [.cancelled])
        XCTAssertEqual(sut.tapEnded(at: near, time: 0.2), [])   // 더블탭의 두 번째 탭은 삼킴
        XCTAssertEqual(sut.windowElapsed(time: 0.4), [])        // 잔여 타이머 발화는 무해
    }

    func testOneFingerZoomCancelsWithoutTapCompletion() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.15), [.cancelled])
        // 두 번째 터치는 드래그로 끝나 tapEnded가 안 옴 — 이후 탭은 정상 동작
        XCTAssertEqual(sut.touchBegan(at: far, time: 2.0), [])
        XCTAssertEqual(sut.tapEnded(at: far, time: 2.1), [.pending(far)])
    }

    func testFarQuickSecondTapConfirmsFirstEarly() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        // 다른 위치 빠른 연속 탭 → 첫 탭 조기 확정, 둘 다 포인트가 된다 (기존 회귀 케이스)
        XCTAssertEqual(sut.touchBegan(at: far, time: 0.15), [.confirmed(p1)])
        XCTAssertEqual(sut.tapEnded(at: far, time: 0.2), [.pending(far)])
    }

    func testResetCancelsPendingOnce() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.reset(), [.cancelled])
        XCTAssertEqual(sut.reset(), [])
    }

    func testLateTouchAfterWindowConfirmsPending() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        // 창이 지났는데 타이머보다 터치가 먼저 온 경합 → 확정 처리
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.5), [.confirmed(p1)])
    }
}
