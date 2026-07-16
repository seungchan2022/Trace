@preconcurrency import AVFoundation

/// VoiceAnnouncer의 AVSpeechSynthesizer 어댑터.
/// 오디오 세션은 발화 묶음 동안만 활성화(.playback + .duckOthers)하고, 큐가 소진되는 시점에만
/// .notifyOthersOnDeactivation으로 비활성화해 음악 볼륨을 복원한다 — 연속 발화(km 경계+상태 전환
/// 동시)에서 볼륨이 복원됐다 다시 내려가는 플랩을 막는다(스펙 §3.3).
/// 세션 활성화 실패(통화 중 등) 시 그 발화는 건너뛴다(재시도 없음 — 플랜 결정, project-decisions.md).
@MainActor
final class SpeechVoiceAnnouncer: NSObject, VoiceAnnouncerProtocol {
    private let synthesizer = AVSpeechSynthesizer()
    /// 큐에 남아 있는 발화 수 — 0이 되는 시점(큐 소진)에만 세션을 비활성화한다
    private var pendingCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ text: String) {
        if pendingCount == 0 {
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
        synthesizer.speak(utterance)
    }

    private func utteranceEnded() {
        pendingCount = max(0, pendingCount - 1)
        guard pendingCount == 0 else { return }
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
