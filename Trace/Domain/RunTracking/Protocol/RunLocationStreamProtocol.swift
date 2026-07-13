import Foundation

enum RunLocationAccuracy: Sendable {
    case full
    case reduced
}

/// 연속 위치 스트림 포트 — Domain은 CoreLocation을 모른다.
/// 스트림 종료(finish)는 "더 이상 위치를 받을 수 없음"(권한 회수·서비스 오프)을 뜻한다.
@MainActor
protocol RunLocationStreamProtocol {
    func currentAccuracy() -> RunLocationAccuracy
    /// "정확한 위치" 꺼짐 상태에서 세션 한정 임시 정밀 권한을 요청한다(스펙 §6).
    func requestSessionFullAccuracy() async -> RunLocationAccuracy
    func startUpdates() -> AsyncStream<RunSample>
    func stopUpdates()
}
