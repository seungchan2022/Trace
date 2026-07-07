import Foundation

// 코스 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다 — 도메인·ViewModel은
// 저장 방식을 모른다 (MVP11 스펙 §2). 초안 삭제는 빈 스냅샷 저장으로 표현한다.
protocol CourseRepositoryProtocol: Sendable {
    func saveDraft(_ draft: CourseDraft) async throws
    // 손상·부재 시 nil (크래시 금지, 스펙 §2 실패 처리)
    func loadDraft() async -> CourseDraft?
    func saveCourse(_ course: SavedCourse) async throws
    // 최신순 정렬. 손상 행은 건너뛰고 나머지 반환 (스펙 §2)
    func fetchCourses() async -> [SavedCourse]
    func deleteCourse(id: UUID) async throws
}
