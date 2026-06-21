import Foundation
import Observation

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    private(set) var startCoordinate: CourseCoordinate?
    private(set) var destinationCoordinate: CourseCoordinate?
    private(set) var course: PlannedCourse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var isDrawingMode = false
    private(set) var drawnStrokes: [[CourseCoordinate]] = []

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

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    func bootstrapLocation() async {
        do {
            initialCameraCoordinate = try await locationService.currentLocation()
        } catch {
            initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
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
        isDrawingMode.toggle()
    }

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        drawnStrokes.append(stroke)
        await recomputeSnappedCourse()
    }

    func undoLastStroke() async {
        guard drawnStrokes.isEmpty == false else { return }
        drawnStrokes.removeLast()
        if drawnStrokes.isEmpty {
            recomputeGeneration += 1
            course = nil
            errorMessage = nil
        } else {
            await recomputeSnappedCourse()
        }
    }

    func clear() {
        recomputeGeneration += 1
        drawnStrokes = []
        course = nil
        errorMessage = nil
        isLoading = false
    }

    private func calculateCourse() async {
        guard let startCoordinate, let destinationCoordinate else { return }

        isLoading = true
        errorMessage = nil
        course = nil

        do {
            course = try await coursePlanningService.route(from: startCoordinate, to: destinationCoordinate)
        } catch CoursePlanningError.routeNotFound {
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    private func recomputeSnappedCourse() async {
        let allPoints = drawnStrokes.flatMap { $0 }
        let sampled = DrawnPathSampler.sample(allPoints)
        guard sampled.count >= 2 else { course = nil; return }

        recomputeGeneration += 1
        let generation = recomputeGeneration
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
