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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ text: String, pace: AnnouncementPace) {
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
