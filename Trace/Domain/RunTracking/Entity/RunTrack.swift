import Foundation

/// 필터를 통과한 샘플의 누적 + 파생값 계산.
/// 연속으로 버려진 공백 구간은 다음 유효 샘플과의 직선 거리로 자동 가산된다(스펙 §2 공백 규칙).
struct RunTrack: Equatable, Sendable {
    static let elevationRiseThresholdMeters: Double = 3
    static let maxValidVerticalAccuracyMeters: Double = 10
    static let currentPaceWindowSeconds: TimeInterval = 30

    private(set) var samples: [RunSample] = []
    private(set) var totalDistanceMeters: Double = 0
    private(set) var elevationGainMeters: Double = 0
    // 고도 상승 임계값 누적 상태(GPS 고도 노이즈 억제 — 스펙 §2)
    private var lastValidAltitudeMeters: Double?
    private var pendingRiseMeters: Double = 0

    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

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

    mutating func append(_ sample: RunSample) {
        if let previous = samples.last {
            totalDistanceMeters += previous.coordinate.distanceMeters(to: sample.coordinate)
        }
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
