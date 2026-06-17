import XCTest
@testable import Trace

@MainActor
final class CoursePlannerPageViewModelTests: XCTestCase {
    func testFirstTapSelectsStartOnly() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service)
        let start = CourseCoordinate(latitude: 37.5665, longitude: 126.9780)

        await viewModel.handleMapTap(at: start)

        XCTAssertEqual(viewModel.startCoordinate?.latitude, start.latitude)
        XCTAssertNil(viewModel.destinationCoordinate)
        XCTAssertNil(viewModel.course)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testSecondTapRequestsRouteAndPublishesDistance() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service)
        let start = CourseCoordinate(latitude: 37.5665, longitude: 126.9780)
        let destination = CourseCoordinate(latitude: 37.5700, longitude: 126.9820)

        await viewModel.handleMapTap(at: start)
        await viewModel.handleMapTap(at: destination)

        XCTAssertEqual(viewModel.destinationCoordinate?.latitude, destination.latitude)
        XCTAssertEqual(viewModel.course?.distanceMeters, 1200)
        XCTAssertEqual(viewModel.distanceText, "1.20 km")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.requestCount, 1)
    }

    func testRouteFailureShowsErrorAndDoesNotPublishRoute() async {
        let service = FakeCoursePlanningService()
        service.result = .failure(CoursePlanningError.routeNotFound)
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service)

        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.5665, longitude: 126.9780))
        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.5700, longitude: 126.9820))

        XCTAssertNil(viewModel.course)
        XCTAssertEqual(viewModel.errorMessage, "도보 경로를 찾을 수 없습니다.")
    }
}

@MainActor
private final class FakeCoursePlanningService: CoursePlanningServiceProtocol {
    var requestCount = 0
    var result: Result<PlannedCourse, Error>?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        requestCount += 1

        if let result {
            return try result.get()
        }

        return PlannedCourse(
            coordinates: [start, destination],
            distanceMeters: 1200
        )
    }
}
