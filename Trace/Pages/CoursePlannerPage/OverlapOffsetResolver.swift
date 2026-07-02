import Foundation

// 겹치는 경로를 표시할 때만 옆으로 비켜 그리는 순수 기하 계산.
// 도메인 좌표는 불변이며 MapKit에 의존하지 않는다 (스펙: 2026-07-02-overlap-offset-design.md).
// 처리 순서는 생성(attach) 순서 — 먼저 만든 구간이 도로 위에 남는다 (prepend 표시 안정성).
enum OverlapOffsetResolver {
    struct Parameters {
        var detectionThresholdMeters = 10.0
        var offsetStepMeters = 4.0
        var taperLengthMeters = 15.0
        var minimumRunPointCount = 3 // 1~2점 잡음성 겹침(수직 교차 등) 무시
    }

    /// - segments: 공간 순서의 세그먼트 (렌더링 순서)
    /// - colorKeys: segments와 병렬인 생성(attach) 순번 — `CourseEditSession.segmentColorKeys`
    /// - Returns: segments와 같은 공간 순서의 표시 좌표
    static func displayCoordinates(
        segments: [CourseSegment],
        colorKeys: [Int],
        parameters: Parameters = Parameters()
    ) -> [[CourseCoordinate]] {
        let originals = segments.map(\.coordinates)
        guard originals.count > 1 else { return originals }

        // 핀 예외 대상: 코스(공간 순서)의 첫/끝 좌표 (Task 3에서 사용)
        let courseFirst = originals.first?.first
        let courseLast = originals.last?.last

        let creationOrder = originals.indices.sorted {
            key(at: $0, colorKeys: colorKeys) < key(at: $1, colorKeys: colorKeys)
        }

        var display = originals
        var processedOriginals: [[CourseCoordinate]] = []

        for spatialIndex in creationOrder {
            let coords = originals[spatialIndex]
            defer { processedOriginals.append(coords) }
            guard coords.count >= 2, !processedOriginals.isEmpty else { continue }

            var overlapCounts = coords.map { pointValue in
                processedOriginals.reduce(into: 0) { count, earlier in
                    if isWithin(
                        parameters.detectionThresholdMeters,
                        point: pointValue, ofPolyline: earlier
                    ) {
                        count += 1
                    }
                }
            }
            suppressShortRuns(&overlapCounts, minimumRun: parameters.minimumRunPointCount)
            exemptPins(
                &overlapCounts, coords: coords,
                courseFirst: courseFirst, courseLast: courseLast
            )
            guard overlapCounts.contains(where: { $0 > 0 }) else { continue }

            let offsets = taperedOffsets(
                counts: overlapCounts, coords: coords,
                step: parameters.offsetStepMeters,
                taperLength: parameters.taperLengthMeters
            )
            display[spatialIndex] = applyOffsets(offsets, to: coords)
        }
        return display
    }

    // MARK: - Private

    private static func key(at index: Int, colorKeys: [Int]) -> Int {
        index < colorKeys.count ? colorKeys[index] : index
    }

    private static func isWithin(
        _ threshold: Double,
        point: CourseCoordinate,
        ofPolyline polyline: [CourseCoordinate]
    ) -> Bool {
        guard polyline.count >= 2 else {
            guard let only = polyline.first else { return false }
            return point.distanceMeters(to: only) <= threshold
        }
        for i in 0..<(polyline.count - 1)
        where point.distanceMeters(toSegment: polyline[i], polyline[i + 1]) <= threshold {
            return true
        }
        return false
    }

    /// 연속 겹침 run이 minimumRun보다 짧으면 잡음으로 보고 0으로 되돌린다
    private static func suppressShortRuns(_ counts: inout [Int], minimumRun: Int) {
        var runStart: Int?
        for i in 0...counts.count {
            let inRun = i < counts.count && counts[i] > 0
            if inRun, runStart == nil {
                runStart = i
            } else if !inRun, let start = runStart {
                if i - start < minimumRun {
                    for j in start..<i { counts[j] = 0 }
                }
                runStart = nil
            }
        }
    }

    /// 코스 첫/끝 좌표(출발·도착 핀 지점)는 오프셋 0 고정 — 핀은 원본 좌표에 남으므로 (스펙 "핀 지점 예외")
    private static func exemptPins(
        _ counts: inout [Int],
        coords: [CourseCoordinate],
        courseFirst: CourseCoordinate?,
        courseLast: CourseCoordinate?
    ) {
        if let pin = courseFirst, coords.first == pin { counts[0] = 0 }
        if let pin = courseLast, coords.last == pin { counts[counts.count - 1] = 0 }
    }

    /// Task 2 시점: 즉시 적용 (Task 3에서 실거리 기반 선형 테이퍼로 교체)
    private static func taperedOffsets(
        counts: [Int], coords: [CourseCoordinate],
        step: Double, taperLength: Double
    ) -> [Double] {
        counts.map { Double($0) * step }
    }

    private static func applyOffsets(
        _ offsets: [Double], to coords: [CourseCoordinate]
    ) -> [CourseCoordinate] {
        coords.indices.map { i in
            let meters = offsets[i]
            guard meters > 0 else { return coords[i] }
            // 로컬 진행 방향: 이웃 점 기준 (양 끝은 한쪽 이웃만)
            let before = coords[max(0, i - 1)]
            let after = coords[min(coords.count - 1, i + 1)]
            let heading = before.headingVector(to: after)
            return coords[i].offset(rightOfHeading: heading, by: meters)
        }
    }
}
