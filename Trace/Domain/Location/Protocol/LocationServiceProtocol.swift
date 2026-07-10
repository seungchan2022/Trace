import Foundation

protocol LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate
}
