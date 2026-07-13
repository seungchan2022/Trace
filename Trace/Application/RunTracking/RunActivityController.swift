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
        observeOnce()
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
        case .tracking:
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
