import Foundation

enum CoursePlanningError: Error, Equatable {
    case routeNotFound
    case requestFailed
    case throttled
}
