import Foundation

struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol
    let cameraStateStore: CameraStateStore
    let courseRepository: CourseRepositoryProtocol

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService(),
            cameraStateStore: CameraStateStore(),
            courseRepository: SwiftDataCourseRepository()
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        let uiTestingDefaults = UserDefaults(suiteName: "uiTesting") ?? .standard
        return DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService(),
            cameraStateStore: CameraStateStore(defaults: uiTestingDefaults),
            // in-memory: UI 테스트는 런치마다 빈 상태에서 시작 (기존 UI 테스트 전제 보존)
            courseRepository: SwiftDataCourseRepository(inMemory: true)
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
            segments: [.tapped(
                coordinates: [
                    start,
                    CourseCoordinate(
                        latitude: (start.latitude + destination.latitude) / 2 + 0.001,
                        longitude: (start.longitude + destination.longitude) / 2
                    ),
                    destination
                ],
                distanceMeters: 1200
            )]
        )
    }
}

private final class UITestingLocationService: LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate {
        CourseCoordinate(latitude: 37.5666, longitude: 126.9784) // 서울시청 고정
    }
}
