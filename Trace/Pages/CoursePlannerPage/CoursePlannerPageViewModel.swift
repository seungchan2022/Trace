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

    private let coursePlanningService: CoursePlanningServiceProtocol

    init(coursePlanningService: CoursePlanningServiceProtocol) {
        self.coursePlanningService = coursePlanningService
    }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
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
}
