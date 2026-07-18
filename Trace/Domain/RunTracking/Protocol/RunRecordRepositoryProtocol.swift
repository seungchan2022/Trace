import Foundation

// 러닝 기록 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다.
// 목록(fetchSummaries)과 상세(fetchRun)를 분리해 목록 경로가 blob을 디코드하지 않게 한다(스펙 §2·§5).
protocol RunRecordRepositoryProtocol: Sendable {
    func save(_ run: SavedRun) async throws
    /// 최신순(startedAt 내림차순). 컬럼만 읽는다 — blob 미디코드
    func fetchSummaries() async -> [SavedRunSummary]
    /// 단건 blob 디코드. 해독 실패(손상·미래 버전)·미존재 시 nil (스펙 §6 우아한 강등)
    func fetchRun(id: UUID) async -> SavedRun?
    func deleteRun(id: UUID) async throws
    /// 포인트 개별 삭제 반영(MVP15 §2.5) — 해당 기록의 포인트 스트림만 교체해 재저장한다.
    /// 캐시 컬럼(거리·시간·고도)은 포인트와 무관하므로 불변. 기록 미존재·해독 실패 시 throw
    func updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws
}
