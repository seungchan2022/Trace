import Foundation

@MainActor
protocol CoursePlanningServiceProtocol {
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse
}
