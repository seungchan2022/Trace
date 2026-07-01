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

    // Draw mode: accumulated drawn strokes (no session seed — starts empty)
    private var accumulatedCoordinates: [CourseCoordinate] = []
    private var accumulatedDistance: Double = 0

    // Draw mode: per-stroke tracking for incremental undo
    private(set) var drawnStrokes: [[CourseCoordinate]] = []
    private(set) var strokeEntries: [StrokeEntry] = []

    // UI state
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
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

    var canUndo: Bool {
        switch interactionMode {
        case .tap:  return !session.segments.isEmpty
        case .draw: return !drawnStrokes.isEmpty || !session.segments.isEmpty
        }
    }

    // Live course: session history + in-progress draw overlay
    // Draw mode에서 accumulatedCoordinates가 있으면 첫 스트로크 방향에 따라 앞/뒤에 붙여 표시
    var course: PlannedCourse? {
        if interactionMode == .draw, !accumulatedCoordinates.isEmpty {
            let drawn = CourseSegment.drawn(
                coordinates: accumulatedCoordinates,
                distanceMeters: accumulatedDistance
            )
            if let sessionCourse = session.course {
                // 첫 스트로크가 session 출발 쪽에 붙으면 drawn을 앞에 배치
                if strokeEntries.first?.direction == .prepend {
                    return PlannedCourse(segments: [drawn] + sessionCourse.segments)
                }
                return PlannedCourse(segments: sessionCourse.segments + [drawn])
            }
            return PlannedCourse(segments: [drawn])
        }
        return session.course
    }

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
            // First tap when no course exists yet: set pending start, show pin
            pendingTapStart = coordinate
            return
        }

        // Second tap of the initial pair: route start→coordinate then attach
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
            let segment = CourseSegment.tapped(
                coordinates: result.coordinates,
                distanceMeters: result.distanceMeters
            )
            try await session.attach(segment, using: coursePlanningService)
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
            accumulatedCoordinates = []
            accumulatedDistance = 0
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw

        case .draw:
            if !accumulatedCoordinates.isEmpty {
                let drawnSegment = CourseSegment.drawn(
                    coordinates: accumulatedCoordinates,
                    distanceMeters: accumulatedDistance
                )
                do {
                    try await session.attach(drawnSegment, using: coursePlanningService)
                } catch {
                    errorMessage = "경로를 저장할 수 없습니다."
                }
            }
            drawnStrokes = []
            strokeEntries = []
            accumulatedCoordinates = []
            accumulatedDistance = 0
            recomputeGeneration += 1
            errorMessage = errorMessage  // attach 실패 시 에러 유지
            interactionMode = .tap
        }
    }

    // MARK: - Draw Mode

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        drawnStrokes.append(stroke)
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await incrementalRoute(rawStroke: stroke, generation: generation)
    }

    // MARK: - Undo / Clear

    func undoLastStroke() async {
        switch interactionMode {
        case .tap:
            session.undo()

        case .draw:
            guard strokeEntries.popLast() != nil else {
                // 그려진 스트로크 없음 → 직전 session 세그먼트 제거
                session.undo()
                return
            }
            drawnStrokes.removeLast()
            recomputeGeneration += 1

            if strokeEntries.isEmpty {
                accumulatedCoordinates = []
                accumulatedDistance = 0
                errorMessage = nil
            } else {
                recomputeGeneration += 1
                let generation = recomputeGeneration
                let savedStrokes = drawnStrokes
                strokeEntries = []
                accumulatedCoordinates = []
                accumulatedDistance = 0
                errorMessage = nil

                for stroke in savedStrokes {
                    await incrementalRoute(rawStroke: stroke, generation: generation)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                }
            }
        }
    }

    func clear() {
        recomputeGeneration += 1
        session.clear()
        pendingTapStart = nil
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Private

    private func incrementalRoute(rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        // 첫 스트로크(accumulated 비어 있음)는 session 경로 기준으로 방향 판단
        // 이후 스트로크는 기존 drawn context 기준
        let contextStart = accumulatedCoordinates.isEmpty ? session.course?.coordinates.first : accumulatedCoordinates.first
        let contextEnd   = accumulatedCoordinates.isEmpty ? session.course?.coordinates.last  : accumulatedCoordinates.last
        let attachment = StrokeDirectionResolver.resolve(
            newStroke: sampled,
            existingCourseStart: contextStart,
            existingCourseEnd: contextEnd
        )
        let oriented = attachment.orientedStroke

        isLoading = true
        errorMessage = nil

        do {
            var newCoords: [CourseCoordinate] = []
            var newDistance = 0.0
            for i in 0..<(oriented.count - 1) {
                let leg = try await coursePlanningService.route(from: oriented[i], to: oriented[i + 1])
                guard generation == recomputeGeneration else { isLoading = false; return }
                newCoords.append(contentsOf: newCoords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                newDistance += leg.distanceMeters
            }

            if accumulatedCoordinates.isEmpty {
                // 첫 스트로크: 방향(prepend/append) 감지 후 initial 스타일로 할당
                // direction은 strokeEntries에 기록되어 course computed의 display 순서에 사용됨
                accumulatedCoordinates = newCoords
                accumulatedDistance = newDistance
            } else {
                switch attachment.direction {
                case .initial:
                    accumulatedCoordinates = newCoords
                    accumulatedDistance = newDistance
                case .append:
                    if let existingEnd = accumulatedCoordinates.last, let newStart = newCoords.first {
                        let connection = try await coursePlanningService.route(from: existingEnd, to: newStart)
                        guard generation == recomputeGeneration else { isLoading = false; return }
                        accumulatedCoordinates.append(contentsOf: Array(connection.coordinates.dropFirst()))
                        accumulatedDistance += connection.distanceMeters
                    }
                    accumulatedCoordinates.append(contentsOf: Array(newCoords.dropFirst()))
                    accumulatedDistance += newDistance
                case .prepend:
                    if let existingStart = accumulatedCoordinates.first, let newEnd = newCoords.last {
                        let connection = try await coursePlanningService.route(from: newEnd, to: existingStart)
                        guard generation == recomputeGeneration else { isLoading = false; return }
                        var merged = newCoords
                        merged.append(contentsOf: Array(connection.coordinates.dropFirst()))
                        merged.append(contentsOf: Array(accumulatedCoordinates.dropFirst()))
                        accumulatedDistance += connection.distanceMeters + newDistance
                        accumulatedCoordinates = merged
                    }
                }
            }

            strokeEntries.append(StrokeEntry(
                orientedStroke: oriented,
                direction: attachment.direction,
                routedCoordinateCount: newCoords.count,
                routedDistance: newDistance
            ))
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
            drawnStrokes.removeLast()
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
            drawnStrokes.removeLast()
        }
        isLoading = false
    }
}
