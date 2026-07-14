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

    var isActive: Bool { state == .acquiring || state == .tracking }

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

    func finish() {
        guard isActive else { return }
        stopStream()
        endedAt = Date()
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
        #if DEBUG
        dumpEntries = []
        #endif
    }

    private func ingest(_ sample: RunSample, sessionStart: Date) {
        guard isActive else { return }
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
            endedAt = Date()
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
                // 벽시계 경과 시간 — 요약 화면이 보여주는 시간과 같은 기준(GPS 샘플 구간 아님)
                duration: endedAt.timeIntervalSince(startedAt),
                elevationGainMeters: track.elevationGainMeters
            ),
            samples: track.samples.map(SavedRunSample.init)
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
