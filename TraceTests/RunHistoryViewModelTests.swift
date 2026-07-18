import XCTest
@testable import Trace

@MainActor
final class RunHistoryViewModelTests: XCTestCase {
    private let repository = MockRunRecordRepository()
    private lazy var viewModel = RunHistoryViewModel(repository: repository)

    private func seedRun(startedAt: Date) async -> SavedRun {
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: startedAt, distanceMeters: 1000,
                duration: 600, elevationGainMeters: 3
            ),
            samples: [SavedRunSample(
                timestamp: startedAt, latitude: 37.5, longitude: 127.0,
                altitudeMeters: 10, speedMetersPerSecond: 3
            )]
        )
        do { try await repository.save(run) } catch { XCTFail("seed save failed") }
        return run
    }

    func test_load하면_요약이_최신순으로_실린다() async {
        let older = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        let newer = await seedRun(startedAt: Date(timeIntervalSince1970: 2000))
        await viewModel.load()
        XCTAssertEqual(viewModel.summaries.map(\.id), [newer.summary.id, older.summary.id])
    }

    func test_삭제는_확인후에만_실행되고_목록이_재동기화된다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        await viewModel.load()

        viewModel.requestDelete(run.summary)
        XCTAssertEqual(viewModel.pendingDelete?.id, run.summary.id)
        XCTAssertEqual(viewModel.summaries.count, 1) // 아직 안 지워짐

        await viewModel.confirmPendingDelete()
        XCTAssertNil(viewModel.pendingDelete)
        XCTAssertTrue(viewModel.summaries.isEmpty)
    }

    func test_삭제취소는_아무것도_지우지_않는다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        await viewModel.load()
        viewModel.requestDelete(run.summary)
        viewModel.cancelPendingDelete()
        XCTAssertNil(viewModel.pendingDelete)
        XCTAssertEqual(viewModel.summaries.count, 1)
    }

    func test_상세는_리포지토리에서_단건을_가져온다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        let fetched = await viewModel.loadRun(id: run.summary.id)
        XCTAssertEqual(fetched, run)
        let missing = await viewModel.loadRun(id: UUID())
        XCTAssertNil(missing) // 손상/미존재 → nil (상세가 우아한 강등 처리)
    }

    // MARK: - 포인트 개별 삭제 (스펙 §2.5)

    private func runWithWaypoints(_ waypoints: [RunWaypoint]) -> SavedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: start, distanceMeters: 2000,
                duration: 600, elevationGainMeters: 0
            ),
            samples: [
                SavedRunSample(timestamp: start, latitude: 37.5, longitude: 127.0,
                               altitudeMeters: 10, speedMetersPerSecond: 3)
            ],
            waypoints: waypoints
        )
    }

    func test_포인트를_삭제하면_갱신된_기록을_돌려준다() async throws {
        let waypoints = [
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        latitude: 37.505, longitude: 127.0, totalDistanceMeters: 870),
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_400),
                        latitude: 37.508, longitude: 127.0, totalDistanceMeters: 1500)
        ]
        let run = runWithWaypoints(waypoints)
        try await repository.save(run)

        let updated = await viewModel.deleteWaypoint(from: run, at: 0)

        XCTAssertEqual(updated?.waypoints, [waypoints[1]])
        XCTAssertFalse(viewModel.showsWaypointDeleteFailure)
    }

    func test_저장소_실패시_실패_플래그가_켜진다() async {
        // 저장된 적 없는 기록 → updateWaypoints가 throw
        let run = runWithWaypoints([
            RunWaypoint(timestamp: Date(), latitude: 37.5, longitude: 127.0, totalDistanceMeters: 500)
        ])
        let updated = await viewModel.deleteWaypoint(from: run, at: 0)
        XCTAssertNil(updated)
        XCTAssertTrue(viewModel.showsWaypointDeleteFailure)
    }

    func test_쓰기는_성공했지만_재조회가_nil이면_실패_플래그가_켜진다() async {
        // Finding 4: updateWaypoints는 성공했는데 바로 이어지는 fetchRun이 일시적으로 nil인 경우도
        // 조용히 넘어가지 않고 기존 실패 알럿으로 사용자에게 알려야 한다.
        let waypoints = [
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        latitude: 37.505, longitude: 127.0, totalDistanceMeters: 870)
        ]
        let run = runWithWaypoints(waypoints)
        try? await repository.save(run)
        await repository.failNextFetch()

        let updated = await viewModel.deleteWaypoint(from: run, at: 0)

        XCTAssertNil(updated)
        XCTAssertTrue(viewModel.showsWaypointDeleteFailure)
    }
}
