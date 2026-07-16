import Foundation

/// 완성된 1km 구간 — 시간은 활동 시간(일시정지 제외) 기준(스펙 §3.2).
struct RunSplit: Equatable, Sendable {
    /// 1부터 시작하는 km 번호
    let index: Int
    let durationSeconds: TimeInterval

    /// 정확히 1km 구간이므로 페이스(초/km) = 구간 시간
    var paceSecondsPerKm: Double { durationSeconds }
}

/// 마지막 미완성 구간(1km 미만 잔여)
struct RunSplitPartial: Equatable, Sendable {
    let index: Int
    let distanceMeters: Double
    let durationSeconds: TimeInterval
}

struct RunSplitResult: Equatable, Sendable {
    let completed: [RunSplit]
    let partial: RunSplitPartial?

    static let empty = RunSplitResult(completed: [], partial: nil)
}

/// km 스플릿 일괄 계산 — 저장 샘플 + 일시정지 구간에서 km별 활동 시간을 파생한다(스펙 §3.2).
/// 저장된 과거 기록(일시정지 없음 = 빈 배열)에도 그대로 소급 적용된다.
/// 거리 적산 규칙은 라이브(RunTrack)와 동일: 일시정지를 사이에 둔 샘플 쌍은 거리를 가산하지 않는다.
enum RunSplitCalculator {
    static let splitDistanceMeters: Double = 1000

    static func splits(samples: [SavedRunSample], pauses: [RunPauseInterval]) -> RunSplitResult {
        guard samples.count >= 2, let first = samples.first else { return .empty }

        var completed: [RunSplit] = []
        var cumulativeDistance: Double = 0
        var lastBoundaryActiveSeconds: TimeInterval = 0
        var nextBoundary = splitDistanceMeters

        for (previous, sample) in zip(samples, samples.dropFirst()) {
            // 일시정지가 사이에 낀 쌍은 이동으로 치지 않는다(라이브 markGap과 동일 규칙)
            let straddlesPause = pauses.contains {
                $0.start < sample.timestamp && $0.end > previous.timestamp
            }
            guard straddlesPause == false else { continue }
            let step = previous.coordinate.distanceMeters(to: sample.coordinate)
            guard step > 0 else { continue }

            let stepStartDistance = cumulativeDistance
            cumulativeDistance += step

            while cumulativeDistance >= nextBoundary {
                // 경계 통과 시각: 쌍 안에서 거리 비례 선형 보간 → 활동 시간으로 환산.
                // GPS 공백 쌍(장시간·장거리)도 같은 보간을 적용한다 — 일정 속도 가정의 근사.
                let fraction = (nextBoundary - stepStartDistance) / step
                let crossingTimestamp = previous.timestamp.addingTimeInterval(
                    sample.timestamp.timeIntervalSince(previous.timestamp) * fraction
                )
                let crossingActive = activeSeconds(
                    at: crossingTimestamp, start: first.timestamp, pauses: pauses
                )
                completed.append(RunSplit(
                    index: completed.count + 1,
                    durationSeconds: crossingActive - lastBoundaryActiveSeconds
                ))
                lastBoundaryActiveSeconds = crossingActive
                nextBoundary += splitDistanceMeters
            }
        }

        var partial: RunSplitPartial?
        let remainder = cumulativeDistance - Double(completed.count) * splitDistanceMeters
        if remainder > 0, let last = samples.last {
            partial = RunSplitPartial(
                index: completed.count + 1,
                distanceMeters: remainder,
                durationSeconds: activeSeconds(at: last.timestamp, start: first.timestamp, pauses: pauses)
                    - lastBoundaryActiveSeconds
            )
        }
        return RunSplitResult(completed: completed, partial: partial)
    }

    /// t 시점까지의 활동 시간 = 벽시계 경과 − [start, t]와 겹치는 일시정지 합
    private static func activeSeconds(
        at t: Date, start: Date, pauses: [RunPauseInterval]
    ) -> TimeInterval {
        let pausedOverlap = pauses.reduce(0.0) { total, pause in
            let overlapStart = max(pause.start, start)
            let overlapEnd = min(pause.end, t)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        return t.timeIntervalSince(start) - pausedOverlap
    }
}
