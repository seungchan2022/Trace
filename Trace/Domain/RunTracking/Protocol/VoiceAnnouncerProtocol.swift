import Foundation

/// 발화 속도 카테고리 — 일시정지/재개만 기존 속도(brisk)를 유지하고, 나머지 전부(시작·종료·
/// km 안내·목표 절반/달성·카운트다운)는 느리게(measured) 말해 알아듣기 쉽게 한다
/// (실사용 QA 피드백 2026-07-18 1차: km·목표달성만 느리게 / 2차: 일시정지·재개 제외 전부 느리게).
enum AnnouncementPace {
    case brisk
    case measured
}

/// 발화 종류 — 포인트 발화 즉시성 규칙 판정용(스펙 §2.2): 포인트는 데이터 낭독(km·목표)이
/// 재생 중이면 중단시키고 바로 재생하되, 상태 전환 발화(시작·일시정지 등)보다는 후순위(대기)다.
enum AnnouncementKind {
    case status
    case data
    case waypoint
}

/// 음성 안내 포트 — Domain은 AVFoundation을 모른다(스펙 §3.3).
/// 발화는 fire-and-forget: 호출자는 완료를 기다리지 않고, 직렬화(큐)는 구현체 책임이다.
@MainActor
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind)
    /// 발화 묶음(카운트다운 등) 동안 오디오 세션을 잡아 덕킹을 1회로 유지한다(스펙 §1.1)
    func holdAudioSession()
    /// hold 해제 — 남은 발화가 끝나는 시점(큐 소진)에 실제 비활성화된다
    func releaseAudioSession()
    /// 진행 중·대기 중 발화 즉시 중단(카운트다운 취소용)
    func stopSpeaking()
}

extension VoiceAnnouncerProtocol {
    /// pace·kind 미지정 호출부 호환용 — 기본값은 measured(느린 속도) + status(상태 전환)
    func announce(_ text: String) { announce(text, pace: .measured, kind: .status) }
    func announce(_ text: String, pace: AnnouncementPace) { announce(text, pace: pace, kind: .status) }
    func holdAudioSession() {}
    func releaseAudioSession() {}
    func stopSpeaking() {}
}
