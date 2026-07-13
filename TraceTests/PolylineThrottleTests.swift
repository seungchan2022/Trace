import XCTest
@testable import Trace

final class PolylineThrottleTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func test_첫호출은_항상_갱신한다() {
        var throttle = PolylineThrottle()
        XCTAssertTrue(throttle.shouldRefresh(now: base, totalDistanceMeters: 0))
    }

    func test_3초와_20m_모두_안지나면_갱신하지_않는다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertFalse(throttle.shouldRefresh(now: base.addingTimeInterval(1), totalDistanceMeters: 10))
    }

    func test_3초가_지나면_갱신한다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertTrue(throttle.shouldRefresh(now: base.addingTimeInterval(3.1), totalDistanceMeters: 0))
    }

    func test_20m를_넘게_이동하면_시간과_무관하게_갱신한다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertTrue(throttle.shouldRefresh(now: base.addingTimeInterval(0.5), totalDistanceMeters: 25))
    }
}
