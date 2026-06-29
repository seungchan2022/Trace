import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT(locationError: Error? = nil) -> CoursePlannerPageViewModel {
        let locationService = StubLocationService()
        locationService.stubbedError = locationError
        let defaults = UserDefaults(suiteName: "viewModelTests")!
        defaults.removePersistentDomain(forName: "viewModelTests")
        return CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: locationService,
            cameraStateStore: CameraStateStore(defaults: defaults)
        )
    }

    // MARK: - Mode switching

    func testDefaultModeIsTap() {
        let sut = makeSUT()
        XCTAssertEqual(sut.interactionMode, .tap)
    }

    func testToggleToDrawPreservesTapRouteAsHistory() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNotNil(sut.course, "탭 경로가 session으로 보존되어야 함")
    }

    func testToggleToTapPreservesDrawnRouteAsHistory() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .tap)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNotNil(sut.course, "그리기 경로가 session으로 보존되어야 함")
    }

    func testClearResetsAllState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])

        sut.clear()

        XCTAssertNil(sut.pendingTapStart)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Location permission

    func testBootstrapSetsAlertOnDenied() async {
        let sut = makeSUT(locationError: LocationError.denied)
        await sut.bootstrapLocation()
        XCTAssertTrue(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    func testBootstrapNoAlertOnSuccess() async {
        let sut = makeSUT()
        await sut.bootstrapLocation()
        XCTAssertFalse(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Camera restore

    func testBootstrapDoesNotOverrideWhenCameraRestored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrap")!)
        UserDefaults(suiteName: "testBootstrap")!.removePersistentDomain(forName: "testBootstrap")
        store.save(latitude: 35.0, longitude: 129.0, latitudinalMeters: 1000, longitudinalMeters: 1000)

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNil(sut.initialCameraCoordinate)
    }

    func testBootstrapSetsCoordinateWhenNoCameraStored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrapEmpty")!)
        UserDefaults(suiteName: "testBootstrapEmpty")!.removePersistentDomain(forName: "testBootstrapEmpty")

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Tap accumulation (MVP6 핵심)

    func testFirstTap_setsPendingStart() async {
        let sut = makeSUT()
        let coord = CourseCoordinate(latitude: 37.5, longitude: 127.0)
        await sut.handleMapTap(at: coord)
        XCTAssertEqual(sut.pendingTapStart?.latitude ?? 0, coord.latitude, accuracy: 0.0001)
        XCTAssertNil(sut.course, "첫 탭만으로 course가 생기면 안 됨")
    }

    func testSecondTap_routesAndCommitsToSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertEqual(sut.session.segments.count, 1)
        XCTAssertNotNil(sut.course)
    }

    func testMultipleTapPairs_accumulate() async {
        let sut = makeSUT()
        // 첫 번째 쌍: A→B
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // 두 번째 쌍: C→D
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2, "탭이 누적되어야 함 — 두 번째 쌍이 덮어쓰면 안 됨")
        XCTAssertNotNil(sut.course)
    }

    func testTapUndo_removesLastSegment() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2)

        await sut.undoLastStroke()
        XCTAssertEqual(sut.session.segments.count, 1)
    }

    // MARK: - Incremental stroke pipeline

    func testAppendStrokeNearEndAppendsAndRoutesOnlyNewSegment() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        let callsAfterFirst = service.routeCallCount

        service.routeCallCount = 0
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertTrue(service.routeCallCount < callsAfterFirst + 3)
        XCTAssertNotNil(sut.course)
    }

    func testAppendStrokeNearStartPrepends() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.509, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(sut.course)
        if let first = sut.course?.coordinates.first {
            XCTAssertTrue(abs(first.latitude - 37.500) < 0.005)
        }
    }

    // MARK: - Undo with session

    func testUndoAllStrokesRestoresHistory() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let tapDistance = sut.course?.distanceMeters ?? 0

        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.undoLastStroke()

        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters ?? 0, tapDistance, accuracy: 1)
    }

    func testDrawModeUndoWithNoStrokes_fallsThroughToSession() async {
        let sut = makeSUT()
        // Build a tap segment in session
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // Enter draw mode (no strokes drawn)
        await sut.toggleDrawingMode()
        XCTAssertTrue(sut.drawnStrokes.isEmpty)

        // Undo in draw mode with 0 drawn strokes → falls through to session.undo()
        await sut.undoLastStroke()

        XCTAssertTrue(sut.session.segments.isEmpty, "draw mode undo with no strokes should fall through to session.undo()")
        XCTAssertNil(sut.course)
    }

    func testClearAlsoResetsSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        await sut.toggleDrawingMode()
        XCTAssertNotNil(sut.course)

        sut.clear()

        XCTAssertNil(sut.course)
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
    }

    func testUndoRemovesLastAddedStroke() async {
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.undoLastStroke()

        XCTAssertEqual(sut.drawnStrokes.count, 1)
        XCTAssertNotNil(sut.course)
    }

    func testThrottleErrorShowsUserMessage() async {
        let service = StubCoursePlanningService()
        service.stubbedError = CoursePlanningError.throttled
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.errorMessage, "요청이 많아 잠시 후 다시 시도해주세요")
    }

    // MARK: - Debounce

    func testRapidStrokesDebounceRecompute() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ])

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.drawnStrokes.count, 2)
    }

    // MARK: - Race condition

    func testToggleDuringRouteCalculationDiscardsStaleCourse() async {
        let service = BlockingCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        XCTAssertNotNil(sut.pendingTapStart)

        let calculateTask = Task {
            await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        }

        await service.waitUntilRouteEntered()

        await sut.toggleDrawingMode()
        XCTAssertEqual(sut.interactionMode, .draw)
        // draw 전환 시 session에 아직 아무것도 없으면 course = nil
        XCTAssertNil(sut.course)

        service.resumeRoute()
        await calculateTask.value

        XCTAssertNil(sut.course)
    }

    // MARK: - Path stitching

    func testTapRouteIsPreservedWhenEnteringDrawMode() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let tapCourse = sut.course
        XCTAssertNotNil(tapCourse)

        await sut.toggleDrawingMode()

        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters, tapCourse?.distanceMeters)
    }

    func testDrawRouteIsPreservedWhenEnteringTapMode() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        let drawCourse = sut.course
        XCTAssertNotNil(drawCourse)

        await sut.toggleDrawingMode()

        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters ?? 0, drawCourse?.distanceMeters ?? 0, accuracy: 1)
    }

    func testDrawRouteIsPreservedAsCourseOnModeSwitch() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNotNil(sut.course)
    }

    func testDrawNearRouteStartPrependsCorrectly() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.49, longitude: 127.00),
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(sut.course)
        if let first = sut.course?.coordinates.first {
            XCTAssertTrue(first.latitude < 37.505, "출발이 A(37.50) 이전으로 prepend 되어야 함")
        }
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
            segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
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
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }

    func waitUntilRouteEntered() async {
        await withCheckedContinuation { continuation in
            routeEnteredContinuation = continuation
        }
    }

    func resumeRoute() {
        routeReleaseContinuation?.resume()
        routeReleaseContinuation = nil
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
