import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT() -> CoursePlannerPageViewModel {
        CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
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
private final class StubLocationService: LocationServiceProtocol {
    var stubbedLocation: CourseCoordinate? = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    var stubbedError: Error?

    func currentLocation() async throws -> CourseCoordinate {
        if let error = stubbedError { throw error }
        return stubbedLocation!
    }
}
