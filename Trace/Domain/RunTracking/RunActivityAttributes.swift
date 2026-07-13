import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
    }

    /// 경과 시간은 매초 푸시하지 않고 Text(timerInterval:)이 이 값으로 자체 갱신한다(스펙 §5)
    var startedAt: Date
}
