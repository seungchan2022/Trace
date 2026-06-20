import Foundation

struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService()
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService()
        )
    }
}

private final class UITestingCoursePlanningService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        if ProcessInfo.processInfo.arguments.contains("-traceRouteFailure") {
            throw CoursePlanningError.routeNotFound
        }

        return PlannedCourse(
            coordinates: [
                start,
                CourseCoordinate(
                    latitude: (start.latitude + destination.latitude) / 2 + 0.001,
                    longitude: (start.longitude + destination.longitude) / 2
                ),
                destination
            ],
            distanceMeters: 1200
        )
    }
}

private final class UITestingLocationService: LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate {
        CourseCoordinate(latitude: 37.5666, longitude: 126.9784) // 서울시청 고정
    }
}
