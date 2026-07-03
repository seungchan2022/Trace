import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    // Application layer: mutable course being planned
    let session = CourseEditSession()

    // Tap mode: first tap waits here until second tap routes A→B
    private(set) var pendingTapStart: CourseCoordinate?

    // UI state
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    private(set) var selectedSegmentIndex: Int?
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private var recomputeGeneration = 0

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var canUndo: Bool { !session.segments.isEmpty }

    var course: PlannedCourse? { session.course }

    // course.segments와 같은 순서로 정렬된 attach 순번(색상 identity, prepend에도 안정적)
    var segmentColorKeys: [Int] { session.segmentColorKeys }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
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

    func handleMapTap(at coordinate: CourseCoordinate) async {
        guard interactionMode == .tap else { return }

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
            pendingTapStart = nil
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw

        case .draw:
            recomputeGeneration += 1
            interactionMode = .tap
        }
    }

    // MARK: - Draw Mode

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await routeStrokeAndAttach(stroke, generation: generation)
    }

    private func routeStrokeAndAttach(_ rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

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
        session.undo()
        selectedSegmentIndex = nil
    }

    var canRedo: Bool { session.canRedo }

    func redo() {
        session.redo()
        selectedSegmentIndex = nil
    }

    func clear() {
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
}
