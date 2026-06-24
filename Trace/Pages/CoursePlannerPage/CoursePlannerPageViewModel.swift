import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    private(set) var startCoordinate: CourseCoordinate?
    private(set) var destinationCoordinate: CourseCoordinate?
    private(set) var course: PlannedCourse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    private(set) var drawnStrokes: [[CourseCoordinate]] = []
    private(set) var strokeEntries: [StrokeEntry] = []
    private var accumulatedCoordinates: [CourseCoordinate] = []
    private var accumulatedDistance: Double = 0
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

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    func bootstrapLocation() async {
        // 저장된 카메라가 있으면 Page에서 이미 복원했으므로 위치 요청만 하고 카메라는 건드리지 않음
        let hasRestoredCamera = cameraStateStore.restore() != nil

        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera {
                initialCameraCoordinate = location
            }
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
        do {
            return try await locationService.currentLocation()
        } catch {
            return nil
        }
    }

    func handleMapTap(at coordinate: CourseCoordinate) async {
        if startCoordinate == nil || destinationCoordinate != nil {
            startCoordinate = coordinate
            destinationCoordinate = nil
            course = nil
            errorMessage = nil
            isLoading = false
            return
        }

        destinationCoordinate = coordinate
        await calculateCourse()
    }

    func toggleDrawingMode() {
        switch interactionMode {
        case .tap:
            recomputeGeneration += 1
            startCoordinate = nil
            destinationCoordinate = nil
            course = nil
            errorMessage = nil
            isLoading = false
            interactionMode = .draw
        case .draw:
            recomputeGeneration += 1
            drawnStrokes = []
            strokeEntries = []
            accumulatedCoordinates = []
            accumulatedDistance = 0
            course = nil
            errorMessage = nil
            interactionMode = .tap
        }
    }

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        drawnStrokes.append(stroke)
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { return }
        await incrementalRoute(rawStroke: stroke, generation: generation)
    }

    func undoLastStroke() async {
        guard strokeEntries.popLast() != nil else { return }
        drawnStrokes.removeLast()
        recomputeGeneration += 1

        if strokeEntries.isEmpty {
            accumulatedCoordinates = []
            accumulatedDistance = 0
            course = nil
            errorMessage = nil
        } else {
            // 전체 재계산 — drawnStrokes를 순회하여 재구축 (double-sampling 방지)
            recomputeGeneration += 1
            let generation = recomputeGeneration
            let savedStrokes = drawnStrokes
            strokeEntries = []
            accumulatedCoordinates = []
            accumulatedDistance = 0
            course = nil
            errorMessage = nil

            for stroke in savedStrokes {
                await incrementalRoute(rawStroke: stroke, generation: generation)
                guard generation == recomputeGeneration else { return }
            }
        }
    }

    func clear() {
        recomputeGeneration += 1
        startCoordinate = nil
        destinationCoordinate = nil
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        course = nil
        errorMessage = nil
        isLoading = false
    }

    private func calculateCourse() async {
        guard let startCoordinate, let destinationCoordinate else { return }

        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil
        course = nil

        do {
            let route = try await coursePlanningService.route(from: startCoordinate, to: destinationCoordinate)
            guard generation == recomputeGeneration else { return }
            course = route
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    private func incrementalRoute(rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        let attachment = StrokeDirectionResolver.resolve(
            newStroke: sampled,
            existingCourseStart: accumulatedCoordinates.first,
            existingCourseEnd: accumulatedCoordinates.last
        )
        let oriented = attachment.orientedStroke

        isLoading = true
        errorMessage = nil

        do {
            // 1) 새 스트로크 내부 구간 라우팅
            var newCoords: [CourseCoordinate] = []
            var newDistance = 0.0
            for i in 0..<(oriented.count - 1) {
                let leg = try await coursePlanningService.route(from: oriented[i], to: oriented[i + 1])
                guard generation == recomputeGeneration else { return }
                newCoords.append(contentsOf: newCoords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                newDistance += leg.distanceMeters
            }

            // 2) 기존 경로와 연결 구간
            switch attachment.direction {
            case .initial:
                accumulatedCoordinates = newCoords
                accumulatedDistance = newDistance
            case .append:
                if let existingEnd = accumulatedCoordinates.last, let newStart = newCoords.first {
                    let connection = try await coursePlanningService.route(from: existingEnd, to: newStart)
                    guard generation == recomputeGeneration else { return }
                    accumulatedCoordinates.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters
                }
                accumulatedCoordinates.append(contentsOf: Array(newCoords.dropFirst()))
                accumulatedDistance += newDistance
            case .prepend:
                if let existingStart = accumulatedCoordinates.first, let newEnd = newCoords.last {
                    let connection = try await coursePlanningService.route(from: newEnd, to: existingStart)
                    guard generation == recomputeGeneration else { return }
                    var merged = newCoords
                    merged.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    merged.append(contentsOf: Array(accumulatedCoordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters + newDistance
                    accumulatedCoordinates = merged
                }
            }

            let entry = StrokeEntry(
                orientedStroke: oriented,
                direction: attachment.direction,
                routedCoordinateCount: newCoords.count,
                routedDistance: newDistance
            )
            strokeEntries.append(entry)

            course = PlannedCourse(coordinates: accumulatedCoordinates, distanceMeters: accumulatedDistance)
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
            drawnStrokes.removeLast()
        } catch {
            guard generation == recomputeGeneration else { return }
            errorMessage = "경로를 계산할 수 없습니다."
            drawnStrokes.removeLast()
        }
        isLoading = false
    }
}
