import Foundation

// 코스 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다 — 도메인·ViewModel은
// 저장 방식을 모른다.
nonisolated protocol CourseRepositoryProtocol: Sendable {
    func saveCourse(_ course: SavedCourse) async throws
    // 최신순 정렬. 손상 행은 건너뛰고 나머지 반환
    func fetchCourses() async -> [SavedCourse]
    func deleteCourse(id: UUID) async throws
}
