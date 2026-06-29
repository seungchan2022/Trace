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

    func reversed() -> CourseSegment {
        switch self {
        case .tapped(let coords, let dist):
            return .tapped(coordinates: coords.reversed(), distanceMeters: dist)
        case .drawn(let coords, let dist):
            return .drawn(coordinates: coords.reversed(), distanceMeters: dist)
        }
    }
}
