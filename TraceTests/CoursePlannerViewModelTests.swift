import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT(locationError: Error? = nil) -> CoursePlannerPageViewModel {
        let locationService = StubLocationService()
        locationService.stubbedError = locationError
        return CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: locationService
        )
    }

    // MARK: - Mode switching

    func testDefaultModeIsTap() {
        let sut = makeSUT()
        XCTAssertEqual(sut.interactionMode, .tap)
    }

    func testToggleToDrawClearsTapState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        XCTAssertNotNil(sut.startCoordinate)

        sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.startCoordinate)
        XCTAssertNil(sut.destinationCoordinate)
        XCTAssertNil(sut.course)
    }

    func testToggleToTapClearsDrawState() async {
        let sut = makeSUT()
        sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        XCTAssertFalse(sut.drawnStrokes.isEmpty)

        sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .tap)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
    }

    func testClearResetsAllState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])

        sut.clear()

        XCTAssertNil(sut.startCoordinate)
        XCTAssertNil(sut.destinationCoordinate)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Location permission

    func testBootstrapSetsAlertOnDenied() async {
        let sut = makeSUT(locationError: LocationError.denied)
        await sut.bootstrapLocation()
        XCTAssertTrue(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate) // 서울시청 폴백
    }

    func testBootstrapNoAlertOnSuccess() async {
        let sut = makeSUT()
        await sut.bootstrapLocation()
        XCTAssertFalse(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Race condition: tap→draw toggle during in-flight route calculation

    // MARK: - Debounce

    func testRapidStrokesDebounceRecompute() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        sut.toggleDrawingMode()

        let stroke1 = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]
        let stroke2 = [
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ]

        // 빠르게 두 스트로크 추가 — 첫 번째의 디바운스가 두 번째에 의해 취소됨
        await sut.appendStroke(stroke1)
        await sut.appendStroke(stroke2)

        // 디바운스 대기 (300ms + 여유)
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 두 스트로크가 저장되었는지 확인
        XCTAssertEqual(sut.drawnStrokes.count, 2)
    }

    // MARK: - Race condition: tap→draw toggle during in-flight route calculation

    func testToggleDuringRouteCalculationDiscardsStaleCourse() async {
        let service = BlockingCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        // Set start coordinate
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        XCTAssertNotNil(sut.startCoordinate)

        // Begin route calculation without awaiting (suspends in route())
        let calculateTask = Task {
            await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        }

        // Wait until route() is executing
        await service.waitUntilRouteEntered()

        // Toggle mode while route is in flight (bumps recomputeGeneration)
        sut.toggleDrawingMode()
        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.course)

        // Allow route() to complete
        service.resumeRoute()
        await calculateTask.value

        // Course should remain nil because generation guard rejected the stale result
        XCTAssertNil(sut.course)
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubCoursePlanningService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    var stubbedResult: PlannedCourse?
    var stubbedError: Error?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedResult ?? PlannedCourse(
            coordinates: [start, destination],
            distanceMeters: 100
        )
    }
}

@MainActor
private final class BlockingCoursePlanningService: CoursePlanningServiceProtocol {
    private var routeEnteredContinuation: CheckedContinuation<Void, Never>?
    private var routeReleaseContinuation: CheckedContinuation<Void, Never>?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        if let continuation = routeEnteredContinuation {
            continuation.resume()
            routeEnteredContinuation = nil
        }

        await withCheckedContinuation { continuation in
            routeReleaseContinuation = continuation
        }

        return PlannedCourse(coordinates: [start, destination], distanceMeters: 100)
    }

    func waitUntilRouteEntered() async {
        await withCheckedContinuation { continuation in
            routeEnteredContinuation = continuation
        }
    }

    func resumeRoute() {
        if let continuation = routeReleaseContinuation {
            continuation.resume()
            routeReleaseContinuation = nil
        }
    }
}

@MainActor
private final class StubLocationService: LocationServiceProtocol {
    var stubbedLocation: CourseCoordinate? = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    var stubbedError: Error?

    func currentLocation() async throws -> CourseCoordinate {
        if let error = stubbedError { throw error }
        return stubbedLocation!
    }
}
