import XCTest
@testable import Trace

nonisolated final class SwiftDataRunRecordRepositoryTests: XCTestCase {
    private func makeRun(
        startedAt: Date, distance: Double = 1000, duration: TimeInterval = 600,
        pauses: [RunPauseInterval] = []
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
            samples: samples,
            pauses: pauses
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
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunPayload(Data("not json".utf8)))
    }

    func test_미래버전blob은_디코드가_nil을_돌려준다() {
        let payload = Data(#"{"version":999,"samples":[]}"#.utf8)
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunPayload(payload))
    }

    func test_일시정지_구간이_저장_후_그대로_복원된다() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let pauses = [
            RunPauseInterval(start: start.addingTimeInterval(100), end: start.addingTimeInterval(160)),
            RunPauseInterval(start: start.addingTimeInterval(400), end: start.addingTimeInterval(430))
        ]
        let run = makeRun(startedAt: start, pauses: pauses)
        try await repository.save(run)

        let fetched = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(fetched?.pauses, pauses)
    }

    func test_v1_payload는_빈_일시정지로_해독된다() {
        // pauses 필드가 없던 기존(v1) blob — 하위호환 확인
        let v1JSON = """
        {"version":1,"samples":[{"t":700000000,"lat":37.5,"lon":127.0,"alt":10,"spd":3}]}
        """
        guard let data = v1JSON.data(using: .utf8) else { return XCTFail("픽스처 인코딩 실패") }
        let decoded = SwiftDataRunRecordRepository.decodeRunPayload(data)
        XCTAssertEqual(decoded?.samples.count, 1)
        XCTAssertEqual(decoded?.pauses, [])
    }

    func test_목표가_저장되고_복원된다() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: base, distanceMeters: 5000,
                duration: 1750, elevationGainMeters: 12
            ),
            samples: [
                SavedRunSample(timestamp: base, latitude: 37.5666, longitude: 126.9784,
                               altitudeMeters: 10, speedMetersPerSecond: 3),
                SavedRunSample(timestamp: base.addingTimeInterval(1750), latitude: 37.6115, longitude: 126.9784,
                               altitudeMeters: 12, speedMetersPerSecond: 3)
            ],
            pauses: [],
            goal: .distance(meters: 5000)
        )
        try await repository.save(run)
        let loaded = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(loaded?.goal, .distance(meters: 5000))
    }

    func test_구버전_blob은_자유목표로_해독된다() {
        // v2(사이클 2) 포맷 — goal 필드 자체가 없다
        let json = """
        {"version":2,"samples":[{"t":700000000,"lat":37.5,"lon":127.0,"alt":10,"spd":3}],"pauses":[]}
        """
        let decoded = SwiftDataRunRecordRepository.decodeRunPayload(Data(json.utf8))
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.goal, .open)
    }
}
