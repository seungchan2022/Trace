import Foundation

/// 음성 안내 포트 — Domain은 AVFoundation을 모른다(스펙 §3.3).
/// 발화는 fire-and-forget: 호출자는 완료를 기다리지 않고, 직렬화(큐)는 구현체 책임이다.
@MainActor
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String)
}
