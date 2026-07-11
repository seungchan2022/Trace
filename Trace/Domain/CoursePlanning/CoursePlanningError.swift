import Foundation

enum CoursePlanningError: Error, Equatable, Sendable {
    case routeNotFound
    case requestFailed
    case throttled
}
