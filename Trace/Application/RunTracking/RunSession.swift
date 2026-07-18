import Foundation
import Observation

#if DEBUG
/// QA 러닝의 원시 데이터(필터 판정 포함)를 남기기 위한 DEBUG 전용 기록(스펙 §1 덤프).
struct RunSampleDumpEntry: Equatable, Sendable, Codable {
    let sample: RunSample
    let accepted: Bool
}
#endif

/// 러닝 세션 오케스트레이터 — DependencyContainer가 소유해 탭 전환·뷰 소멸에도 유지된다.
/// 화면·잠금화면·(미래)오디오 안내는 전부 이 세션의 소비자다(스펙 §4).
@MainActor
@Observable
final class RunSession {
    enum State: Equatable {
        case idle
        case acquiring
        case tracking
        case paused
        case summary
    }

    enum StartFailure: Equatable {
        case reducedAccuracy
        case permissionDenied
    }

    enum SaveStatus: Equatable {
        case saving
        case saved
        case failed
    }

    static let maxHorizontalAccuracyMeters: Double = 30
    static let weakSignalTimeoutSeconds: TimeInterval = 10

    private(set) var state: State = .idle
    private(set) var track = RunTrack()
    private(set) var startedAt: Date?
    private(set) var isSignalWeak = false
    private(set) var lastStartFailure: StartFailure?
    #if DEBUG
    private(set) var dumpEntries: [RunSampleDumpEntry] = []
    #endif
    private(set) var saveStatus: SaveStatus?
    /// 저장(또는 재시도) 대상 기록 — 재시도가 같은 id로 저장되게 값을 보관한다
    private var pendingRun: SavedRun?
    private var endedAt: Date?
    /// 닫힌 일시정지 구간들 — 저장 payload에 그대로 들어간다(스펙 §4)
    private(set) var completedPauses: [RunPauseInterval] = []
    /// 열린 일시정지의 시작 시각 — paused 상태에서만 non-nil
    private var pausedAt: Date?
    /// 이번 러닝의 목표 — start(goal:)에서 정해지고 요약을 닫을 때 리셋된다(스펙 §3.4)
    private(set) var goal: RunGoal = .open
    /// 절반/달성 플래그 — 한 번 true면 러닝 끝까지 유지(각 1회 발화는 소비자가 전이로 감지)
    private(set) var goalHalfReached = false
    private(set) var goalAchieved = false
    /// 이번 러닝에서 찍은 포인트들(스펙 §2) — 저장 payload에 그대로 들어간다
    private(set) var waypoints: [RunWaypoint] = []

    var isActive: Bool { state == .acquiring || state == .tracking || state == .paused }
    var isPaused: Bool { state == .paused }

    /// 포인트 버튼 활성 조건(스펙 §2.2): 일시정지 아님 + 첫 유효 샘플 확보됨 = tracking 상태.
    /// (acquiring은 유효 샘플 이전, paused는 거리가 안 쌓이는 상태 — 둘 다 비활성)
    var canMarkWaypoint: Bool { state == .tracking }

    /// 포인트 찍기 — 좌표는 마지막 유효 샘플, 거리는 총거리 적산 스냅샷(스펙 §2.2·§2.4).
    /// tracking 상태는 유효 샘플 ≥ 1을 보장하므로 좌표는 항상 존재한다.
    /// 연타 방지 임계값 없음 — 0m 구간도 허용(스펙 §2.2).
    @discardableResult
    func markWaypoint(now: Date = Date()) -> RunWaypoint? {
        guard canMarkWaypoint, let lastSample = track.samples.last else { return nil }
        let waypoint = RunWaypoint(
            timestamp: now,
            latitude: lastSample.latitude,
            longitude: lastSample.longitude,
            totalDistanceMeters: track.totalDistanceMeters
        )
        waypoints.append(waypoint)
        return waypoint
    }

    /// 닫힌 구간 합 + (일시정지 중이면) 열린 구간까지 — "지금까지 멈춘 총 시간"
    func totalPausedSeconds(now: Date = Date()) -> TimeInterval {
        let completed = completedPauses.reduce(0) { $0 + $1.duration }
        let open = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return completed + open
    }

    /// 활동 시간 = 벽시계 경과 − 일시정지 합. 시간·페이스·기록의 새 기준(스펙 §3.1).
    func activeElapsedSeconds(now: Date = Date()) -> TimeInterval? {
        guard let startedAt else { return nil }
        return now.timeIntervalSince(startedAt) - totalPausedSeconds(now: now)
    }

    /// 타이머 UI용 보정 시작 시각 — 여기서부터 지금까지가 곧 활동 시간이 되도록 민 값.
    /// 트래킹 중에는 열린 구간이 없어 고정값이다(Text(timerInterval:)의 기준으로 안전).
    var displayTimerStart: Date? {
        guard let startedAt else { return nil }
        return startedAt.addingTimeInterval(totalPausedSeconds())
    }

    /// 종료 시각 기준으로 고정된 최종 활동 시간 — summary 상태에서만 non-nil.
    /// activeElapsedSeconds()는 now 기준이라 종료 후에도 계속 자란다 — 종료 발화·요약용은 이 값.
    var summaryActiveElapsedSeconds: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt) - totalPausedSeconds(now: endedAt)
    }

    private let locationStream: RunLocationStreamProtocol
    private let recordRepository: RunRecordRepositoryProtocol
    private var streamTask: Task<Void, Never>?
    /// 예열 단계 여부 — prepareStart~beginTracking 사이(카운트다운 중)에만 true
    private var isPreparing = false

    init(locationStream: RunLocationStreamProtocol, recordRepository: RunRecordRepositoryProtocol) {
        self.locationStream = locationStream
        self.recordRepository = recordRepository
    }

    /// 카운트다운 전 단계(스펙 §1.1): 정확도 게이트(시스템 프롬프트 포함)와 GPS 예열만 수행한다.
    /// 상태는 idle 유지·startedAt 미설정 — 스트림 태스크의 startedAt 가드가 예열 샘플을 버린다.
    func prepareStart(goal: RunGoal = .open) async -> Bool {
        guard state == .idle, isPreparing == false else { return false }
        isPreparing = true // 아래 정확도 재요청 await 지점 전에 닫아야 재진입 창이 안 생긴다
        lastStartFailure = nil

        var accuracy = locationStream.currentAccuracy()
        if accuracy == .reduced {
            accuracy = await locationStream.requestSessionFullAccuracy()
        }
        guard accuracy == .full else {
            lastStartFailure = .reducedAccuracy
            isPreparing = false // 재시도를 막지 않도록 원복
            return false
        }

        track = RunTrack()
        startedAt = nil
        #if DEBUG
        dumpEntries = []
        #endif
        self.goal = goal
        goalHalfReached = false
        goalAchieved = false
        waypoints = []

        let stream = locationStream.startUpdates()
        streamTask = Task { [weak self] in
            for await sample in stream {
                guard let self, let sessionStart = self.startedAt else { continue } // 예열 샘플 폐기
                self.ingest(sample, sessionStart: sessionStart)
            }
            // stopStream()이 취소한 뒤 finish()를 호출한 경우(의도적 종료·재시작)는 이 태스크가
            // 뒤늦게 깨어나 streamEnded()를 부르면 그 사이 새로 시작된 세션을 오염시킨다 — 취소된
            // 경우는 건너뛴다. 취소 없이 스트림이 스스로 끝난 경우(권한 회수 등)만 실제로 처리한다.
            guard Task.isCancelled == false else { return }
            self?.streamEnded()
        }
        return true
    }

    /// 카운트다운 종료 시점 — 여기부터가 세션 시작(활동 시간·거리 적산 기준, 스펙 §1.1)
    func beginTracking(now: Date = Date()) {
        guard isPreparing, state == .idle else { return }
        isPreparing = false
        guard lastStartFailure == nil else { stopStream(); return } // 예열 중 스트림 사망(권한 회수)
        startedAt = now
        state = .acquiring
    }

    /// 카운트다운 취소 — 예열 스트림을 내리고 대기 상태로 되돌린다
    func cancelPreparation() {
        guard isPreparing else { return }
        isPreparing = false
        stopStream()
        startedAt = nil
        goal = .open
        goalHalfReached = false
        goalAchieved = false
    }

    func start(goal: RunGoal = .open) async {
        guard await prepareStart(goal: goal) else { return }
        beginTracking()
    }

    func pause(now: Date = Date()) {
        guard state == .tracking else { return }
        pausedAt = now
        state = .paused
    }

    func resume(now: Date = Date()) {
        guard state == .paused, let pausedAt else { return }
        completedPauses.append(RunPauseInterval(start: pausedAt, end: now))
        self.pausedAt = nil
        track.markGap()
        state = .tracking
    }

    private func closeOpenPause(at date: Date) {
        guard let pausedAt else { return }
        completedPauses.append(RunPauseInterval(start: pausedAt, end: date))
        self.pausedAt = nil
    }

    func finish() {
        guard isActive else { return }
        stopStream()
        let end = Date()
        closeOpenPause(at: end)
        endedAt = end
        state = .summary
        startRecordSave()
    }

    /// 신호 확보 중 사용자가 취소한 경우 — 아직 유효 샘플이 없으므로 요약 없이 바로 대기로 복귀한다.
    func finishAcquiringCancelled() {
        guard state == .acquiring else { return }
        stopStream()
        state = .idle
        track = RunTrack()
        startedAt = nil
        completedPauses = []
        pausedAt = nil
        goal = .open
        goalHalfReached = false
        goalAchieved = false
        waypoints = []
        #if DEBUG
        dumpEntries = []
        #endif
    }

    func dismissSummary() {
        guard state == .summary else { return }
        state = .idle
        track = RunTrack()
        startedAt = nil
        endedAt = nil
        saveStatus = nil
        pendingRun = nil
        completedPauses = []
        pausedAt = nil
        goal = .open
        goalHalfReached = false
        goalAchieved = false
        waypoints = []
        #if DEBUG
        dumpEntries = []
        #endif
    }

    private func ingest(_ sample: RunSample, sessionStart: Date) {
        guard isActive else { return }
        // 일시정지 중 샘플은 통째로 무시 — 적산·덤프·약신호 갱신 없음(스펙 §3.1 전이표)
        guard state != .paused else { return }
        // 시작 직후 도착하는 캐시된 옛 샘플은 버린다(스펙 §4 필터링)
        guard sample.timestamp >= sessionStart else { return }

        let accepted = sample.horizontalAccuracyMeters > 0
            && sample.horizontalAccuracyMeters <= Self.maxHorizontalAccuracyMeters
        #if DEBUG
        dumpEntries.append(RunSampleDumpEntry(sample: sample, accepted: accepted))
        #endif
        guard accepted else {
            updateWeakSignal(now: sample.timestamp)
            return
        }

        track.append(sample)
        isSignalWeak = false
        if state == .acquiring { state = .tracking }
        updateGoalProgress(now: sample.timestamp)
    }

    /// 샘플 도착 시점 판정 — 시간 목표도 샘플 타임스탬프 기준(별도 타이머 없음, 지연 ≤ 샘플 간격)
    private func updateGoalProgress(now: Date) {
        guard goal != .open, goalAchieved == false else { return }
        guard let fraction = goal.progressFraction(
            distanceMeters: track.totalDistanceMeters,
            activeSeconds: activeElapsedSeconds(now: now) ?? 0
        ) else { return }
        if fraction >= 1 { goalAchieved = true }
        if fraction >= 0.5 { goalHalfReached = true }
    }

    private func updateWeakSignal(now: Date) {
        guard let lastAccepted = track.samples.last else {
            // 아직 유효 샘플이 하나도 없는 신호 확보 단계 — 탈락이 이어지면 약신호 표시
            isSignalWeak = true
            return
        }
        if now.timeIntervalSince(lastAccepted.timestamp) >= Self.weakSignalTimeoutSeconds {
            isSignalWeak = true
        }
    }

    /// 스트림이 밖에서 끊긴 경우(러닝 도중 권한 회수 등) — 수집분을 버리지 않는다(스펙 §6)
    private func streamEnded() {
        if isPreparing { // 예열 중 스트림 사망(권한 회수 등) — beginTracking이 시작을 거부하게 표시
            isPreparing = false
            locationStream.stopUpdates()
            lastStartFailure = .permissionDenied
            return
        }
        guard isActive else { return }
        stopStream()
        if track.samples.isEmpty {
            state = .idle
            startedAt = nil
            lastStartFailure = .permissionDenied
        } else {
            let end = Date()
            closeOpenPause(at: end)
            endedAt = end
            state = .summary
            startRecordSave()
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        locationStream.stopUpdates()
        isSignalWeak = false
    }

    // MARK: - 자동 저장 (스펙 §3)

    private func startRecordSave() {
        guard let startedAt, let endedAt, track.samples.isEmpty == false else { return }
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(),
                startedAt: startedAt,
                distanceMeters: track.totalDistanceMeters,
                // 활동 시간(벽시계 − 일시정지 합) — 트래킹 화면·요약이 보여주는 시간과 같은 기준(MVP14 §3.1)
                duration: endedAt.timeIntervalSince(startedAt) - totalPausedSeconds(now: endedAt),
                elevationGainMeters: track.elevationGainMeters
            ),
            samples: track.samples.map(SavedRunSample.init),
            pauses: completedPauses,
            goal: goal
        )
        pendingRun = run
        performSave(run)
    }

    /// 저장 실패 후 재시도 — 같은 pendingRun(같은 id)을 다시 저장하므로 중복 기록이 생기지 않는다
    func retrySave() {
        guard saveStatus == .failed, let pendingRun else { return }
        performSave(pendingRun)
    }

    private func performSave(_ run: SavedRun) {
        saveStatus = .saving
        Task { [weak self, recordRepository] in
            do {
                try await recordRepository.save(run)
                self?.markSaveFinished(for: run, status: .saved)
            } catch {
                self?.markSaveFinished(for: run, status: .failed)
            }
        }
    }

    /// 요약을 닫은 뒤(또는 다음 세션에서) 완료된 이전 저장이 상태를 오염시키지 않게 id로 가드한다
    private func markSaveFinished(for run: SavedRun, status: SaveStatus) {
        guard pendingRun?.summary.id == run.summary.id else { return }
        saveStatus = status
    }
}
