import Foundation
@testable import Trace

// actor로 구현하는 이유: RunRecordRepositoryProtocol은 Sendable을 상속하는데, Swift 6.3의
// isolated-conformance 검사는 Sendable-상속 프로토콜에 대해 @MainActor 격리 conformance
// 형성을 아예 금지한다("cannot form main actor-isolated conformance ... SendableMetatype
// -inheriting protocol"). actor는 이 프로토콜의 기존 구현(SwiftDataRunRecordRepository)과
// 이 저장소 테스트 스위트의 기존 목(MockCourseRepository, CoursePlannerViewModelPersistenceTests.swift)이
// 쓰는 것과 동일한 패턴이다 — 프로퍼티 접근은 actor 경계를 넘으므로 호출부에서 `await`가 필요하다.
actor MockRunRecordRepository: RunRecordRepositoryProtocol {
    enum MockError: Error { case saveFailed }

    private(set) var savedRuns: [SavedRun] = []
    private var failsNextSave = false

    func failNextSave() {
        failsNextSave = true
    }

    func save(_ run: SavedRun) async throws {
        if failsNextSave {
            failsNextSave = false
            throw MockError.saveFailed
        }
        savedRuns.append(run)
    }

    func fetchSummaries() async -> [SavedRunSummary] {
        savedRuns.map(\.summary).sorted { $0.startedAt > $1.startedAt }
    }

    func fetchRun(id: UUID) async -> SavedRun? {
        savedRuns.first { $0.summary.id == id }
    }

    func deleteRun(id: UUID) async throws {
        savedRuns.removeAll { $0.summary.id == id }
    }
}
