import Foundation

@MainActor
protocol LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate
}
