import Foundation

// 작업 중 코스(초안)의 세션 상태 스냅샷. undo가 재시작 후에도 동작하도록
// 시간순(order)·배치(placedAtFront)·왕복 anchor까지 담는다. redo 스택은 담지 않는다 (MVP11 스펙 §2).
struct CourseDraft: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        // anchorID가 있을 때만 의미 있음: true = anchor 바로 앞에 삽입(코스 앞쪽 끝 왕복),
        // false = anchor 바로 뒤(코스 뒤쪽 끝 왕복). anchorID가 nil이면 무시된다.
        let anchorInsertsBefore: Bool
        let segment: CourseSegment
    }

    var entries: [Entry]
    var nextOrder: Int

    var isEmpty: Bool { entries.isEmpty }

    static let empty = CourseDraft(entries: [], nextOrder: 0)
}
