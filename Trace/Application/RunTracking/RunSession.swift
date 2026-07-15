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

    var isActive: Bool { state == .acquiring || state == .tracking || state == .paused }
    var isPaused: Bool { state == .paused }

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

    private let locationStream: RunLocationStreamProtocol
    private let recordRepository: RunRecordRepositoryProtocol
    private var streamTask: Task<Void, Never>?

    init(locationStream: RunLocationStreamProtocol, recordRepository: RunRecordRepositoryProtocol) {
        self.locationStream = locationStream
        self.recordRepository = recordRepository
    }

    func start() async {
        guard state == .idle else { return }
        lastStartFailure = nil

        var accuracy = locationStream.currentAccuracy()
        if accuracy == .reduced {
            accuracy = await locationStream.requestSessionFullAccuracy()
        }
        guard accuracy == .full else {
            lastStartFailure = .reducedAccuracy
            return
        }

        let sessionStart = Date()
        startedAt = sessionStart
        track = RunTrack()
        #if DEBUG
        dumpEntries = []
        #endif
        state = .acquiring

        let stream = locationStream.startUpdates()
        streamTask = Task { [weak self] in
            for await sample in stream {
                self?.ingest(sample, sessionStart: sessionStart)
            }
            self?.streamEnded()
        }
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
            pauses: completedPauses
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
