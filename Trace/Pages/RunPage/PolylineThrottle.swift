import Foundation

/// SwiftUI Map의 자라는 폴리라인을 매 위치 업데이트마다 다시 그리지 않기 위한 게이트(스펙 §4).
struct PolylineThrottle {
    static let minInterval: TimeInterval = 3
    static let minDistanceMeters: Double = 20

    private var lastRefreshAt: Date?
    private var lastRefreshDistance: Double = 0

    mutating func shouldRefresh(now: Date, totalDistanceMeters: Double) -> Bool {
        guard let last = lastRefreshAt else {
            lastRefreshAt = now
            lastRefreshDistance = totalDistanceMeters
            return true
        }
        let timeDue = now.timeIntervalSince(last) >= Self.minInterval
        let distanceDue = totalDistanceMeters - lastRefreshDistance >= Self.minDistanceMeters
        guard timeDue || distanceDue else { return false }
        lastRefreshAt = now
        lastRefreshDistance = totalDistanceMeters
        return true
    }
}

enum RunPaceFormatter {
    /// 초/km → `5'32"`. nil·0 이하·60분/km 초과는 `--'--"`.
    static func string(secondsPerKm: Double?) -> String {
        guard let seconds = secondsPerKm, seconds > 0, seconds < 3600 else { return "--'--\"" }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d'%02d\"", minutes, remainder)
    }
}
