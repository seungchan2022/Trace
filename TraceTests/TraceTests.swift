import XCTest
@testable import Trace

@MainActor
final class CoursePlannerPageViewModelTests: XCTestCase {
    func testFirstTapSelectsStartOnly() async {
        let service = FakeCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
        let start = CourseCoordinate(latitude: 37.5665, longitude: 126.9780)

        await viewModel.handleMapTap(at: start)

        XCTAssertEqual(viewModel.pendingTapStart?.latitude, start.latitude)
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

        await viewModel.toggleDrawingMode()
        await viewModel.appendStroke(stroke)

        XCTAssertNotNil(viewModel.course)
        XCTAssertEqual(viewModel.drawnStrokes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAppendStrokeFailureSetsErrorAndKeepsNoCourse() async {
        let service = FakeCoursePlanningService()
        service.result = .failure(CoursePlanningError.requestFailed)
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())

        await viewModel.toggleDrawingMode()
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

        await viewModel.toggleDrawingMode()
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

    func testToggleDrawingModeFlips() async {
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
        XCTAssertFalse(viewModel.isDrawingMode)
        await viewModel.toggleDrawingMode()
        XCTAssertTrue(viewModel.isDrawingMode)
    }

    func testUndoRemovesLastStroke() async {
        let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
        await viewModel.toggleDrawingMode()
        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        await viewModel.appendStroke([
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
        ])

        await viewModel.undoLastStroke()
        XCTAssertEqual(viewModel.drawnStrokes.count, 1)

        await viewModel.undoLastStroke()
        XCTAssertTrue(viewModel.drawnStrokes.isEmpty)
        XCTAssertNil(viewModel.course)
    }

    /// clear() 호출 후 아직 진행 중인 recompute가 완료되어도
    /// course를 부활시키지 않는다 (phantom-course 방지).
    func testClearInvalidatesInFlightRecompute() async {
        let gatedService = GatedCoursePlanningService()
        let viewModel = CoursePlannerPageViewModel(
            coursePlanningService: gatedService,
            locationService: FakeLocationService()
        )
        // 충분한 간격의 좌표 2개 → DrawnPathSampler가 둘 다 보존 → route 1회 호출
        let stroke = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]

        // 1) appendStroke를 자식 Task로 실행 — route 호출에서 일시정지됨
        let appendTask = Task { @MainActor in
            await viewModel.appendStroke(stroke)
        }

        // 2) 페이크가 route 안에서 일시정지될 때까지 대기
        while gatedService.isSuspended == false {
            await Task.yield()
        }

        // 3) clear() → recomputeGeneration 증가, course = nil
        viewModel.clear()

        // 4) 게이트 열기 → route가 결과를 반환하지만 세대 불일치로 적용되지 않아야 함
        let staleCourse = PlannedCourse(
            segments: [.drawn(
                coordinates: [
                    CourseCoordinate(latitude: 37.50, longitude: 127.00),
                    CourseCoordinate(latitude: 37.51, longitude: 127.00),
                ],
                distanceMeters: 500
            )]
        )
        gatedService.openGate(returning: staleCourse)

        // 5) 자식 Task 완료 대기
        await appendTask.value

        // 6) 검증: course가 nil로 유지되고 strokes가 비어 있어야 함
        XCTAssertNil(viewModel.course, "clear() 이후 완료된 recompute가 course를 부활시키면 안 됩니다")
        XCTAssertTrue(viewModel.drawnStrokes.isEmpty, "clear()가 strokes를 비워야 합니다")
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

// MARK: - 게이트 기반 레이스 테스트용 페이크

@MainActor
private final class GatedCoursePlanningService: CoursePlanningServiceProtocol {
    private(set) var isSuspended = false
    private var gateContinuation: CheckedContinuation<PlannedCourse, any Error>?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        return try await withCheckedThrowingContinuation { continuation in
            self.gateContinuation = continuation
            self.isSuspended = true
        }
    }

    /// 게이트를 열어 대기 중인 route 호출을 완료시킨다.
    func openGate(returning course: PlannedCourse) {
        guard let continuation = gateContinuation else { return }
        gateContinuation = nil
        isSuspended = false
        continuation.resume(returning: course)
    }
}

// MARK: - 기존 테스트용 페이크

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
            segments: [.tapped(coordinates: [start, destination], distanceMeters: 1200)]
        )
    }
}

@MainActor
private final class FakeLocationService: LocationServiceProtocol {
    var result: Result<CourseCoordinate, Error> = .success(CourseCoordinate(latitude: 37.4979, longitude: 127.0276))
    func currentLocation() async throws -> CourseCoordinate { try result.get() }
}
