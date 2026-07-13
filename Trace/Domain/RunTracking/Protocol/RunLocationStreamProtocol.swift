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
    /// 반드시 스트림의 continuation을 finish 처리해 소비자의 `for await` 루프가 종료되게 해야 한다 —
    /// 소비 Task를 cancel하는 것만으로는 AsyncStream 반복이 멈추지 않는다.
    func stopUpdates()
}
