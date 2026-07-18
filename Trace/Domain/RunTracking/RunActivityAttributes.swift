import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
        var isPaused: Bool
        /// 보정된 타이머 시작 시각(시작 + 누적 일시정지) — Text(timerInterval:)의 기준.
        /// 고정 Attributes.startedAt으로는 정지·재개를 표현할 수 없어 상태로 옮겼다(스펙 §3.1).
        var timerStart: Date
        /// 일시정지 중 고정 표시할 활동 경과(초) — isPaused일 때만 non-nil
        var elapsedSecondsAtPause: Double?

        /// 마지막 포인트 표시용(스펙 §2.3) — 발화를 놓쳐도 눈으로 확인 가능하게.
        /// 첫 포인트 전에는 nil(줄 자체를 숨김)
        struct LastWaypoint: Codable, Hashable {
            var index: Int
            var segmentMeters: Double
        }

        var lastWaypoint: LastWaypoint?
    }

    /// 경과 시간은 매초 푸시하지 않고 Text(timerInterval:)이 이 값으로 자체 갱신한다(스펙 §5)
    var startedAt: Date
}
