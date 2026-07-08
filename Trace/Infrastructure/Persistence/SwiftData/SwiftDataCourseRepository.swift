import Foundation
import SwiftData

// SwiftData 어댑터. actor 직렬화로 "저장은 연산 순서대로"의 실행부를 담당한다
// (호출 순서 보장은 ViewModel의 Task 체인 — 스펙 §2 순서 불변식).
actor SwiftDataCourseRepository: CourseRepositoryProtocol {
    enum RepositoryError: Error {
        case storeUnavailable
    }

    private let inMemory: Bool
    // 컨텍스트는 첫 사용 시 actor 실행기 위에서 생성한다. init은 호출자(main) 스레드에서 실행되므로
    // 여기서 만들면 "main에서 생성한 컨텍스트를 다른 스레드에서 사용"하는 affinity 위반이 된다
    // (실기기 콘솔 "Unbinding from the main queue" 경고, 2026-07-08 QA).
    private lazy var context: ModelContext? = Self.makeContext(inMemory: inMemory)

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    // 컨테이너 생성 실패 정책 (스펙 §2): ① 정상 생성 → ② 스토어 파일을 백업으로 옮기고 재생성
    // (자산 즉시 삭제 금지) → ③ in-memory 폴백 → ④ nil(모든 연산 no-op/throw).
    // 어떤 경우에도 앱은 뜬다 — 런치 크래시 금지.
    private nonisolated static func makeContext(inMemory: Bool) -> ModelContext? {
        let schema = Schema([CourseRecord.self])

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "TraceCourseStore.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        // 스토어 손상 추정 — 백업 이름으로 옮기고 새로 생성
        let backupURL = storeURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).bak")
        try? FileManager.default.moveItem(at: storeURL, to: backupURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) else { return nil }
        return ModelContext(container)
    }

    // MARK: - Saved Courses

    func saveCourse(_ course: SavedCourse) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let dto = CoursePersistenceDTO.Course(
            version: CoursePersistenceDTO.currentVersion,
            segments: course.segments.map(CoursePersistenceDTO.Segment.init)
        )
        let payload = try JSONEncoder().encode(dto)
        context.insert(CourseRecord(
            id: course.id, name: course.name, createdAt: course.createdAt, payload: payload
        ))
        try context.save()
    }

    func fetchCourses() async -> [SavedCourse] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<CourseRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        // 손상 행은 건너뛰고 나머지 반환 (스펙 §2 — 행 삭제는 하지 않는다, 사용자 자산)
        return records.compactMap { record in
            guard let segments = Self.decodeCourseSegments(record.payload) else { return nil }
            return SavedCourse(
                id: record.id, name: record.name, createdAt: record.createdAt, segments: segments
            )
        }
    }

    func deleteCourse(id: UUID) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<CourseRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - Decode (테스트 가능한 손상 처리 경로)

    static func decodeCourseSegments(_ data: Data) -> [CourseSegment]? {
        guard let dto = try? JSONDecoder().decode(CoursePersistenceDTO.Course.self, from: data),
              dto.version <= CoursePersistenceDTO.currentVersion else { return nil }
        return dto.segments.map(\.domain)
    }
}
