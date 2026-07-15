import Foundation

/// 일시정지 구간 — 시각 쌍. GPS 공백과 구분 불가하므로 파생하지 않고 명시 기록한다(스펙 §4).
struct RunPauseInterval: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
