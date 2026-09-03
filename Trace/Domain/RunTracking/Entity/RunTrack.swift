import Foundation

/// 필터를 통과한 샘플의 누적 + 파생값 계산.
/// 연속으로 버려진 공백 구간은 다음 유효 샘플과의 직선 거리로 자동 가산된다(스펙 §2 공백 규칙).
struct RunTrack: Equatable, Sendable {
    static let elevationRiseThresholdMeters: Double = 3
    static let maxValidVerticalAccuracyMeters: Double = 10
    /// 현재 페이스 창(초). 이 지표는 「지금 얼마나 빠른가」를 말하므로 최신성이 먼저다 —
    /// 창이 길면 이미 지나간 속도가 섞여 오르막·내리막 전환을 늦게 따라온다.
    /// 업계 관행은 5~10초다(Garmin 약 5초, Timex Global Trainer 5초 평균).
    /// 더 줄이지 않는 이유: `RunLocationTracker`가 `distanceFilter = 5`(m)를 써서 러닝 중 샘플
    /// 간격이 약 2초이고, 5초 창이면 평균 낼 샘플이 2~3개뿐이라 GPS 오차가 상쇄되지 않는다.
    /// 근거: docs/superpowers/specs/2026-09-02-pace-definition-design.md §3
    static let currentPaceWindowSeconds: TimeInterval = 10

    private(set) var samples: [RunSample] = []
    private(set) var totalDistanceMeters: Double = 0
    private(set) var elevationGainMeters: Double = 0
    // 고도 상승 임계값 누적 상태(GPS 고도 노이즈 억제 — 스펙 §2)
    private var lastValidAltitudeMeters: Double?
    private var pendingRiseMeters: Double = 0
    // 재개 직후 첫 샘플의 거리 가산 억제 플래그(일시정지 경계 순간이동 방지 — 스펙 §3.1)
    private var pendingGap = false

    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// GPS 샘플 구간(첫~마지막 타임스탬프, 일시정지 **포함**) 기준 평균 페이스.
    ///
    /// **프로덕션 화면·발화는 이 값을 쓰지 않는다** — 그쪽은 활동 시간 기준인
    /// `RunSession.averagePaceSecondsPerKm(now:)`를 쓴다(MVP14 §3.1).
    /// **그렇다고 지우지 말 것**: `RunPageViewModelTests`가 이 값을 `buggyPace` 대조군으로 삼아
    /// 「뷰모델이 GPS 구간 기준을 쓰지 않는다」를 증명한다. 지우면 그 회귀 가드가 함께 사라진다.
    var averagePaceSecondsPerKm: Double? {
        guard totalDistanceMeters > 0, duration > 0 else { return nil }
        return duration / (totalDistanceMeters / 1000)
    }

    var currentPaceSecondsPerKm: Double? {
        guard let last = samples.last else { return nil }
        let windowStart = last.timestamp.addingTimeInterval(-Self.currentPaceWindowSeconds)
        let validSpeeds = samples
            .filter { $0.timestamp >= windowStart && $0.speedMetersPerSecond > 0 }
            .map(\.speedMetersPerSecond)
        guard validSpeeds.isEmpty == false else { return nil }
        let averageSpeed = validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        return 1000 / averageSpeed
    }

    /// 다음 append 1회에 한해 직전 샘플과의 거리를 가산하지 않는다 — 일시정지 재개 시 호출.
    mutating func markGap() {
        pendingGap = true
    }

    mutating func append(_ sample: RunSample) {
        if let previous = samples.last, pendingGap == false {
            totalDistanceMeters += previous.coordinate.distanceMeters(to: sample.coordinate)
        }
        pendingGap = false
        accumulateElevation(from: sample)
        samples.append(sample)
    }

    private mutating func accumulateElevation(from sample: RunSample) {
        guard sample.verticalAccuracyMeters > 0,
              sample.verticalAccuracyMeters <= Self.maxValidVerticalAccuracyMeters
        else { return }
        defer { lastValidAltitudeMeters = sample.altitudeMeters }
        guard let last = lastValidAltitudeMeters else { return }
        let delta = sample.altitudeMeters - last
        if delta > 0 {
            pendingRiseMeters += delta
            if pendingRiseMeters >= Self.elevationRiseThresholdMeters {
                elevationGainMeters += pendingRiseMeters
                pendingRiseMeters = 0
            }
        } else {
            pendingRiseMeters = 0
        }
    }
}
