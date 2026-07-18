import Foundation

struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol
    let cameraStateStore: CameraStateStore
    let courseRepository: CourseRepositoryProtocol
    let runRecordRepository: RunRecordRepositoryProtocol
    let runSession: RunSession
    let runActivityController: RunActivityController
    let runAudioCoach: RunAudioCoach
    /// coach와 RunPage(ViewModel)가 같은 인스턴스를 공유해야 덕킹 hold/release가 한 곳으로 모인다
    let voiceAnnouncer: VoiceAnnouncerProtocol

    @MainActor
    static func live() -> DependencyContainer {
        let runRecordRepository = SwiftDataRunRecordRepository()
        let runSession = RunSession(locationStream: RunLocationTracker(), recordRepository: runRecordRepository)
        let voiceAnnouncer = SpeechVoiceAnnouncer()
        let runAudioCoach = RunAudioCoach(session: runSession, announcer: voiceAnnouncer)
        return DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService(),
            cameraStateStore: CameraStateStore(),
            courseRepository: SwiftDataCourseRepository(),
            runRecordRepository: runRecordRepository,
            runSession: runSession,
            runActivityController: RunActivityController(session: runSession),
            runAudioCoach: runAudioCoach,
            voiceAnnouncer: voiceAnnouncer
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        let uiTestingDefaults = UserDefaults(suiteName: "uiTesting") ?? .standard
        let runRecordRepository = SwiftDataRunRecordRepository(inMemory: true)
        let runSession = RunSession(locationStream: UITestingRunLocationStream(), recordRepository: runRecordRepository)
        let voiceAnnouncer = NoopVoiceAnnouncer()
        let runAudioCoach = RunAudioCoach(session: runSession, announcer: voiceAnnouncer)
        return DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService(),
            cameraStateStore: CameraStateStore(defaults: uiTestingDefaults),
            // in-memory: UI 테스트가 실기기/다른 테스트의 저장 코스 데이터와 격리되도록
            courseRepository: SwiftDataCourseRepository(inMemory: true),
            runRecordRepository: runRecordRepository,
            runSession: runSession,
            runActivityController: RunActivityController(session: runSession),
            runAudioCoach: runAudioCoach,
            voiceAnnouncer: voiceAnnouncer
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

@MainActor
private final class NoopVoiceAnnouncer: VoiceAnnouncerProtocol {
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {}
}
