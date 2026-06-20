import XCTest
@testable import Trace

@MainActor
final class SnappedRouteTests: XCTestCase {
    func testStitchesLegsAndSumsDistance() async throws {
        let service = StubLegService()
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 점 3개 → 구간 2개
        XCTAssertEqual(course.distanceMeters, 200)    // 구간당 100m
        XCTAssertEqual(course.coordinates.first, p[0])
        XCTAssertEqual(course.coordinates.last, p[2])
    }

    func testRetriesTransientLegFailureOnce() async throws {
        let service = StubLegService(failFirstCall: true)
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 첫 호출 실패 + 재시도 성공
        XCTAssertEqual(course.distanceMeters, 100)
    }

    func testThrowsWhenFewerThanTwoPoints() async {
        let service = StubLegService()
        do {
            _ = try await service.snappedRoute(through: [CourseCoordinate(latitude: 37.5, longitude: 127)])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? CoursePlanningError, .routeNotFound)
        }
    }
}

@MainActor
private final class StubLegService: CoursePlanningServiceProtocol {
    var calls = 0
    private var shouldFailNext: Bool
    init(failFirstCall: Bool = false) { shouldFailNext = failFirstCall }

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        calls += 1
        if shouldFailNext {
            shouldFailNext = false
            throw CoursePlanningError.requestFailed
        }
        return PlannedCourse(coordinates: [start, destination], distanceMeters: 100)
    }
}
