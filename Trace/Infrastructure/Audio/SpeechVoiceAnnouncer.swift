@preconcurrency import AVFoundation

/// VoiceAnnouncer의 AVSpeechSynthesizer 어댑터.
/// 오디오 세션은 발화 묶음 동안만 활성화(.playback + .duckOthers)하고, 큐가 소진되는 시점에만
/// .notifyOthersOnDeactivation으로 비활성화해 음악 볼륨을 복원한다 — 연속 발화(km 경계+상태 전환
/// 동시)에서 볼륨이 복원됐다 다시 내려가는 플랩을 막는다(스펙 §3.3).
/// 세션 활성화 실패(통화 중 등) 시 그 발화는 건너뛴다(재시도 없음 — 플랜 결정, project-decisions.md).
@MainActor
final class SpeechVoiceAnnouncer: NSObject, VoiceAnnouncerProtocol {
    /// 실기기 QA에서 튜닝해 확정한다(스펙 §1.3) — 시스템 기본 0.5가 빠르다는 실사용 피드백으로 하향
    private static let speechRate: Float = 0.45
    /// 숫자 정보가 담긴 문구(km 안내·목표 달성) 전용 — 알아듣기 어렵다는 실사용 QA 피드백으로 추가 하향(2026-07-18)
    private static let measuredSpeechRate: Float = 0.40

    private let synthesizer = AVSpeechSynthesizer()
    /// 큐에 남아 있는 발화 수 — 0이 되는 시점(큐 소진)에만 세션을 비활성화한다
    private var pendingCount = 0
    /// holdAudioSession으로 세션을 보유 중인지 — 보유 중엔 발화별 활성화/비활성화를 건너뛴다
    private var isHeld = false
    /// 대기열에 있는 발화들의 종류(FIFO) — 첫 원소가 현재 재생 중인 발화의 종류다.
    /// 포인트 발화 즉시성(스펙 §2.2) 판정에 쓴다.
    private var queuedKinds: [AnnouncementKind] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        primeEngine()
    }

    /// AVSpeechSynthesizer/음성 로딩은 프로세스 최초 발화에서만 지연이 커서(플랫폼 특성),
    /// 첫 러닝 시작 시 카운트다운 "삼"이 늦게 나와 세 단어가 뭉쳐 들린다는 실사용 QA
    /// 피드백(2026-07-19)으로 앱 시작 시 1회 미리 예열한다. .duckOthers가 아닌
    /// .mixWithOthers로 진행해 사용자가 듣고 있던 음악을 건드리지 않는다(실제 카운트다운은
    /// holdAudioSession이 별도로 .duckOthers 세션을 연다) — 볼륨도 거의 0으로 낮춘다.
    private func primeEngine() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            return // 세션 준비 실패 — 예열 없이 진행(첫 카운트다운에만 영향, 재시도 없음)
        }
        let utterance = AVSpeechUtterance(string: "예열")
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.volume = 0.01
        synthesizer.speak(utterance)
    }

    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {
        // 포인트 발화 즉시성(스펙 §2.2): 데이터 낭독(km·목표)이 유일하게 대기 중이면 중단하고
        // 바로 말한다. stopSpeaking은 큐 전체를 비우므로, 뒤에 다른 발화(km+목표 동시 등)가
        // 이미 붙어 있으면 건너뛰고 정상 큐잉한다 — 그렇지 않으면 didCancel이 하나만 정리해
        // pendingCount가 영영 0으로 안 돌아가는 세션 디싱크가 생긴다.
        if kind == .waypoint, queuedKinds == [.data] {
            synthesizer.stopSpeaking(at: .immediate) // didCancel 델리게이트가 카운트를 정리한다
        }
        if pendingCount == 0 && isHeld == false {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try audioSession.setActive(true)
            } catch {
                return // 활성화 실패(통화 중 등) — 이번 발화는 건너뛴다
            }
        }
        pendingCount += 1
        queuedKinds.append(kind)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = pace == .measured ? Self.measuredSpeechRate : Self.speechRate
        synthesizer.speak(utterance)
    }

    func holdAudioSession() {
        guard isHeld == false else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            isHeld = true
        } catch {
            // 활성화 실패 — 보유 없이 진행하면 announce가 발화별 활성화로 폴백한다
        }
    }

    func releaseAudioSession() {
        guard isHeld else { return }
        isHeld = false
        guard pendingCount == 0 else { return } // 남은 발화의 utteranceEnded가 비활성화를 맡는다
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate) // didCancel 델리게이트가 pendingCount를 정리한다
    }

    private func utteranceEnded() {
        pendingCount = max(0, pendingCount - 1)
        if queuedKinds.isEmpty == false { queuedKinds.removeFirst() }
        guard pendingCount == 0, isHeld == false else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SpeechVoiceAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
