import Foundation

enum StrokeDirection: Equatable, Sendable {
    case initial
    case append
    case prepend
}

struct StrokeEntry: Equatable, Sendable {
    let orientedStroke: [CourseCoordinate]
    let direction: StrokeDirection
    var routedCoordinateCount: Int = 0
    var routedDistance: Double = 0
}
