import XCTest
@testable import Trace

nonisolated final class ThrottleDetectionTests: XCTestCase {
    @MainActor
    func testThrottleErrorIsDistinctFromRequestFailed() {
        let throttled = CoursePlanningError.throttled
        let failed = CoursePlanningError.requestFailed
        XCTAssertNotEqual(throttled, failed)
    }

    @MainActor
    func testRouteWithRetryDoesNotRetryOnThrottle() async {
        let service = ThrottleStubService()
        // snappedRoute가 routeWithRetry를 사용하므로 간접 테스트
        do {
            _ = try await service.snappedRoute(through: [
                CourseCoordinate(latitude: 37.50, longitude: 127.00),
                CourseCoordinate(latitude: 37.51, longitude: 127.00),
            ])
            XCTFail("Should have thrown")
        } catch CoursePlanningError.throttled {
            // routeWithRetry가 retry하지 않으므로 1번만 호출
            XCTAssertEqual(service.routeCallCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class ThrottleStubService: CoursePlanningServiceProtocol {
    var routeCallCount = 0

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        throw CoursePlanningError.throttled
    }
}
