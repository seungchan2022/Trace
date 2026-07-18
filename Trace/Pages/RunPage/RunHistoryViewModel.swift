import Foundation
import Observation

/// 기록 목록/상세 상태 — 목록은 요약(컬럼)만, 상세 진입 시에만 단건 blob을 읽는다(스펙 §2·§4)
@MainActor
@Observable
final class RunHistoryViewModel {
    private let repository: RunRecordRepositoryProtocol

    private(set) var summaries: [SavedRunSummary] = []
    private(set) var pendingDelete: SavedRunSummary?
    var showsDeleteFailure = false
    var showsWaypointDeleteFailure = false

    init(repository: RunRecordRepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        summaries = await repository.fetchSummaries()
    }

    func loadRun(id: UUID) async -> SavedRun? {
        await repository.fetchRun(id: id)
    }

    func requestDelete(_ summary: SavedRunSummary) {
        pendingDelete = summary
    }

    func cancelPendingDelete() {
        pendingDelete = nil
    }

    func confirmPendingDelete() async {
        guard let pendingDelete else { return }
        self.pendingDelete = nil
        do {
            try await repository.deleteRun(id: pendingDelete.id)
        } catch {
            showsDeleteFailure = true
        }
        // 성공·실패 모두 실제 스토어와 재동기화(스펙 §6)
        await load()
    }

    /// 포인트 개별 삭제(스펙 §2.5) — 성공 시 스토어에서 다시 읽은 기록을 돌려준다(재계산은 뷰가
    /// RunWaypointSegmentsCalculator로 수행). 실패 시 nil + 알럿 플래그
    func deleteWaypoint(from run: SavedRun, at index: Int) async -> SavedRun? {
        var waypoints = run.waypoints
        guard waypoints.indices.contains(index) else { return nil }
        waypoints.remove(at: index)
        do {
            try await repository.updateWaypoints(runID: run.summary.id, waypoints: waypoints)
        } catch {
            showsWaypointDeleteFailure = true
            return nil
        }
        return await repository.fetchRun(id: run.summary.id)
    }
}
