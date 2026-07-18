import Foundation
import SwiftData

// SwiftData 어댑터 — 러닝 기록은 코스와 별도 스토어 파일에 저장한다(스펙 §2 저장소 분리:
// 기존 코스 스토어에 스키마 변경을 가하지 않아 마이그레이션 리스크 0).
actor SwiftDataRunRecordRepository: RunRecordRepositoryProtocol {
    enum RepositoryError: Error {
        case storeUnavailable
        case recordUnavailable
    }

    private let inMemory: Bool
    // 컨텍스트는 첫 사용 시 actor 실행기 위에서 생성 — main 스레드 init에서 만들면 affinity 위반
    // (코스 어댑터와 동일, 2026-07-08 QA 교훈).
    private lazy var context: ModelContext? = Self.makeContext(inMemory: inMemory)

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    // 컨테이너 생성 실패 정책(스펙 §5): ① 정상 생성 → ② 손상 스토어 백업 후 재생성(자산 즉시
    // 삭제 금지) → ③ in-memory 폴백 → ④ nil(모든 연산 no-op/throw). 런치 크래시 금지.
    private nonisolated static func makeContext(inMemory: Bool) -> ModelContext? {
        let schema = Schema([RunRecordModel.self])

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "TraceRunStore.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

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

    // MARK: - RunRecordRepositoryProtocol

    func save(_ run: SavedRun) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: run.samples.map(RunPersistenceDTO.Sample.init),
            pauses: run.pauses.map(RunPersistenceDTO.Pause.init),
            goal: RunPersistenceDTO.Goal(run.goal),
            waypoints: run.waypoints.map(RunPersistenceDTO.Waypoint.init)
        )
        let payload = try JSONEncoder().encode(dto)
        context.insert(RunRecordModel(
            id: run.summary.id,
            startedAt: run.summary.startedAt,
            distanceMeters: run.summary.distanceMeters,
            durationSeconds: run.summary.duration,
            elevationGainMeters: run.summary.elevationGainMeters,
            payload: payload
        ))
        try context.save()
    }

    func fetchSummaries() async -> [SavedRunSummary] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<RunRecordModel>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        // 컬럼만 읽는다 — payload는 건드리지 않는다(스펙 §2 목록 성능)
        return records.map { record in
            SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            )
        }
    }

    func fetchRun(id: UUID) async -> SavedRun? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try? context.fetch(descriptor).first else { return nil }
        // 해독 실패(손상·미래 버전)는 nil — 목록 요약은 컬럼 기반이라 계속 유효(스펙 §6 우아한 강등)
        guard let payload = Self.decodeRunPayload(record.payload) else { return nil }
        return SavedRun(
            summary: SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            ),
            samples: payload.samples,
            pauses: payload.pauses,
            goal: payload.goal,
            waypoints: payload.waypoints
        )
    }

    func deleteRun(id: UUID) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    func updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == runID }
        )
        guard let record = try context.fetch(descriptor).first,
              let payload = Self.decodeRunPayload(record.payload)
        else { throw RepositoryError.recordUnavailable }
        // 샘플·일시정지·목표는 그대로, 포인트만 교체해 재직렬화(버전은 현재로 승격)
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: payload.samples.map(RunPersistenceDTO.Sample.init),
            pauses: payload.pauses.map(RunPersistenceDTO.Pause.init),
            goal: RunPersistenceDTO.Goal(payload.goal),
            waypoints: waypoints.map(RunPersistenceDTO.Waypoint.init)
        )
        record.payload = try JSONEncoder().encode(dto)
        try context.save()
    }

    // MARK: - Decode (테스트 가능한 손상 처리 경로)

    static func decodeRunPayload(
        _ data: Data
    ) -> (samples: [SavedRunSample], pauses: [RunPauseInterval], goal: RunGoal, waypoints: [RunWaypoint])? {
        guard let dto = try? JSONDecoder().decode(RunPersistenceDTO.Run.self, from: data),
              dto.version <= RunPersistenceDTO.currentVersion else { return nil }
        return (
            dto.samples.map(\.domain), (dto.pauses ?? []).map(\.domain),
            dto.goal?.domain ?? .open, (dto.waypoints ?? []).map(\.domain)
        )
    }
}
