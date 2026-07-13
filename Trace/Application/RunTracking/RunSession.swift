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

    var isActive: Bool { state == .acquiring || state == .tracking }

    private let locationStream: RunLocationStreamProtocol
    private var streamTask: Task<Void, Never>?

    init(locationStream: RunLocationStreamProtocol) {
        self.locationStream = locationStream
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
        state = .summary
    }

    func dismissSummary() {
        guard state == .summary else { return }
        state = .idle
        track = RunTrack()
        startedAt = nil
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
            state = .summary
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        locationStream.stopUpdates()
        isSignalWeak = false
    }
}
