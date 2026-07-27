import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (MVP11 스펙 §2).
enum CoursePersistenceDTO: Sendable {
    static let currentVersion = 1

    struct Coordinate: Codable {
        let lat: Double
        let lon: Double
    }

    struct Segment: Codable {
        enum Kind: String, Codable {
            case tapped, drawn, roundTrip
        }
        let kind: Kind
        let coordinates: [Coordinate]
        let distanceMeters: Double
    }

    struct Course: Codable {
        let version: Int
        let segments: [Segment]
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension CoursePersistenceDTO.Coordinate {
    init(_ coordinate: CourseCoordinate) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }
    var domain: CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }
}

extension CoursePersistenceDTO.Segment {
    init(_ segment: CourseSegment) {
        let coords = segment.coordinates.map(CoursePersistenceDTO.Coordinate.init)
        switch segment {
        case .tapped(_, let distance):    self.init(kind: .tapped, coordinates: coords, distanceMeters: distance)
        case .drawn(_, let distance):     self.init(kind: .drawn, coordinates: coords, distanceMeters: distance)
        case .roundTrip(_, let distance): self.init(kind: .roundTrip, coordinates: coords, distanceMeters: distance)
        }
    }

    var domain: CourseSegment {
        let coords = coordinates.map(\.domain)
        switch kind {
        case .tapped:    return .tapped(coordinates: coords, distanceMeters: distanceMeters)
        case .drawn:     return .drawn(coordinates: coords, distanceMeters: distanceMeters)
        case .roundTrip: return .roundTrip(coordinates: coords, distanceMeters: distanceMeters)
        }
    }
}
