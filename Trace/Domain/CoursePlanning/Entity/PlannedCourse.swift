import Foundation

nonisolated struct PlannedCourse: Equatable, Sendable {
    var segments: [CourseSegment]

    // 세그먼트 사이 첫 좌표 중복 제거: i>0이면 첫 좌표를 dropFirst
    var coordinates: [CourseCoordinate] {
        segments.enumerated().flatMap { i, seg in
            i == 0 ? seg.coordinates : Array(seg.coordinates.dropFirst())
        }
    }

    var distanceMeters: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }
}
