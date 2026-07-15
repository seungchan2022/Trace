@preconcurrency import ActivityKit
import Foundation
import Observation

/// RunSession의 비뷰 소비자 — withObservationTracking으로 세션을 구독해
/// Live Activity 생성·갱신·제거를 전담한다(스펙 §5).
@MainActor
final class RunActivityController {
    private let session: RunSession
    private var activity: Activity<RunActivityAttributes>?

    init(session: RunSession) {
        self.session = session
    }

    func startObserving() {
        endOrphanedActivities()
        observeOnce()
    }

    /// 강제 종료 후 재실행 시 세션은 항상 .idle로 새로 시작하고 이전 세션을 복구하지 않으므로
    /// (스펙 범위 밖), 실행 시점에 남아 있는 Activity는 예외 없이 고아다 — 즉시 정리한다(중요 리뷰 항목).
    private func endOrphanedActivities() {
        for activity in Activity<RunActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func observeOnce() {
        withObservationTracking {
            _ = session.state
            _ = session.track.totalDistanceMeters
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeOnce() // 관찰은 1회성이라 재등록
            }
        }
    }

    private func sync() {
        switch session.state {
        case .tracking, .paused:
            // paused는 Task 2가 도입한 컴파일 shim — 실제 일시정지 표시(타이머 정지 등)는 Task 6이 담당한다.
            if activity == nil {
                startActivity()
            } else {
                updateActivity()
            }
        case .idle, .acquiring, .summary:
            endActivityIfNeeded()
        }
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return } // 꺼져 있으면 조용히 무시(스펙 §6)
        guard let startedAt = session.startedAt else { return }
        let attributes = RunActivityAttributes(startedAt: startedAt)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: currentState(), staleDate: nil)
        )
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = currentState()
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivityIfNeeded() {
        guard let activity else { return }
        self.activity = nil
        let finalState = currentState()
        Task {
            // 요약은 앱 화면이 담당 — 잠금화면 잔류 없이 즉시 제거(스펙 §5)
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private func currentState() -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            distanceMeters: session.track.totalDistanceMeters,
            paceSecondsPerKm: session.track.currentPaceSecondsPerKm
        )
    }
}
