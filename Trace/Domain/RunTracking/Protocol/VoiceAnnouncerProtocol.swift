import Foundation

/// 발화 속도 카테고리 — 상태 전환 등 짧은 문구는 기본(brisk), 숫자 정보가 담긴 문구는
/// 더 천천히(measured) 말해 알아듣기 쉽게 한다(실사용 QA 피드백 2026-07-18).
enum AnnouncementPace {
    case brisk
    case measured
}

/// 음성 안내 포트 — Domain은 AVFoundation을 모른다(스펙 §3.3).
/// 발화는 fire-and-forget: 호출자는 완료를 기다리지 않고, 직렬화(큐)는 구현체 책임이다.
@MainActor
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String, pace: AnnouncementPace)
    /// 발화 묶음(카운트다운 등) 동안 오디오 세션을 잡아 덕킹을 1회로 유지한다(스펙 §1.1)
    func holdAudioSession()
    /// hold 해제 — 남은 발화가 끝나는 시점(큐 소진)에 실제 비활성화된다
    func releaseAudioSession()
    /// 진행 중·대기 중 발화 즉시 중단(카운트다운 취소용)
    func stopSpeaking()
}

extension VoiceAnnouncerProtocol {
    /// pace 미지정 호출부 호환용 — 기본 속도로 말한다
    func announce(_ text: String) { announce(text, pace: .brisk) }
    func holdAudioSession() {}
    func releaseAudioSession() {}
    func stopSpeaking() {}
}
