import XCTest
@testable import Trace

nonisolated final class SnappedRouteTests: XCTestCase {
    @MainActor
    func testStitchesLegsAndSumsDistance() async throws {
        let service = StubLegService()
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00)
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 점 3개 → 구간 2개
        XCTAssertEqual(course.distanceMeters, 200)    // 구간당 100m
        XCTAssertEqual(course.coordinates, [p[0], p[1], p[2]])
    }

    @MainActor
    func testRetriesTransientLegFailureOnce() async throws {
        let service = StubLegService(failFirstCall: true)
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00)
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 첫 호출 실패 + 재시도 성공
        XCTAssertEqual(course.distanceMeters, 100)
    }

    @MainActor
    func testThrowsRealErrorWhenRetryExhausted() async {
        let service = StubLegService(alwaysFail: true)
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00)
        ]
        do {
            _ = try await service.snappedRoute(through: p)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(service.calls, 2)          // 첫 호출 + 재시도 1회 = 총 2회
            XCTAssertTrue(error is StubLegError)       // placeholder가 아닌 실제 에러 전파 확인
        }
    }

    @MainActor
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

private enum StubLegError: Error { case boom }

@MainActor
private final class StubLegService: CoursePlanningServiceProtocol {
    var calls = 0
    private var shouldFailNext: Bool
    private let alwaysFail: Bool
    init(failFirstCall: Bool = false, alwaysFail: Bool = false) {
        shouldFailNext = failFirstCall
        self.alwaysFail = alwaysFail
    }

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        calls += 1
        if alwaysFail { throw StubLegError.boom }
        if shouldFailNext {
            shouldFailNext = false
            throw CoursePlanningError.requestFailed
        }
        return PlannedCourse(
            segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
        )
    }
}
