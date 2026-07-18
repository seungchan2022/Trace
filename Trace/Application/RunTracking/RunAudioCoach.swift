import Foundation
import Observation

/// RunSession의 비뷰 소비자 — withObservationTracking으로 세션을 구독해 상태 전환·km 경계에서
/// 발화 문장을 조립해 VoiceAnnouncer에 넘긴다(스펙 §3.3). 세션 자체는 오디오를 모른다.
/// 구독·재등록 패턴은 RunActivityController와 동일.
@MainActor
final class RunAudioCoach {
    private let session: RunSession
    private let announcer: VoiceAnnouncerProtocol
    private var lastState: RunSession.State = .idle
    private var lastAnnouncedKm = 0
    private var goalHalfAnnounced = false
    private var goalAchievedAnnounced = false

    init(session: RunSession, announcer: VoiceAnnouncerProtocol) {
        self.session = session
        self.announcer = announcer
    }

    func startObserving() {
        observeOnce()
    }

    private func observeOnce() {
        withObservationTracking {
            _ = session.state
            _ = session.track.totalDistanceMeters
            _ = session.goalHalfReached
            _ = session.goalAchieved
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeOnce() // 관찰은 1회성이라 재등록
            }
        }
    }

    /// 관찰 콜백의 유일한 진입점 — 테스트가 직접 호출해 발화 결정을 검증한다.
    func sync() {
        announceStateTransitionIfNeeded()
        announceKilometerIfNeeded()
        announceGoalIfNeeded()
        lastState = session.state
    }

    private func announceStateTransitionIfNeeded() {
        let state = session.state
        guard state != lastState else { return }
        switch (lastState, state) {
        case (.idle, .acquiring):
            lastAnnouncedKm = 0 // 새 러닝 — km 카운터 리셋
            goalHalfAnnounced = false
            goalAchievedAnnounced = false
            announcer.announce(RunAnnouncementBuilder.start)
        case (.tracking, .paused):
            announcer.announce(RunAnnouncementBuilder.pause, pace: .brisk) // 유일하게 기존 속도 유지(2026-07-18)
        case (.paused, .tracking):
            announcer.announce(RunAnnouncementBuilder.resume, pace: .brisk) // 유일하게 기존 속도 유지(2026-07-18)
        case (_, .summary):
            let elapsed = session.summaryActiveElapsedSeconds ?? 0
            announcer.announce(RunAnnouncementBuilder.finish(
                distanceMeters: session.track.totalDistanceMeters,
                totalSeconds: elapsed,
                averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
            ))
        default:
            break // acquiring→tracking(첫 샘플), 취소/권한회수로 인한 →idle 등은 발화 없음
        }
    }

    private func announceKilometerIfNeeded() {
        guard session.state == .tracking else { return }
        let km = Int(session.track.totalDistanceMeters / RunSplitCalculator.splitDistanceMeters)
        guard km > lastAnnouncedKm else { return }
        // 한 번에 여러 경계를 지난 극단 케이스는 최신 경계만 읽는다(밀린 발화 연쇄 방지)
        lastAnnouncedKm = km
        let elapsed = session.activeElapsedSeconds() ?? 0
        announcer.announce(RunAnnouncementBuilder.kilometer(
            km: km,
            totalSeconds: elapsed,
            averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
        ))
    }

    private func announceGoalIfNeeded() {
        guard session.state == .tracking else { return }
        if session.goalAchieved, goalAchievedAnnounced == false {
            goalAchievedAnnounced = true
            // 한 sync에 절반·달성이 같이 걸린 극단 케이스는 달성만 읽는다(밀린 발화 연쇄 방지)
            goalHalfAnnounced = true
            let elapsed = session.activeElapsedSeconds() ?? 0
            announcer.announce(RunAnnouncementBuilder.goalAchieved(
                distanceMeters: session.track.totalDistanceMeters,
                totalSeconds: elapsed,
                averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
            ))
        } else if session.goalHalfReached, goalHalfAnnounced == false {
            goalHalfAnnounced = true
            announcer.announce(RunAnnouncementBuilder.goalHalf)
        }
    }

    /// 평균 페이스 = 활동 시간 / 거리 — 요약 화면(summaryAveragePaceSecondsPerKm)과 같은 기준(MVP14 §3.1)
    private func averagePace(elapsed: TimeInterval) -> Double? {
        let distance = session.track.totalDistanceMeters
        guard distance > 0, elapsed > 0 else { return nil }
        return elapsed / (distance / 1000)
    }
}
