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
}
