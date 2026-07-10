import Foundation

// 이름 붙여 저장한 코스 — 스냅샷 의미론: 저장 후 세션 편집과 무관하게 불변 (MVP11 스펙 §2)
nonisolated struct SavedCourse: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var segments: [CourseSegment]

    var distanceMeters: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }
}
