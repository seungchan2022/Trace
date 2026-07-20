import Foundation
import Observation

/// 대기 화면 목표 선택 세그먼트의 3모드 — 조립 결과는 RunGoal(Domain)
enum RunGoalMode: String, CaseIterable, Identifiable {
    case open
    case distance
    case time

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "자유"
        case .distance: "거리"
        case .time: "시간"
        }
    }
}

/// 포인트 확인용 화면 카드(보조 채널 — 주 채널은 발화, 스펙 §2.2)
struct WaypointCard: Equatable {
    let index: Int
    let segmentMeters: Double
}

@MainActor
@Observable
final class RunPageViewModel {
    let session: RunSession
    private let announcer: VoiceAnnouncerProtocol
    private let defaults: UserDefaults
    private let sleeper: (Duration) async throws -> Void

    var showsAccuracyAlert = false
    var showsPermissionAlert = false
    /// 카운트다운 표시값(3→2→1). nil = 카운트다운 아님. 스펙 §1.1
    private(set) var countdown: Int?
    /// 취소 감지 플래그 — cancelCountdown()이 내리면 진행 중인 startTapped 루프가 중단된다
    private var countdownActive = false
    /// 요약 화면에 보여줄 활동 시간(일시정지 제외) — 트래킹 화면·Live Activity가 보여준 시간과 같은 기준(MVP14 §3.1).
    /// `RunTrack.duration`(GPS 샘플 구간)과는 다른 측정치라 별도로 종료 시점에 캡처해 둔다.
    private(set) var summaryElapsedSeconds: TimeInterval?
    /// 몇 초 표시 후 사라지는 포인트 확인 카드 — nil = 표시 안 함(스펙 §2.2)
    private(set) var waypointCard: WaypointCard?
    private var waypointCardDismissTask: Task<Void, Never>?

    static let lastDistanceKey = "run.goal.lastDistanceKm"
    static let lastTimeKey = "run.goal.lastTimeMinutes"

    // 목표 선택 상태(대기 화면) — 러닝 시작 시 composedGoal로 조립해 세션에 넘긴다
    var goalMode: RunGoalMode = .open
    var goalDistanceInput: String
    var goalTimeInput: String

    /// "5.5" 같은 자유 입력 텍스트를 km 값으로 파싱(스펙 §1.4) — 쉼표 소수점도 허용
    var parsedGoalDistanceKm: Double? {
        let normalized = goalDistanceInput.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// 분 입력은 정수만 허용 — "30.5" 같은 소수는 무효
    var parsedGoalTimeMinutes: Int? {
        guard let value = Int(goalTimeInput), value > 0 else { return nil }
        return value
    }

    /// 시작 버튼 활성 조건(스펙 §1.4) — 자유 모드는 입력이 없어도 항상 유효
    var isGoalInputValid: Bool {
        switch goalMode {
        case .open: true
        case .distance: parsedGoalDistanceKm != nil
        case .time: parsedGoalTimeMinutes != nil
        }
    }

    /// 비정상 입력 인라인 안내(스펙 §1.4) — 빈 입력은 플레이스홀더가 안내하므로 에러 아님
    var goalInputErrorText: String? {
        switch goalMode {
        case .open: nil
        case .distance:
            goalDistanceInput.isEmpty || parsedGoalDistanceKm != nil ? nil : "0보다 큰 숫자를 입력하세요"
        case .time:
            goalTimeInput.isEmpty || parsedGoalTimeMinutes != nil ? nil : "0보다 큰 정수(분)를 입력하세요"
        }
    }

    var composedGoal: RunGoal {
        switch goalMode {
        case .open: .open
        case .distance: parsedGoalDistanceKm.map { .distance(meters: $0 * 1000) } ?? .open
        case .time: parsedGoalTimeMinutes.map { .time(seconds: TimeInterval($0 * 60)) } ?? .open
        }
    }

    /// 트래킹 중 목표 진행률(1로 캡 — 달성 후 100% 고정 표시). 자유 러닝은 nil
    var goalProgressFraction: Double? {
        guard let fraction = session.goal.progressFraction(
            distanceMeters: session.track.totalDistanceMeters,
            activeSeconds: session.activeElapsedSeconds() ?? 0
        ) else { return nil }
        return min(1, fraction)
    }

    /// 트래킹 화면 평균 페이스 — 활동 시간(일시정지 제외) 기준.
    /// `RunTrack.averagePaceSecondsPerKm`은 GPS 샘플 구간(일시정지 포함) 기준이라
    /// 같은 러닝의 요약 화면·발화(RunAudioCoach.averagePace)와 값이 어긋난다(MVP14 §3.1).
    var liveAveragePaceSecondsPerKm: Double? {
        let distanceMeters = session.track.totalDistanceMeters
        guard distanceMeters > 0,
              let elapsed = session.activeElapsedSeconds(), elapsed > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    /// 요약 화면에 보여줄 평균 페이스 — 활동 시간(`summaryElapsedSeconds`) 기준.
    /// `RunTrack.averagePaceSecondsPerKm`(GPS 샘플 구간, 일시정지 포함)을 쓰면 같은 화면의 시간 필드·
    /// 저장된 기록의 페이스(`SavedRunSummary.averagePaceSecondsPerKm`)와 값이 어긋난다(MVP14 §3.1, 최종 브랜치 리뷰).
    var summaryAveragePaceSecondsPerKm: Double? {
        guard let elapsed = summaryElapsedSeconds, elapsed > 0 else { return nil }
        let distanceMeters = session.track.totalDistanceMeters
        guard distanceMeters > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    init(
        session: RunSession,
        announcer: VoiceAnnouncerProtocol,
        defaults: UserDefaults = .standard,
        sleeper: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.announcer = announcer
        self.defaults = defaults
        self.sleeper = sleeper
        // 직전 사용 목표값 프리필(스펙 §1.4) — 저장값이 없으면 빈 문자열(플레이스홀더 노출)
        goalDistanceInput = (defaults.object(forKey: Self.lastDistanceKey) as? Double)
            .map(Self.formatKm) ?? ""
        goalTimeInput = (defaults.object(forKey: Self.lastTimeKey) as? Int)
            .map(String.init) ?? ""
    }

    func startTapped() async {
        guard countdown == nil else { return }
        guard isGoalInputValid else { return }
        // prepareStart의 정확도 게이트(await) 동안 오디오 세션을 미리 잡아둔다 — 정확도 확인
        // 직후 첫 숫자를 바로 말하면 오디오 엔진이 덜 데워진 채로 시작해 "삼"이 뭉개져 들린다는
        // 실사용 QA 피드백(2026-07-18). 실패 시에도 잡은 세션은 반드시 해제한다.
        announcer.holdAudioSession() // 덕킹 1회: 카운트다운~시작 발화까지 유지(스펙 §1.1)
        guard await session.prepareStart(goal: composedGoal) else {
            announcer.releaseAudioSession()
            presentStartFailure()
            return
        }
        persistGoalInputs()
        countdownActive = true
        for (index, word) in RunAnnouncementBuilder.countdown.enumerated() {
            guard countdownActive else { return } // 취소됨 — cancelCountdown()이 정리 완료
            countdown = RunAnnouncementBuilder.countdown.count - index
            announcer.announce(word)
            do { try await sleeper(.seconds(1)) } catch { return }
        }
        guard countdownActive else { return }
        countdownActive = false
        countdown = nil
        session.beginTracking()
        // 시작 발화(RunAudioCoach, idle→acquiring)가 큐에 남아 있는 동안 release —
        // 어댑터는 큐 소진 시점에 비활성화하므로 덕킹 플랩이 없다(스펙 §1.1)
        announcer.releaseAudioSession()
        guard session.lastStartFailure == nil else {
            presentStartFailure()
            return
        }
        summaryElapsedSeconds = nil
    }

    /// 카운트다운 중 화면 탭 → 취소(스펙 §1.1). 백그라운드 진입은 취소가 아니다 — 계속 진행.
    func cancelCountdown() {
        guard countdownActive else { return }
        countdownActive = false
        countdown = nil
        announcer.stopSpeaking()
        announcer.releaseAudioSession()
        session.cancelPreparation()
    }

    /// 포인트 버튼 탭 — 마킹은 세션, 발화는 RunAudioCoach(관찰), 여기는 화면 카드만 담당
    func markWaypointTapped() {
        guard session.markWaypoint() != nil else { return }
        guard let segmentMeters = session.waypoints.lastSegmentMeters else { return }
        waypointCard = WaypointCard(index: session.waypoints.count, segmentMeters: segmentMeters)
        waypointCardDismissTask?.cancel()
        waypointCardDismissTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleeper(.seconds(3)) } catch { return } // 취소 = 새 카드가 대체
            waypointCard = nil
        }
    }

    private func presentStartFailure() {
        switch session.lastStartFailure {
        case .reducedAccuracy: showsAccuracyAlert = true
        case .permissionDenied: showsPermissionAlert = true
        case nil: break
        }
    }

    func endRun() {
        waypointCardDismissTask?.cancel()
        waypointCard = nil
        summaryElapsedSeconds = session.activeElapsedSeconds()
        session.finish()
    }

    func closeSummary() {
        session.dismissSummary()
    }

    func cancelAcquiring() {
        session.finishAcquiringCancelled()
    }

    /// 이번에 사용한 목표값을 다음 시작 화면 프리필용으로 저장(스펙 §1.4)
    private func persistGoalInputs() {
        if let km = parsedGoalDistanceKm { defaults.set(km, forKey: Self.lastDistanceKey) }
        if let minutes = parsedGoalTimeMinutes { defaults.set(minutes, forKey: Self.lastTimeKey) }
    }

    /// 7.0 → "7", 7.5 → "7.5" — 입력 필드 프리필 표기
    private static func formatKm(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
