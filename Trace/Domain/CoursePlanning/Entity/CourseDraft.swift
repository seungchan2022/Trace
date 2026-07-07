import Foundation

// 작업 중 코스(초안)의 세션 상태 스냅샷. undo가 재시작 후에도 동작하도록
// 시간순(order)·배치(placedAtFront)·왕복 anchor까지 담는다. redo 스택은 담지 않는다 (MVP11 스펙 §2).
struct CourseDraft: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        let segment: CourseSegment
    }

    var entries: [Entry]
    var nextOrder: Int

    var isEmpty: Bool { entries.isEmpty }

    static let empty = CourseDraft(entries: [], nextOrder: 0)
}
