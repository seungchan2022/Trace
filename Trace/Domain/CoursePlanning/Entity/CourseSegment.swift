import Foundation

enum CourseSegment: Equatable, Sendable {
    case tapped(coordinates: [CourseCoordinate], distanceMeters: Double)
    case drawn(coordinates: [CourseCoordinate], distanceMeters: Double)

    var coordinates: [CourseCoordinate] {
        switch self {
        case .tapped(let coords, _), .drawn(let coords, _): return coords
        }
    }

    var distanceMeters: Double {
        switch self {
        case .tapped(_, let d), .drawn(_, let d): return d
        }
    }
}
