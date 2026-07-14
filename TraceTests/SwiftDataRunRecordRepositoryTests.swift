import XCTest
@testable import Trace

nonisolated final class SwiftDataRunRecordRepositoryTests: XCTestCase {
    private func makeRun(
        startedAt: Date, distance: Double = 1000, duration: TimeInterval = 600
    ) -> SavedRun {
        let samples = [
            SavedRunSample(
                timestamp: startedAt, latitude: 37.50, longitude: 127.00,
                altitudeMeters: 20, speedMetersPerSecond: 3
            ),
            SavedRunSample(
                timestamp: startedAt.addingTimeInterval(10), latitude: 37.51, longitude: 127.00,
                altitudeMeters: 21, speedMetersPerSecond: 3.2
            )
        ]
        return SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: startedAt, distanceMeters: distance,
                duration: duration, elevationGainMeters: 4
            ),
            samples: samples
        )
    }

    func test_저장후_요약은_최신순으로_컬럼값을_돌려준다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let older = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeRun(startedAt: Date(timeIntervalSince1970: 2000), distance: 5000)
        try await repo.save(older)
        try await repo.save(newer)

        let summaries = await repo.fetchSummaries()
        XCTAssertEqual(summaries.map(\.id), [newer.summary.id, older.summary.id]) // 최신순
        XCTAssertEqual(summaries.first?.distanceMeters, 5000)
        XCTAssertEqual(summaries.first?.duration, 600)
    }

    func test_단건조회는_샘플까지_복원한다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let run = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        try await repo.save(run)

        let fetched = await repo.fetchRun(id: run.summary.id)
        XCTAssertEqual(fetched, run) // 요약+샘플 왕복 무손실
    }

    func test_삭제하면_요약목록에서_사라진다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let run = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        try await repo.save(run)
        try await repo.deleteRun(id: run.summary.id)
        let summaries = await repo.fetchSummaries()
        XCTAssertTrue(summaries.isEmpty)
        let fetched = await repo.fetchRun(id: run.summary.id)
        XCTAssertNil(fetched)
    }

    func test_손상blob은_디코드가_nil을_돌려준다() {
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunSamples(Data("not json".utf8)))
    }

    func test_미래버전blob은_디코드가_nil을_돌려준다() {
        let payload = Data(#"{"version":999,"samples":[]}"#.utf8)
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunSamples(payload))
    }
}
