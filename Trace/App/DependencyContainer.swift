import Foundation

struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol

    static func live() -> DependencyContainer {
        DependencyContainer(coursePlanningService: MapKitCoursePlanningService())
    }

    static func uiTesting() -> DependencyContainer {
        DependencyContainer(coursePlanningService: UITestingCoursePlanningService())
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
