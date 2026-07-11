import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

// 지도 핀의 의미 역할. 화면 히트 판정은 View(MapViewRepresentable)가 하고,
// ViewModel은 판정 결과만 받는다 (MapKit 비의존 유지).
enum CoursePinRole: Equatable {
    case start        // 출발 핀
    case end          // 도착 핀
    case merged       // 닫힌 코스의 출발/도착 병합 핀
    case pendingStart // 첫 탭 대기 핀 (특수 동작 없음)
}

@Observable
@MainActor
final class CoursePlannerPageViewModel {
    // Application layer: mutable course being planned
    let session = CourseEditSession()

    // Tap mode: first tap waits here until second tap routes A→B
    private(set) var pendingTapStart: CourseCoordinate?

    // Tap mode: 판별 창(0.35s) 통과를 기다리는 보류 탭 — 임시 마커 표시용.
    // 수명: 보류~확정 흐름 종료(성공/실패/정보 경로)까지. 스펙 '임시 마커' 절.
    private(set) var pendingTapMarker: CourseCoordinate?

    // UI state
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    private(set) var selectedSegmentIndex: Int?
    private(set) var infoMessage: String?
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private let courseRepository: CourseRepositoryProtocol
    private var recomputeGeneration = 0

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore(),
        courseRepository: CourseRepositoryProtocol
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
        self.courseRepository = courseRepository
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var canUndo: Bool { !session.segments.isEmpty }

    var course: PlannedCourse? { session.course }

    // course.segments와 같은 순서로 정렬된 attach 순번(색상 identity, prepend에도 안정적)
    var segmentColorKeys: [Int] { session.segmentColorKeys }

    // 지도 경유점 마커용: 인접 구간이 만나는 경계 좌표 (각 구간의 마지막 좌표, 최종 구간 제외)
    var waypointCoordinates: [CourseCoordinate] {
        guard let segments = course?.segments, segments.count > 1 else { return [] }
        return segments.dropLast().compactMap { $0.coordinates.last }
    }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    // 닫힌 코스(왕복 완성) 판정 — 첫·끝 좌표가 연결 임계값 이내
    var isClosedCourse: Bool {
        guard let course, course.coordinates.count > 1,
              let first = course.coordinates.first,
              let last = course.coordinates.last else { return false }
        return first.distanceMeters(to: last) <= CourseEditSession.connectionThresholdMeters
    }

    // 출발핀 탭 왕복 힌트 노출 조건 (statusPanel)
    var roundTripHintVisible: Bool {
        interactionMode == .tap && course != nil && !isClosedCourse
    }

    // MARK: - Location

    func bootstrapLocation() async {
        let hasRestoredCamera = cameraStateStore.restore() != nil
        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera { initialCameraCoordinate = location }
        } catch LocationError.denied {
            showLocationDeniedAlert = true
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        } catch {
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        }
    }

    func recenterToCurrentLocation() async -> CourseCoordinate? {
        try? await locationService.currentLocation()
    }

    // MARK: - Tap Mode

    // 판별 창(0.35s) 동안 임시 마커를 보여주기 위한 신호. Task 3의 제스처 인식기가 호출한다.
    func pendingTapBegan(at coordinate: CourseCoordinate, hitPin: CoursePinRole?) {
        guard interactionMode == .tap else { return }
        pendingTapMarker = hitPin == nil ? coordinate : nil
    }

    func pendingTapCancelled() {
        pendingTapMarker = nil
    }

    func handleMapTap(at coordinate: CourseCoordinate, hitPin: CoursePinRole? = nil) async {
        guard interactionMode == .tap else { return }
        defer { pendingTapMarker = nil }
        infoMessage = nil

        // 핀 히트 분기 (상호배제, spec 설계 2)
        switch hitPin {
        case .merged:
            infoMessage = "이미 닫힌 코스입니다"
            return
        case .end:
            infoMessage = "이미 도착점입니다"
            return
        case .start:
            guard let course = session.course,
                  let start = course.coordinates.first,
                  let end = course.coordinates.last,
                  course.coordinates.count > 1 else { break }
            // 왕복: 도착점 → 출발점 좌표(스냅). 시작점이 도착점이므로 항상 append.
            await routeAndAttach(from: end, to: start)
            return
        case .pendingStart, nil:
            break
        }

        if pendingTapStart == nil {
            if let start = nearestEndpoint(to: coordinate) {
                await routeAndAttach(from: start, to: coordinate)
                return
            }
            pendingTapStart = coordinate
            return
        }

        guard let start = pendingTapStart else { return }
        pendingTapStart = nil
        await routeAndAttach(from: start, to: coordinate)
    }

    private func nearestEndpoint(to coordinate: CourseCoordinate) -> CourseCoordinate? {
        guard let course = session.course,
              let start = course.coordinates.first,
              let end = course.coordinates.last else { return nil }
        return coordinate.distanceMeters(to: start) <= coordinate.distanceMeters(to: end) ? start : end
    }

    private func routeAndAttach(from start: CourseCoordinate, to coordinate: CourseCoordinate) async {
        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil

        do {
            let result = try await coursePlanningService.route(from: start, to: coordinate)
            guard generation == recomputeGeneration else { isLoading = false; return }
            guard result.coordinates.count >= 2 else {
                errorMessage = "도보 경로를 찾을 수 없습니다."
                isLoading = false
                return
            }
            let segment = CourseSegment.tapped(
                coordinates: result.coordinates,
                distanceMeters: result.distanceMeters
            )
            try await session.attach(segment, using: coursePlanningService)
            selectedSegmentIndex = nil
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    // MARK: - Mode Toggle

    func toggleDrawingMode() async {
        switch interactionMode {
        case .tap:
            infoMessage = nil
            pendingTapStart = nil
            pendingTapMarker = nil
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw

        case .draw:
            infoMessage = nil
            recomputeGeneration += 1
            interactionMode = .tap
        }
    }

    // MARK: - Draw Mode

    func appendStroke(_ stroke: [CourseCoordinate], startPinHit: CoursePinRole? = nil) async {
        infoMessage = nil
        guard stroke.count >= 2 else { return }
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await routeStrokeAndAttach(stroke, startPinHit: startPinHit, generation: generation)
    }

    // 시작점 치환: 화면 24pt 핀 히트(줌 무관 시각 근접) 우선, 실거리 20m 폴백(고배율 줌인에서
    // 24pt < 20m인 구간을 커버 — 문서 리뷰 2026-07-04). 치환이 없으면 도로 스냅 드리프트로
    // attach 근접 판정이 깨진다 (기존 주석의 원 문제).
    private func snappedStrokeStart(
        _ sampled: [CourseCoordinate], startPinHit: CoursePinRole?
    ) -> CourseCoordinate? {
        guard let course = session.course,
              let existingStart = course.coordinates.first,
              let existingEnd = course.coordinates.last,
              let first = sampled.first else { return nil }
        switch startPinHit {
        case .end, .merged: return existingEnd
        case .start: return existingStart
        case .pendingStart, nil: break
        }
        let threshold = CourseEditSession.connectionThresholdMeters
        if first.distanceMeters(to: existingEnd) <= threshold { return existingEnd }
        if first.distanceMeters(to: existingStart) <= threshold { return existingStart }
        return nil
    }

    private func routeStrokeAndAttach(
        _ rawStroke: [CourseCoordinate], startPinHit: CoursePinRole?, generation: Int
    ) async {
        var sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        if let snappedStart = snappedStrokeStart(sampled, startPinHit: startPinHit) {
            sampled[0] = snappedStart
        }

        isLoading = true
        errorMessage = nil

        do {
            var coords: [CourseCoordinate] = []
            var distance = 0.0
            for i in 0..<(sampled.count - 1) {
                let leg = try await coursePlanningService.route(from: sampled[i], to: sampled[i + 1])
                guard generation == recomputeGeneration else { isLoading = false; return }
                guard leg.coordinates.count >= 2 else {
                    errorMessage = "도보 경로를 찾을 수 없습니다."
                    isLoading = false
                    return
                }
                coords.append(contentsOf: coords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                distance += leg.distanceMeters
            }
            let segment = CourseSegment.drawn(coordinates: coords, distanceMeters: distance)
            try await session.attach(segment, using: coursePlanningService)
            selectedSegmentIndex = nil
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }
        isLoading = false
    }

    // MARK: - Undo / Clear

    func undo() async {
        infoMessage = nil
        session.undo()
        selectedSegmentIndex = nil
    }

    var canRedo: Bool { session.canRedo }

    func redo() {
        infoMessage = nil
        session.redo()
        selectedSegmentIndex = nil
    }

    func clear() {
        infoMessage = nil
        recomputeGeneration += 1
        session.clear()
        pendingTapStart = nil
        selectedSegmentIndex = nil
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Segment selection (지도 연동용, Task 5에서 사용)

    func selectSegment(at index: Int?) {
        selectedSegmentIndex = index
    }

    // MARK: - Round Trip (MVP11 스펙 §4) — colorKey = 세션 order

    func canInsertRoundTrip(afterColorKey key: Int) -> Bool {
        session.canInsertRoundTrip(afterOrder: key)
    }

    func insertRoundTrip(afterColorKey key: Int) {
        infoMessage = nil
        session.insertRoundTrip(afterOrder: key)
        selectedSegmentIndex = nil
    }

    // MARK: - Whole Course Round Trip (2026-07-08 추가)

    var canInsertWholeCourseRoundTrip: Bool {
        session.canInsertWholeCourseRoundTrip()
    }

    func insertWholeCourseRoundTrip() {
        infoMessage = nil
        session.insertWholeCourseRoundTrip()
        selectedSegmentIndex = nil
    }

    // MARK: - Saved Courses (MVP11 스펙 §3)

    private(set) var savedCourses: [SavedCourse] = []
    var isCourseListPresented = false
    var isSavePromptPresented = false
    var courseNameInput = ""
    private(set) var pendingLoadCourse: SavedCourse?

    var canSaveCourse: Bool { course != nil }

    // 스냅샷 의미론: 저장 시점의 세그먼트를 복사 — 이후 편집과 무관 (스펙 §2)
    func saveCurrentCourse() async {
        let name = courseNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let course = session.course else { return }
        let saved = SavedCourse(id: UUID(), name: name, createdAt: Date(), segments: course.segments)
        do {
            try await courseRepository.saveCourse(saved)
            infoMessage = "'\(name)' 저장됨"
            courseNameInput = ""
        } catch {
            errorMessage = "코스 저장에 실패했습니다."
        }
    }

    func presentCourseList() async {
        savedCourses = await courseRepository.fetchCourses()
        isCourseListPresented = true
    }

    // 작업 중 코스가 있으면 교체 확인을 거친다 (스펙 §3)
    func requestLoad(_ saved: SavedCourse) async {
        if course == nil {
            applyLoadedCourse(saved)
        } else {
            pendingLoadCourse = saved
        }
    }

    func confirmPendingLoad() async {
        guard let saved = pendingLoadCourse else { return }
        pendingLoadCourse = nil
        applyLoadedCourse(saved)
    }

    func cancelPendingLoad() {
        pendingLoadCourse = nil
    }

    // 스와이프 삭제는 확인 알럿을 거친다 (스펙 §3)
    private(set) var pendingDeleteCourse: SavedCourse?

    func requestDelete(_ saved: SavedCourse) {
        pendingDeleteCourse = saved
    }

    func confirmPendingDelete() async {
        guard let saved = pendingDeleteCourse else { return }
        pendingDeleteCourse = nil
        await deleteSavedCourse(saved)
    }

    func cancelPendingDelete() {
        pendingDeleteCourse = nil
    }

    func deleteSavedCourse(_ saved: SavedCourse) async {
        do {
            try await courseRepository.deleteCourse(id: saved.id)
            savedCourses.removeAll { $0.id == saved.id }
        } catch {
            errorMessage = "코스 삭제에 실패했습니다."
        }
    }

    private func applyLoadedCourse(_ saved: SavedCourse) {
        session.load(segments: saved.segments)
        pendingTapStart = nil
        selectedSegmentIndex = nil
        errorMessage = nil
        infoMessage = nil
        isCourseListPresented = false
    }
}
