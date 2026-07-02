# 겹치는 경로 좌표 오프셋 렌더링 (MVP8 마일스톤 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 코스가 자기 자신 위를 지나는 부분(왕복 등)을 감지해 나중에 만든 구간의 표시 좌표를 옆으로 비켜 그려, 두 구간과 각자의 거리 라벨이 항상 함께 보이게 한다.

**Architecture:** `OverlapOffsetResolver`(순수 기하, MapKit 미의존, `Trace/Pages/CoursePlannerPage/`)가 원본 세그먼트 → 표시 좌표로 변환하고, `MapViewRepresentable`은 폴리라인·거리 라벨을 표시 좌표로 그린다. 도메인 데이터는 불변. 기하 원시 함수(점-대-선분 거리, 수직 오프셋)는 `CourseCoordinate+Geo`에 둔다.

**Tech Stack:** Swift (순수 Foundation 기하 계산), XCTest, MapKit (연동 Task만).

**Spec:** `docs/superpowers/specs/2026-07-02-overlap-offset-design.md`
(핵심 결정: 점-대-선분 감지 10m · 오프셋 4m×n · 테이퍼 실거리 15m · 생성 순서 우선(먼저 만든 구간이 도로 위) · 코스 첫/끝 좌표(핀) 오프셋 제외 · 즉시 스냅)

## Global Constraints

- Minimum iOS 17.0, Swift 6 스타일. SwiftLint: force unwrap/cast/try 금지
- 시뮬레이터: 세션당 UDID 1개 고정, iOS 26+ 런타임만 (`docs/agent-rules/testing.md`)
- 커밋 전 3종 통과 + 스탬프: `.git/trace-verify-{build,test,lint}.ok`
- 커밋: `scripts/trace-commit.sh -m "..." -- <paths>`, 브랜치 `feature/overlap-offset` (마일스톤 1 통합 후 main에서 분기)
- 검증 명령 (모든 Task 동일):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test && touch .git/trace-verify-test.ok
swiftlint && touch .git/trace-verify-lint.ok
```

---

### Task 1: 기하 원시 함수 — 점-대-선분 거리, 진행 방향 벡터, 수직 오프셋

**Files:**
- Modify: `Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift` (기존 `distanceMeters(to:)` 아래에 추가)
- Test: `TraceTests/CourseCoordinateGeoTests.swift` (신규)

**Interfaces:**
- Consumes: `CourseCoordinate` (기존 도메인 타입: `latitude`/`longitude: Double`)
- Produces (Task 2·3이 소비):
  - `func distanceMeters(toSegment a: CourseCoordinate, _ b: CourseCoordinate) -> Double`
  - `func headingVector(to other: CourseCoordinate) -> (dxEast: Double, dyNorth: Double)`
  - `func offset(rightOfHeading heading: (dxEast: Double, dyNorth: Double), by meters: Double) -> CourseCoordinate`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/CourseCoordinateGeoTests.swift` 생성 (서울시청 부근, 위도 1도 ≈ 111,320m / 경도 1도 ≈ 111,320 × cos(37.5666°) ≈ 88,180m):

```swift
import XCTest
@testable import Trace

final class CourseCoordinateGeoTests: XCTestCase {
    private let base = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)

    /// base에서 동쪽 east(m), 북쪽 north(m) 이동한 좌표
    private func point(east: Double, north: Double) -> CourseCoordinate {
        CourseCoordinate(
            latitude: base.latitude + north / 111_320.0,
            longitude: base.longitude + east / (111_320.0 * cos(base.latitude * .pi / 180))
        )
    }

    // MARK: - distanceMeters(toSegment:)

    func testPointToSegmentUsesPerpendicularDistanceInsideSpan() {
        // 선분: 동쪽으로 0m→100m. 점: 선분 중간(동쪽 50m)에서 북쪽 8m
        let a = point(east: 0, north: 0)
        let b = point(east: 100, north: 0)
        let p = point(east: 50, north: 8)
        XCTAssertEqual(p.distanceMeters(toSegment: a, b), 8, accuracy: 0.5)
    }

    func testPointToSegmentClampsToNearestEndpointOutsideSpan() {
        // 선분 밖(동쪽 130m, 북쪽 0m) → 가까운 끝점 b(동쪽 100m)까지 30m
        let a = point(east: 0, north: 0)
        let b = point(east: 100, north: 0)
        let p = point(east: 130, north: 0)
        XCTAssertEqual(p.distanceMeters(toSegment: a, b), 30, accuracy: 0.5)
    }

    func testPointToDegenerateSegmentFallsBackToPointDistance() {
        // a == b (길이 0 선분)
        let a = point(east: 10, north: 0)
        let p = point(east: 10, north: 5)
        XCTAssertEqual(p.distanceMeters(toSegment: a, a), 5, accuracy: 0.5)
    }

    // MARK: - offset(rightOfHeading:by:)

    func testOffsetRightOfEastHeadingMovesSouth() {
        // 동쪽 진행의 오른쪽 = 남쪽
        let moved = base.offset(rightOfHeading: (dxEast: 1, dyNorth: 0), by: 4)
        XCTAssertEqual(base.distanceMeters(to: moved), 4, accuracy: 0.1)
        XCTAssertLessThan(moved.latitude, base.latitude)
    }

    func testOffsetRightOfWestHeadingMovesNorth() {
        // 서쪽 진행(왕복의 돌아오는 방향)의 오른쪽 = 북쪽 — 가는 선의 반대편
        let moved = base.offset(rightOfHeading: (dxEast: -1, dyNorth: 0), by: 4)
        XCTAssertEqual(base.distanceMeters(to: moved), 4, accuracy: 0.1)
        XCTAssertGreaterThan(moved.latitude, base.latitude)
    }

    func testZeroHeadingOrZeroMetersReturnsSelf() {
        XCTAssertEqual(base.offset(rightOfHeading: (dxEast: 0, dyNorth: 0), by: 4), base)
        XCTAssertEqual(base.offset(rightOfHeading: (dxEast: 1, dyNorth: 0), by: 0), base)
    }

    // MARK: - headingVector(to:)

    func testHeadingVectorEastward() {
        let heading = base.headingVector(to: point(east: 100, north: 0))
        XCTAssertEqual(heading.dxEast, 100, accuracy: 1)
        XCTAssertEqual(heading.dyNorth, 0, accuracy: 1)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: Global Constraints의 test 명령
Expected: FAIL — `value of type 'CourseCoordinate' has no member 'distanceMeters(toSegment:_:)'` (컴파일 에러)

- [ ] **Step 3: 최소 구현**

`Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift`의 기존 extension 안에 추가:

```swift
    /// 이 좌표에서 선분 a-b까지의 최단 거리(미터).
    /// 코스 규모(수 km)에서는 등장방형(equirectangular) 근사로 충분하다.
    func distanceMeters(toSegment a: CourseCoordinate, _ b: CourseCoordinate) -> Double {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        // 자기 자신을 원점으로 한 로컬 평면(미터)
        let ax = (a.longitude - longitude) * metersPerDegreeLon
        let ay = (a.latitude - latitude) * metersPerDegreeLat
        let bx = (b.longitude - longitude) * metersPerDegreeLon
        let by = (b.latitude - latitude) * metersPerDegreeLat
        let abx = bx - ax
        let aby = by - ay
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return sqrt(ax * ax + ay * ay) }
        let t = max(0, min(1, -(ax * abx + ay * aby) / lengthSquared))
        let closestX = ax + t * abx
        let closestY = ay + t * aby
        return sqrt(closestX * closestX + closestY * closestY)
    }

    /// self → other 로컬 평면 벡터(미터, 동쪽/북쪽 성분)
    func headingVector(to other: CourseCoordinate) -> (dxEast: Double, dyNorth: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        return (
            (other.longitude - longitude) * metersPerDegreeLon,
            (other.latitude - latitude) * metersPerDegreeLat
        )
    }

    /// 진행 방향(heading) 기준 오른쪽 수직으로 meters만큼 이동한 좌표
    func offset(
        rightOfHeading heading: (dxEast: Double, dyNorth: Double),
        by meters: Double
    ) -> CourseCoordinate {
        let length = sqrt(heading.dxEast * heading.dxEast + heading.dyNorth * heading.dyNorth)
        guard length > 0, meters != 0 else { return self }
        // (동, 북) 진행의 오른쪽 = (북, -동)
        let rightEast = heading.dyNorth / length
        let rightNorth = -heading.dxEast / length
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        return CourseCoordinate(
            latitude: latitude + (meters * rightNorth) / metersPerDegreeLat,
            longitude: longitude + (meters * rightEast) / metersPerDegreeLon
        )
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Global Constraints의 test 명령
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 겹침 오프셋용 기하 원시 함수 추가

- 점-대-선분 최단 거리(등장방형 근사) — 희소 정점 폴리라인 감지용
- 진행 방향 벡터와 오른쪽 수직 오프셋 이동
- OverlapOffsetResolver(마일스톤 2)의 기반" -- Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift TraceTests/CourseCoordinateGeoTests.swift
```

---

### Task 2: OverlapOffsetResolver — 감지 + 생성 순서 우선 + 배수 오프셋

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift`
- Test: `TraceTests/OverlapOffsetResolverTests.swift` (신규)

**Interfaces:**
- Consumes: Task 1의 기하 함수, `CourseSegment`(`.coordinates`), `segmentColorKeys` 규약(공간 순서 배열과 병렬인 생성 순번 — `CourseEditSession.segmentColorKeys`와 동일)
- Produces (Task 3·4가 소비):
  - `OverlapOffsetResolver.Parameters` (기본값: detectionThresholdMeters 10, offsetStepMeters 4, taperLengthMeters 15, minimumRunPointCount 3)
  - `static func displayCoordinates(segments: [CourseSegment], colorKeys: [Int], parameters: Parameters) -> [[CourseCoordinate]]` — 입력과 같은 공간 순서

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/OverlapOffsetResolverTests.swift` 생성. 이 Task에서는 감지·우선순위·배수까지만 검증한다 (테이퍼·핀 예외는 Task 3에서 추가):

```swift
import XCTest
@testable import Trace

final class OverlapOffsetResolverTests: XCTestCase {
    private let base = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)

    private func point(east: Double, north: Double) -> CourseCoordinate {
        CourseCoordinate(
            latitude: base.latitude + north / 111_320.0,
            longitude: base.longitude + east / (111_320.0 * cos(base.latitude * .pi / 180))
        )
    }

    /// 동서 방향 직선 경로 (from → to, spacing 간격)
    private func line(fromEast: Double, toEast: Double, north: Double, spacing: Double) -> [CourseCoordinate] {
        let step: Double = fromEast <= toEast ? spacing : -spacing
        var coords: [CourseCoordinate] = []
        var east = fromEast
        while (step > 0 && east <= toEast) || (step < 0 && east >= toEast) {
            coords.append(point(east: east, north: north))
            east += step
        }
        return coords
    }

    private func segment(_ coords: [CourseCoordinate]) -> CourseSegment {
        .tapped(coordinates: coords, distanceMeters: 0)
    }

    /// 대응 점끼리의 평균 이동 거리(미터) — run 중앙부만 (테이퍼 경계 제외)
    private func midDisplacement(_ original: [CourseCoordinate], _ display: [CourseCoordinate]) -> Double {
        let mid = original.count / 2
        return original[mid].distanceMeters(to: display[mid])
    }

    // MARK: - 기본 동작

    func testNonOverlappingSegmentsUnchanged() {
        let a = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let b = segment(line(fromEast: 0, toEast: 200, north: 100, spacing: 10)) // 100m 떨어진 평행선
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [a, b], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(display[0], a.coordinates)
        XCTAssertEqual(display[1], b.coordinates)
    }

    func testOutAndBackOffsetsLaterCreatedSegmentOnly() {
        // 가는 길(동쪽 0→200m), 오는 길(동쪽 200→0m, 같은 도로)
        let outbound = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let inbound = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        // 먼저 생성(colorKey 0)된 가는 길은 도로 위 유지
        XCTAssertEqual(display[0], outbound.coordinates)
        // 오는 길 중앙부는 약 4m 이동
        XCTAssertEqual(midDisplacement(inbound.coordinates, display[1]), 4, accuracy: 1.0)
        // 서쪽 진행의 오른쪽 = 북쪽으로 밀림
        let mid = inbound.coordinates.count / 2
        XCTAssertGreaterThan(display[1][mid].latitude, inbound.coordinates[mid].latitude)
    }

    func testPrependKeepsEarlierCreatedSegmentOnRoad() {
        // 공간 순서 ≠ 생성 순서: 새 구간(colorKey 1)이 prepend되어 배열 맨 앞
        let older = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))    // colorKey 0
        let prepended = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10)) // colorKey 1
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [prepended, older], colorKeys: [1, 0], parameters: .init()
        )
        // 먼저 생성된 구간(공간상 뒤)이 도로 위에 남고, prepend된 새 구간이 밀린다
        XCTAssertEqual(display[1], older.coordinates)
        XCTAssertEqual(midDisplacement(prepended.coordinates, display[0]), 4, accuracy: 1.0)
    }

    func testTripleOverlapUsesMultipliedOffset() {
        let first = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let second = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let third = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [first, second, third], colorKeys: [0, 1, 2], parameters: .init()
        )
        XCTAssertEqual(display[0], first.coordinates)
        XCTAssertEqual(midDisplacement(second.coordinates, display[1]), 4, accuracy: 1.0)
        // 세 번째 통과는 앞선 2개와 겹침 → 8m
        XCTAssertEqual(midDisplacement(third.coordinates, display[2]), 8, accuracy: 1.5)
    }

    // MARK: - 감지 방식 (점-대-선분)

    func testSparseVertexPolylineStillDetected() {
        // 라우팅 선처럼 정점이 희소(100m 간격)한 직선 + 그 위를 지나는 조밀(5m)한 그리기 스트로크
        let sparse = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 100)) // 정점 3개
        let dense = segment(line(fromEast: 200, toEast: 0, north: 2, spacing: 5))    // 2m 옆, 점-대-점이면 최대 50m
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [sparse, dense], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertGreaterThan(midDisplacement(dense.coordinates, display[1]), 3)
    }

    func testShortNoiseCrossingIgnored() {
        // 수직 교차: 임계 안에 드는 점이 1~2개뿐 → run 필터로 무시
        let horizontal = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let crossingCoords = (0...20).map { point(east: 100, north: Double($0) * 10 - 100) } // 남→북 수직선
        let crossing = segment(crossingCoords)
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [horizontal, crossing], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(display[1], crossing.coordinates)
    }

    // MARK: - 불변성

    func testOriginalSegmentsUntouched() {
        let outbound = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let inbound = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let originalInboundCoords = inbound.coordinates
        _ = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(inbound.coordinates, originalInboundCoords)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: Global Constraints의 test 명령
Expected: FAIL — `cannot find 'OverlapOffsetResolver' in scope`

- [ ] **Step 3: 구현**

`Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift` 생성. 이 Task에서는 테이퍼를 "즉시 적용"(보간 없음)으로 두고 Task 3에서 교체한다 — 단, 아래 코드는 테이퍼 자리(`taperedOffsets`)를 이미 분리해 둔다:

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Global Constraints의 test 명령
Expected: PASS (테이퍼 미적용이라 `midDisplacement`의 accuracy 안에서 통과)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: OverlapOffsetResolver 겹침 감지 + 생성 순서 우선 오프셋

- 점-대-선분 수직 거리로 감지 (희소 정점·소스 혼합에도 동작)
- 생성 순서 처리로 먼저 만든 구간이 도로 위 유지 (prepend 표시 안정)
- 겹치는 앞선 구간 수에 비례한 4m×n 배수 오프셋, 잡음 run 필터" -- Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift TraceTests/OverlapOffsetResolverTests.swift
```

---

### Task 3: 테이퍼(실거리 15m 선형 보간) + 핀 예외 검증

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift` (`taperedOffsets` 교체)
- Modify: `TraceTests/OverlapOffsetResolverTests.swift` (테스트 추가)

**Interfaces:**
- Consumes: Task 2의 `taperedOffsets` 자리, Task 1의 `distanceMeters(to:)`
- Produces: 동일 시그니처 (내부 동작만 보간으로 변경)

- [ ] **Step 1: 실패하는 테스트 추가**

`OverlapOffsetResolverTests.swift`에 추가:

```swift
    // MARK: - 테이퍼 (실거리 15m 선형 보간)

    func testTaperRampsUpFromRunBoundary() {
        // 오는 길의 겹침 run 시작 부근: 오프셋이 0 → 4m로 점진 증가해야 한다
        let outbound = segment(line(fromEast: 0, toEast: 300, north: 0, spacing: 5))
        let inbound = segment(line(fromEast: 300, toEast: 0, north: 0, spacing: 5))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        let displacements = inbound.coordinates.indices.map {
            inbound.coordinates[$0].distanceMeters(to: display[1][$0])
        }
        // 중앙부는 4m에 도달
        XCTAssertEqual(displacements[displacements.count / 2], 4, accuracy: 0.5)
        // 인접 점(5m 간격) 사이 오프셋 변화는 테이퍼 기울기(4m/15m × 5m ≈ 1.33m) 이하
        for i in 1..<displacements.count {
            XCTAssertLessThanOrEqual(
                abs(displacements[i] - displacements[i - 1]), 1.4,
                "인덱스 \(i)에서 단차 발생"
            )
        }
    }

    func testNTransitionHasNoStep() {
        // 세 번째 통과가 run 중간에서 겹침 수가 변해도(1겹→2겹) 단차 없이 보간되어야 한다
        // 구성: first는 동쪽 0~150m만, second는 0~300m 전체 왕복 → third(0~300m)는
        // 0~150m 구간에서 2겹(first+second), 150~300m 구간에서 1겹(second)
        let first = segment(line(fromEast: 0, toEast: 150, north: 0, spacing: 5))
        let second = segment(line(fromEast: 300, toEast: 0, north: 0, spacing: 5))
        let third = segment(line(fromEast: 0, toEast: 300, north: 0, spacing: 5))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [first, second, third], colorKeys: [0, 1, 2], parameters: .init()
        )
        let displacements = third.coordinates.indices.map {
            third.coordinates[$0].distanceMeters(to: display[2][$0])
        }
        for i in 1..<displacements.count {
            XCTAssertLessThanOrEqual(
                abs(displacements[i] - displacements[i - 1]), 1.4,
                "n 전환 지점 인덱스 \(i)에서 4m 단차 발생"
            )
        }
    }

    // MARK: - 핀 예외

    func testCourseEndpointsStayPinned() {
        // 왕복: 코스 마지막 좌표(도착 핀 지점)는 겹쳐도 원본 유지
        let outbound = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let inbound = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(display[1].last, inbound.coordinates.last, "도착 핀 지점이 밀리면 안 됨")
        XCTAssertEqual(display[0].first, outbound.coordinates.first, "출발 핀 지점이 밀리면 안 됨")
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: Global Constraints의 test 명령
Expected: `testTaperRampsUpFromRunBoundary`와 `testNTransitionHasNoStep` FAIL (즉시 적용이라 run 경계에서 0→4m 단차). `testCourseEndpointsStayPinned`는 Task 2 구현으로 이미 PASS일 수 있음 — 그 경우 회귀 가드로 유지.

- [ ] **Step 3: taperedOffsets를 실거리 기반 기울기 제한으로 교체**

`OverlapOffsetResolver.swift`의 `taperedOffsets`를 다음으로 교체:

```swift
    /// 목표 오프셋(step × n)에 실거리 기반 기울기 제한을 걸어, run 경계(0→step)와
    /// run 내부의 n 전환(step→2×step)을 모두 taperLength에 걸친 선형 램프로 만든다.
    /// 앞→뒤, 뒤→앞 두 번의 패스로 모든 전환 지점을 대칭으로 보간한다.
    private static func taperedOffsets(
        counts: [Int], coords: [CourseCoordinate],
        step: Double, taperLength: Double
    ) -> [Double] {
        var offsets = counts.map { Double($0) * step }
        guard offsets.count > 1, taperLength > 0 else { return offsets }
        let slope = step / taperLength // 한 단(step) 전환을 taperLength 미터에 걸쳐

        for i in 1..<offsets.count {
            let distance = coords[i - 1].distanceMeters(to: coords[i])
            offsets[i] = min(offsets[i], offsets[i - 1] + slope * distance)
        }
        for i in stride(from: offsets.count - 2, through: 0, by: -1) {
            let distance = coords[i].distanceMeters(to: coords[i + 1])
            offsets[i] = min(offsets[i], offsets[i + 1] + slope * distance)
        }
        return offsets
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Global Constraints의 test 명령
Expected: PASS — Task 2의 기존 테스트(중앙부 4m/8m)도 계속 통과해야 한다 (run이 충분히 길어 중앙부는 목표치 도달)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 오프셋 테이퍼 — 실거리 15m 선형 보간

- run 경계(0→4m)와 n 전환(4m→8m) 모두 기울기 제한으로 단차 제거
- 실거리 기준이라 그리기(조밀)/라우팅(희소) 정점 밀도와 무관
- 코스 첫/끝 좌표(핀 지점) 원본 유지 검증 추가" -- Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift TraceTests/OverlapOffsetResolverTests.swift
```

---

### Task 4: MapViewRepresentable 연동 — 표시 좌표로 그리기

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (`updateUIView`의 오버레이 재구성 블록만)

**Interfaces:**
- Consumes: `OverlapOffsetResolver.displayCoordinates(segments:colorKeys:parameters:)` (Task 2·3)
- Produces: 없음 (렌더링 동작 변경)

- [ ] **Step 1: 오버레이 재구성 블록 수정**

`updateUIView`의 스냅샷 비교 블록(`if context.coordinator.lastSegmentSnapshots != currentSnapshots {`) 내부에서, 기존의 세그먼트 순회를 표시 좌표 기반으로 교체한다. 변경 전 코드:

```swift
            for (index, segment) in segments.enumerated() {
                var coords = segment.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
```

변경 후 (resolver 호출을 순회 앞에 추가하고, 폴리라인·라벨 좌표만 표시 좌표를 쓴다 — 거리 텍스트는 원본 `segment.distanceMeters` 유지):

```swift
            // 겹치는 경로는 표시 좌표만 옆으로 비켜 그린다 (도메인 좌표 불변).
            // 스냅샷 게이트 안이므로 세그먼트가 실제로 바뀔 때만 재계산된다.
            let displayCoordinates = OverlapOffsetResolver.displayCoordinates(
                segments: segments, colorKeys: segmentColorKeys
            )
            for (index, segment) in segments.enumerated() {
                var coords = displayCoordinates[index].map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
```

블록 내 나머지(색상 colorKey, `midIndex` 라벨 위치, `segment.distanceMeters` 텍스트)는 그대로 — `coords`가 이미 표시 좌표이므로 라벨은 자동으로 밀린 선 위에 얹힌다.

- [ ] **Step 2: 빌드 + 전체 테스트 + lint**

Run: Global Constraints의 3종 명령
Expected: 모두 PASS

- [ ] **Step 3: 시뮬레이터 스모크 확인**

XcodeBuildMCP로 앱 실행 → 탭으로 A→B 경로 생성 → 같은 길로 B→A 경로 추가(왕복) → 확대해서 두 선이 나란히 보이는지, 각 라벨이 자기 선 위에 있는지, 출발/도착 핀이 선 끝과 일치하는지 확인.

- [ ] **Step 4: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 지도 렌더링을 겹침 오프셋 표시 좌표로 전환

- 폴리라인과 거리 라벨 위치를 resolver 표시 좌표로 그림
- 거리 텍스트는 원본 좌표 기반 값 유지 (표시만 이동)
- 스냅샷 게이트 안에서만 재계산 (카메라 이동 시 비용 없음)" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
```

---

### Task 5: MVP8 실기기 QA 체크리스트 작성·제출

**Files:**
- Create: `docs/qa/YYYY-MM-DD-mvp8-course-ux-device-checklist.md` (작성일 기준)

- [ ] **Step 1: 체크리스트 작성** (`docs/agent-rules/testing.md` 템플릿 기반)

마일스톤 1 항목(플랜 1 Task 4에 기록)과 이 마일스톤 항목을 묶는다:
- 왕복 코스에서 두 선이 나란히 보이고 각 라벨이 자기 선 위에 있는지
- 왕복 코스에서 도착 핀과 선 끝이 일치하는지
- 코스 전체 조망 배율에서 라벨-선 색 어긋남이 재현되는지 (화면 포인트 오프셋 백로그 트리거 판정)
- 줌 배율별 병합 시점 기록, 10m/4m 초기값 체감 조정
- 겹치는 스트로크 확정 시 즉시 스냅이 거슬리는지 (거슬리면 애니메이션 백로그 등록)
- 좁은 골목·도로변 산책로에서 거짓 양성(안 겹쳤는데 밀림) 여부
- attach 직후 프레임 히치 여부 (O(N²) 감지 비용 실측 — 문제 시 격자 해싱 백로그)

- [ ] **Step 2: 사용자에게 제출**

체크리스트 경로를 안내하고 실기기 QA를 요청한다. 피드백은 `docs/backlog.md`로 캡처 (genuinely broken은 현 세션 수정).

---

## Self-Review 결과

- 스펙 커버리지: 점-대-선분 감지 → Task 1·2, 생성 순서 우선 → Task 2, 4m×n 배수 → Task 2, 실거리 15m 테이퍼 + n 전환 연속성 → Task 3, 핀 예외 → Task 2·3, 표시 좌표 렌더링 + 라벨 위치 → Task 4, 스냅샷 게이트 재사용 → Task 4, 즉시 스냅(결정) → 추가 구현 없음(기본 동작), 실기기 QA → Task 5. 누락 없음.
- 타입 일관성: `displayCoordinates(segments:colorKeys:parameters:)` 시그니처가 Task 2 정의 = Task 4 호출 (parameters는 기본값 사용). Task 1 기하 함수명이 Task 2·3 사용처와 일치.
- 알려진 유의점: `testShortNoiseCrossingIgnored`의 수직 교차 픽스처는 spacing 10m 기준으로 임계(10m) 안에 드는 점이 1~2개가 되도록 구성했다 — 구현 중 실측으로 픽스처가 3점 이상 걸리면 spacing을 늘려 조정한다(테스트 의도는 run 필터 검증).
