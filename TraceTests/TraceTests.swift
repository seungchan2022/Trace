import XCTest
@testable import Trace

@MainActor
final class CoursePlannerPageViewModelTests: XCTestCase {
    func testFirstTapSelectsStartOnly() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
        let start = CourseCoordinate(latitude: 37.5665, longitude: 126.9780)

        await viewModel.handleMapTap(at: start)

        XCTAssertEqual(viewModel.startCoordinate?.latitude, start.latitude)
        XCTAssertNil(viewModel.destinationCoordinate)
        XCTAssertNil(viewModel.course)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testSecondTapRequestsRouteAndPublishesDistance() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
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
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())

        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.5665, longitude: 126.9780))
        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.5700, longitude: 126.9820))

        XCTAssertNil(viewModel.course)
        XCTAssertEqual(viewModel.errorMessage, "도보 경로를 찾을 수 없습니다.")
    }

    func testBootstrapSetsCameraToCurrentLocation() async {
        let service = FakeCoursePlanningService()
        let location = FakeLocationService()
        location.result = .success(CourseCoordinate(latitude: 37.4979, longitude: 127.0276))
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: location)

        await viewModel.bootstrapLocation()

        XCTAssertEqual(viewModel.initialCameraCoordinate?.latitude, 37.4979)
    }

    func testBootstrapFallsBackWhenLocationDenied() async {
        let service = FakeCoursePlanningService()
        let location = FakeLocationService()
        location.result = .failure(LocationError.denied)
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: location)

        await viewModel.bootstrapLocation()

        XCTAssertEqual(viewModel.initialCameraCoordinate?.latitude, 37.5666) // 서울시청 폴백
    }

    func testAppendStrokeSnapsAndPublishesCourse() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
        let stroke = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ]

        await viewModel.appendStroke(stroke)

        XCTAssertNotNil(viewModel.course)
        XCTAssertEqual(viewModel.drawnStrokes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAppendStrokeFailureSetsErrorAndKeepsNoCourse() async {
        let service = FakeCoursePlanningService()
        service.result = .failure(CoursePlanningError.requestFailed)
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())

        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])

        XCTAssertNil(viewModel.course)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testAppendStrokeFailureKeepsPreviousCourse() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())

        // 1. 성공적으로 첫 스트로크 추가 → course 생성 확인
        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ])
        XCTAssertNotNil(viewModel.course, "첫 스트로크 후 course가 생성되어야 합니다")

        // 2. 서비스를 실패 모드로 전환 후 두 번째 스트로크 추가
        service.result = .failure(CoursePlanningError.requestFailed)
        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
            CourseCoordinate(latitude: 37.54, longitude: 127.00),
        ])

        // 3. 기존 course가 유지되고 에러 메시지가 설정되었는지 검증
        XCTAssertNotNil(viewModel.course, "스냅 실패 시 기존 course가 유지되어야 합니다")
        XCTAssertNotNil(viewModel.errorMessage, "스냅 실패 시 에러 메시지가 설정되어야 합니다")
    }

    func testToggleDrawingModeFlips() {
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
        XCTAssertFalse(viewModel.isDrawingMode)
        viewModel.toggleDrawingMode()
        XCTAssertTrue(viewModel.isDrawingMode)
    }

    func testClearResetsState() async {
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        viewModel.clear()
        XCTAssertNil(viewModel.course)
        XCTAssertTrue(viewModel.drawnStrokes.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
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

@MainActor
private final class FakeLocationService: LocationServiceProtocol {
    var result: Result<CourseCoordinate, Error> = .success(CourseCoordinate(latitude: 37.4979, longitude: 127.0276))
    func currentLocation() async throws -> CourseCoordinate { try result.get() }
}
