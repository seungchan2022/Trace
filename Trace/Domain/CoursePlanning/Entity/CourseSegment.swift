import Foundation

nonisolated enum CourseSegment: Equatable, Sendable {
    case tapped(coordinates: [CourseCoordinate], distanceMeters: Double)
    case drawn(coordinates: [CourseCoordinate], distanceMeters: Double)
    // 기존 구간 뒤에 삽입되는 "갔다 되돌아오기"(역+정 병합) — 좌표 복제라 라우팅 비호출 (MVP11 스펙 §4)
    case roundTrip(coordinates: [CourseCoordinate], distanceMeters: Double)

    var coordinates: [CourseCoordinate] {
        switch self {
        case .tapped(let coords, _), .drawn(let coords, _), .roundTrip(let coords, _): return coords
        }
    }

    var distanceMeters: Double {
        switch self {
        case .tapped(_, let d), .drawn(_, let d), .roundTrip(_, let d): return d
        }
    }

    var isRoundTrip: Bool {
        if case .roundTrip = self { return true }
        return false
    }

    func reversed() -> CourseSegment {
        switch self {
        case .tapped(let coords, let dist):
            return .tapped(coordinates: coords.reversed(), distanceMeters: dist)
        case .drawn(let coords, let dist):
            return .drawn(coordinates: coords.reversed(), distanceMeters: dist)
        case .roundTrip(let coords, let dist):
            return .roundTrip(coordinates: coords.reversed(), distanceMeters: dist)
        }
    }
}
