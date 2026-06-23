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
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private var recomputeGeneration = 0

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    func bootstrapLocation() async {
        do {
            initialCameraCoordinate = try await locationService.currentLocation()
        } catch LocationError.denied {
            showLocationDeniedAlert = true
            initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
        } catch {
            initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
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
        await recomputeSnappedCourse(generation: generation)
    }

    func undoLastStroke() async {
        guard drawnStrokes.isEmpty == false else { return }
        drawnStrokes.removeLast()
        if drawnStrokes.isEmpty {
            recomputeGeneration += 1
            course = nil
            errorMessage = nil
        } else {
            recomputeGeneration += 1
            let generation = recomputeGeneration
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard generation == recomputeGeneration else { return }
            await recomputeSnappedCourse(generation: generation)
        }
    }

    func clear() {
        recomputeGeneration += 1
        startCoordinate = nil
        destinationCoordinate = nil
        drawnStrokes = []
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

    private func recomputeSnappedCourse(generation: Int) async {
        let allPoints = drawnStrokes.flatMap { $0 }
        let sampled = DrawnPathSampler.sample(allPoints)
        guard sampled.count >= 2 else { course = nil; return }

        isLoading = true
        errorMessage = nil
        do {
            let snapped = try await coursePlanningService.snappedRoute(through: sampled)
            guard generation == recomputeGeneration else { return }
            course = snapped
        } catch {
            guard generation == recomputeGeneration else { return }
            errorMessage = "경로를 계산할 수 없습니다."
        }
        isLoading = false
    }
}
