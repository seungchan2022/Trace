import Foundation

struct PlannedCourse: Equatable, Sendable {
    let coordinates: [CourseCoordinate]
    let distanceMeters: Double
}
