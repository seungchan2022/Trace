# CourseEditSession 구현 플랜 — 탭↔그리기 통합 + undo/clear 통합

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `CourseEditSession` Application 레이어를 도입해 탭 모드 경로 누적, 탭↔그리기 자동 이어붙이기, undo/clear 통합을 올바르게 구현한다.

**Architecture:** `CourseEditSession`이 방향 판단·gap 라우팅·세그먼트 병합을 단독으로 처리하는 Application 레이어 오케스트레이터가 된다. ViewModel은 얇은 조율자로 단순화되며, `session.attach` 한 번 호출 = `session.segments`에 1개 추가 = undo 한 번에 완전 제거 단위를 보장한다.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, MapKit/MKDirections

## Global Constraints

- iOS 17+ minimum (Observation API)
- `@MainActor @Observable` — ViewModel, CourseEditSession 공통 패턴
- Swift 6 style `async`/`await`, `@MainActor` UI 상태 분리
- `CoursePlanningServiceProtocol` — `route(from:to:) async throws -> PlannedCourse`
- No Co-Authored-By in commits. Commit body: 3–4 non-empty lines.
- Never commit on main; use branch `feature/mvp6-course-edit-session`.

---

## 파일 구조

| 파일 | 변경 |
|---|---|
| `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift` | `reversed()` 추가 |
| `Trace/Application/CoursePlanning/CourseEditSession.swift` | **신규** |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` | 전면 교체 |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` | `startCoordinate` → `pendingTapStart` |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift` | async 전환 + undo 통합 |
| `TraceTests/CourseEditSessionTests.swift` | **신규** |
| `TraceTests/CoursePlannerViewModelTests.swift` | 업데이트 |

---

### Task 1: CourseSegment.reversed() + CourseEditSession 구현

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift`
- Create: `Trace/Application/CoursePlanning/CourseEditSession.swift`
- Create: `TraceTests/CourseEditSessionTests.swift`

**Interfaces:**
- Produces:
  - `CourseSegment.reversed() -> CourseSegment`
  - `CourseEditSession.segments: [CourseSegment]` (private(set))
  - `CourseEditSession.course: PlannedCourse?` (computed)
  - `CourseEditSession.attach(_ newSegment: CourseSegment, using service: CoursePlanningServiceProtocol) async throws`
  - `CourseEditSession.undo()`
  - `CourseEditSession.clear()`

---

- [ ] **Step 1-1: CourseSegment에 reversed() 추가**

`Trace/Domain/CoursePlanning/Entity/CourseSegment.swift` 끝에 추가:

```swift
func reversed() -> CourseSegment {
    switch self {
    case .tapped(let coords, let dist):
        return .tapped(coordinates: coords.reversed(), distanceMeters: dist)
    case .drawn(let coords, let dist):
        return .drawn(coordinates: coords.reversed(), distanceMeters: dist)
    }
}
```

- [ ] **Step 1-2: CourseEditSessionTests 실패 테스트 작성**

`TraceTests/CourseEditSessionTests.swift` 신규 생성:

```swift
import XCTest
@testable import Trace

@MainActor
final class CourseEditSessionTests: XCTestCase {
    private let A = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    private let B = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    private let C = CourseCoordinate(latitude: 37.52, longitude: 127.00)
    private let D = CourseCoordinate(latitude: 37.53, longitude: 127.00)

    // MARK: - reversed()

    func testReversedTapped() {
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [B, A])
        XCTAssertEqual(rev.distanceMeters, 100)
    }

    func testReversedDrawn() {
        let seg = CourseSegment.drawn(coordinates: [A, B, C], distanceMeters: 200)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [C, B, A])
    }

    // MARK: - attach: no existing course

    func testAttachFirstSegment_appendsDirectly() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        try await session.attach(seg, using: service)
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.segments.first?.coordinates.first, A)
        XCTAssertEqual(session.segments.first?.coordinates.last, B)
        XCTAssertEqual(service.routeCallCount, 0, "gap 라우팅 없어야 함")
    }

    // MARK: - attach: append (new start near existing end)

    func testAttach_appendNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: B→C (start near existing end B → append, no gap)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [near_B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A)
    }

    // MARK: - attach: prepend (new end near existing start)

    func testAttach_prependNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: A→B (end near existing start B → prepend, no gap)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [A, near_B], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        // prepend되므로 전체 경로 시작이 A여야 함
        XCTAssertEqual(session.course?.coordinates.first, A)
    }

    // MARK: - attach: reversed append (new end near existing end)

    func testAttach_reversedAppend() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: C→B (end near existing end B → reverse to B→C, then append)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [C, near_B], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        // 두 번째 세그먼트는 reversed되어 near_B→C 순서여야 함
        XCTAssertEqual(session.segments.last?.coordinates.last, C)
    }

    // MARK: - undo

    func testUndo_removesLastSegment() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        session.undo()
        XCTAssertEqual(session.segments.count, 1)
    }

    func testUndo_empty_doesNothing() {
        let session = CourseEditSession()
        session.undo()
        XCTAssertTrue(session.segments.isEmpty)
    }

    // MARK: - clear

    func testClear_removesAll() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        session.clear()
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertNil(session.course)
    }

    // MARK: - undo is exact unit (no dangling gap)

    func testUndo_withGap_removesGapAndSegmentTogether() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // 거리가 먼 곳 C→D (gap B→C 라우팅됨)
        try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
        // undo → gap+segment 합쳐진 하나가 제거되어야 함
        session.undo()
        XCTAssertEqual(session.segments.count, 1, "gap이 병합됐으므로 undo 1번에 하나만 남아야 함")
        XCTAssertEqual(session.course?.coordinates.last, B)
    }
}

// MARK: - Stub

@MainActor
private final class StubCourseService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }
}
```

- [ ] **Step 1-3: 테스트 실행 — 실패 확인**

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' -only-testing:TraceTests/CourseEditSessionTests 2>&1 | tail -20
```
Expected: `CourseEditSession` 타입 없음 오류

- [ ] **Step 1-4: Application 폴더 생성 + CourseEditSession.swift 구현**

`Trace/Application/CoursePlanning/CourseEditSession.swift` 신규 생성:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class CourseEditSession {
    private(set) var segments: [CourseSegment] = []

    var course: PlannedCourse? {
        segments.isEmpty ? nil : PlannedCourse(segments: segments)
    }

    // 1 attach = 1 segment 추가 = undo 1번에 완전 제거
    func attach(
        _ newSegment: CourseSegment,
        using service: CoursePlanningServiceProtocol
    ) async throws {
        guard let existing = course,
              let existingStart = existing.coordinates.first,
              let existingEnd = existing.coordinates.last,
              let newStart = newSegment.coordinates.first,
              let newEnd = newSegment.coordinates.last else {
            segments.append(newSegment)
            return
        }

        let orientation = resolveOrientation(
            newStart: newStart, newEnd: newEnd,
            existingStart: existingStart, existingEnd: existingEnd
        )

        let oriented = orientation.needsReverse ? newSegment.reversed() : newSegment
        guard let orientedFirst = oriented.coordinates.first,
              let orientedLast = oriented.coordinates.last else { return }

        var combinedCoords = oriented.coordinates
        var combinedDistance = oriented.distanceMeters

        if orientation.attachesToEnd {
            if needsGap(from: existingEnd, to: orientedFirst) {
                let gap = try await service.route(from: existingEnd, to: orientedFirst)
                combinedCoords = gap.coordinates + Array(oriented.coordinates.dropFirst())
                combinedDistance += gap.distanceMeters
            }
            segments.append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
        } else {
            if needsGap(from: orientedLast, to: existingStart) {
                let gap = try await service.route(from: orientedLast, to: existingStart)
                combinedCoords = oriented.coordinates + Array(gap.coordinates.dropFirst())
                combinedDistance += gap.distanceMeters
            }
            segments.insert(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance), at: 0)
        }
    }

    func undo() {
        guard !segments.isEmpty else { return }
        segments.removeLast()
    }

    func clear() {
        segments = []
    }

    // MARK: - Private

    private struct AttachOrientation {
        let needsReverse: Bool
        let attachesToEnd: Bool
    }

    private func resolveOrientation(
        newStart: CourseCoordinate, newEnd: CourseCoordinate,
        existingStart: CourseCoordinate, existingEnd: CourseCoordinate
    ) -> AttachOrientation {
        let pairs: [(distance: Double, attachesToEnd: Bool, needsReverse: Bool)] = [
            (newStart.distanceMeters(to: existingEnd),   true,  false),
            (newEnd.distanceMeters(to: existingEnd),     true,  true),
            (newEnd.distanceMeters(to: existingStart),   false, false),
            (newStart.distanceMeters(to: existingStart), false, true),
        ]
        let closest = pairs.min(by: { $0.distance < $1.distance })!
        return AttachOrientation(needsReverse: closest.needsReverse, attachesToEnd: closest.attachesToEnd)
    }

    private func needsGap(from: CourseCoordinate, to: CourseCoordinate) -> Bool {
        from.distanceMeters(to: to) > 20
    }

    private func makeMerged(
        like original: CourseSegment,
        coordinates: [CourseCoordinate],
        distance: Double
    ) -> CourseSegment {
        switch original {
        case .tapped: return .tapped(coordinates: coordinates, distanceMeters: distance)
        case .drawn:  return .drawn(coordinates: coordinates, distanceMeters: distance)
        }
    }
}
```

- [ ] **Step 1-5: Xcode 프로젝트에 새 파일 등록**

Xcode에서:
1. `Trace/Application/CoursePlanning/` 폴더를 Project Navigator에서 생성
2. `CourseEditSession.swift`를 `Trace` 타겟에 추가 (Target Membership 체크)
3. `TraceTests/CourseEditSessionTests.swift`를 `TraceTests` 타겟에 추가

- [ ] **Step 1-6: 테스트 실행 — 통과 확인**

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' -only-testing:TraceTests/CourseEditSessionTests 2>&1 | tail -20
```
Expected: `Test Suite 'CourseEditSessionTests' passed`

- [ ] **Step 1-7: 커밋**

```bash
git add Trace/Domain/CoursePlanning/Entity/CourseSegment.swift \
        Trace/Application/CoursePlanning/CourseEditSession.swift \
        TraceTests/CourseEditSessionTests.swift \
        Trace.xcodeproj/project.pbxproj
git commit -m "feat: CourseEditSession Application 레이어 + reversed() 추가"
```
커밋 본문 (3-4줄):
```
CourseEditSession: attach/undo/clear + 방향 판단·gap 라우팅·병합 내부 처리
1 attach = 1 merged segment = undo 한 번에 완전 제거 보장 (dangling gap 없음)
CourseSegment.reversed(): 좌표 순서 반전 유지하며 케이스 보존
```

---

### Task 2: CoursePlannerPageViewModel 전면 교체

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `CourseEditSession.attach`, `CourseEditSession.undo`, `CourseEditSession.clear`, `CourseEditSession.course`
- Produces (public):
  - `var session: CourseEditSession` (let, package visible — tests need it)
  - `private(set) var pendingTapStart: CourseCoordinate?`
  - `var course: PlannedCourse?` (computed)
  - `var canUndo: Bool` (computed)
  - `func handleMapTap(at:) async`
  - `func toggleDrawingMode() async`
  - `func appendStroke(_:) async`
  - `func undoLastStroke() async`
  - `func clear()`
  - 제거됨: `startCoordinate`, `destinationCoordinate`

---

- [ ] **Step 2-1: 기존 ViewModel 테스트 중 제거할 테스트 파악**

아래 테스트는 동작이 근본적으로 바뀌므로 삭제:
- `testToggleToDrawAndBackWithoutDrawing_restoresTapPins` — `preDrawTapState` 없어짐

아래 테스트는 `await` 추가 + `startCoordinate`/`destinationCoordinate` 참조 제거 필요:
- `testToggleToDrawPreservesTapRouteAsHistory`
- `testClearResetsAllState`
- `testToggleDuringRouteCalculationDiscardsStaleCourse`
- `testDrawRouteIsPreservedAsCourseOnModeSwitch`
- `testClearAlsoResetsHistory`

- [ ] **Step 2-2: CoursePlannerPageViewModel 전면 교체**

`Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` 전체를 아래로 교체:

```swift
import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    // Application layer: mutable course being planned
    let session = CourseEditSession()

    // Tap mode: first tap waits here until second tap routes A→B
    private(set) var pendingTapStart: CourseCoordinate?

    // Draw mode: accumulated drawn strokes (no session seed — starts empty)
    private var accumulatedCoordinates: [CourseCoordinate] = []
    private var accumulatedDistance: Double = 0

    // Draw mode: per-stroke tracking for incremental undo
    private(set) var drawnStrokes: [[CourseCoordinate]] = []
    private(set) var strokeEntries: [StrokeEntry] = []

    // UI state
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private var recomputeGeneration = 0

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var canUndo: Bool {
        switch interactionMode {
        case .tap:  return !session.segments.isEmpty
        case .draw: return !drawnStrokes.isEmpty || !session.segments.isEmpty
        }
    }

    // Live course: session history + in-progress draw overlay
    // Draw mode에서 accumulatedCoordinates가 있으면 session 경로 뒤에 drawn 세그먼트를 붙여 표시
    var course: PlannedCourse? {
        if interactionMode == .draw, !accumulatedCoordinates.isEmpty {
            let drawn = CourseSegment.drawn(
                coordinates: accumulatedCoordinates,
                distanceMeters: accumulatedDistance
            )
            if let sessionCourse = session.course {
                return PlannedCourse(segments: sessionCourse.segments + [drawn])
            }
            return PlannedCourse(segments: [drawn])
        }
        return session.course
    }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    // MARK: - Location

    func bootstrapLocation() async {
        let hasRestoredCamera = cameraStateStore.restore() != nil
        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera { initialCameraCoordinate = location }
        } catch LocationError.denied {
            showLocationDeniedAlert = true
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        } catch {
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        }
    }

    func recenterToCurrentLocation() async -> CourseCoordinate? {
        try? await locationService.currentLocation()
    }

    // MARK: - Tap Mode

    func handleMapTap(at coordinate: CourseCoordinate) async {
        guard interactionMode == .tap else { return }

        if pendingTapStart == nil {
            // First tap: set pending start, show pin
            pendingTapStart = coordinate
            return
        }

        // Second tap: route start→coordinate then attach to session
        let start = pendingTapStart!
        pendingTapStart = nil

        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil

        do {
            let result = try await coursePlanningService.route(from: start, to: coordinate)
            guard generation == recomputeGeneration else { isLoading = false; return }
            let segment = CourseSegment.tapped(
                coordinates: result.coordinates,
                distanceMeters: result.distanceMeters
            )
            try await session.attach(segment, using: coursePlanningService)
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    // MARK: - Mode Toggle

    func toggleDrawingMode() async {
        switch interactionMode {
        case .tap:
            pendingTapStart = nil
            accumulatedCoordinates = []
            accumulatedDistance = 0
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw

        case .draw:
            if !accumulatedCoordinates.isEmpty {
                let drawnSegment = CourseSegment.drawn(
                    coordinates: accumulatedCoordinates,
                    distanceMeters: accumulatedDistance
                )
                do {
                    try await session.attach(drawnSegment, using: coursePlanningService)
                } catch {
                    errorMessage = "경로를 저장할 수 없습니다."
                }
            }
            drawnStrokes = []
            strokeEntries = []
            accumulatedCoordinates = []
            accumulatedDistance = 0
            recomputeGeneration += 1
            errorMessage = errorMessage  // attach 실패 시 에러 유지
            interactionMode = .tap
        }
    }

    // MARK: - Draw Mode

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        drawnStrokes.append(stroke)
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await incrementalRoute(rawStroke: stroke, generation: generation)
    }

    // MARK: - Undo / Clear

    func undoLastStroke() async {
        switch interactionMode {
        case .tap:
            session.undo()

        case .draw:
            guard strokeEntries.popLast() != nil else {
                // 그려진 스트로크 없음 → 직전 session 세그먼트 제거
                session.undo()
                return
            }
            drawnStrokes.removeLast()
            recomputeGeneration += 1

            if strokeEntries.isEmpty {
                accumulatedCoordinates = []
                accumulatedDistance = 0
                errorMessage = nil
            } else {
                recomputeGeneration += 1
                let generation = recomputeGeneration
                let savedStrokes = drawnStrokes
                strokeEntries = []
                accumulatedCoordinates = []
                accumulatedDistance = 0
                errorMessage = nil

                for stroke in savedStrokes {
                    await incrementalRoute(rawStroke: stroke, generation: generation)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                }
            }
        }
    }

    func clear() {
        recomputeGeneration += 1
        session.clear()
        pendingTapStart = nil
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Private

    private func incrementalRoute(rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        // 기존 drawn context 기준으로 방향 판단 (session 씨드 없음 — drawn 내부에서만 판단)
        let attachment = StrokeDirectionResolver.resolve(
            newStroke: sampled,
            existingCourseStart: accumulatedCoordinates.first,
            existingCourseEnd: accumulatedCoordinates.last
        )
        let oriented = attachment.orientedStroke

        isLoading = true
        errorMessage = nil

        do {
            var newCoords: [CourseCoordinate] = []
            var newDistance = 0.0
            for i in 0..<(oriented.count - 1) {
                let leg = try await coursePlanningService.route(from: oriented[i], to: oriented[i + 1])
                guard generation == recomputeGeneration else { isLoading = false; return }
                newCoords.append(contentsOf: newCoords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                newDistance += leg.distanceMeters
            }

            switch attachment.direction {
            case .initial:
                accumulatedCoordinates = newCoords
                accumulatedDistance = newDistance
            case .append:
                if let existingEnd = accumulatedCoordinates.last, let newStart = newCoords.first {
                    let connection = try await coursePlanningService.route(from: existingEnd, to: newStart)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                    accumulatedCoordinates.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters
                }
                accumulatedCoordinates.append(contentsOf: Array(newCoords.dropFirst()))
                accumulatedDistance += newDistance
            case .prepend:
                if let existingStart = accumulatedCoordinates.first, let newEnd = newCoords.last {
                    let connection = try await coursePlanningService.route(from: newEnd, to: existingStart)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                    var merged = newCoords
                    merged.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    merged.append(contentsOf: Array(accumulatedCoordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters + newDistance
                    accumulatedCoordinates = merged
                }
            }

            strokeEntries.append(StrokeEntry(
                orientedStroke: oriented,
                direction: attachment.direction,
                routedCoordinateCount: newCoords.count,
                routedDistance: newDistance
            ))
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
            drawnStrokes.removeLast()
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
            drawnStrokes.removeLast()
        }
        isLoading = false
    }
}
```

- [ ] **Step 2-3: CoursePlannerViewModelTests 업데이트**

`TraceTests/CoursePlannerViewModelTests.swift`를 아래로 교체:

```swift
import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT(locationError: Error? = nil) -> CoursePlannerPageViewModel {
        let locationService = StubLocationService()
        locationService.stubbedError = locationError
        let defaults = UserDefaults(suiteName: "viewModelTests")!
        defaults.removePersistentDomain(forName: "viewModelTests")
        return CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: locationService,
            cameraStateStore: CameraStateStore(defaults: defaults)
        )
    }

    // MARK: - Mode switching

    func testDefaultModeIsTap() {
        let sut = makeSUT()
        XCTAssertEqual(sut.interactionMode, .tap)
    }

    func testToggleToDrawPreservesTapRouteAsHistory() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNotNil(sut.course, "탭 경로가 session으로 보존되어야 함")
    }

    func testToggleToTapPreservesDrawnRouteAsHistory() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .tap)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNotNil(sut.course, "그리기 경로가 session으로 보존되어야 함")
    }

    func testClearResetsAllState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])

        sut.clear()

        XCTAssertNil(sut.pendingTapStart)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Location permission

    func testBootstrapSetsAlertOnDenied() async {
        let sut = makeSUT(locationError: LocationError.denied)
        await sut.bootstrapLocation()
        XCTAssertTrue(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    func testBootstrapNoAlertOnSuccess() async {
        let sut = makeSUT()
        await sut.bootstrapLocation()
        XCTAssertFalse(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Camera restore

    func testBootstrapDoesNotOverrideWhenCameraRestored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrap")!)
        UserDefaults(suiteName: "testBootstrap")!.removePersistentDomain(forName: "testBootstrap")
        store.save(latitude: 35.0, longitude: 129.0, latitudinalMeters: 1000, longitudinalMeters: 1000)

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNil(sut.initialCameraCoordinate)
    }

    func testBootstrapSetsCoordinateWhenNoCameraStored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrapEmpty")!)
        UserDefaults(suiteName: "testBootstrapEmpty")!.removePersistentDomain(forName: "testBootstrapEmpty")

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Tap accumulation (MVP6 핵심)

    func testFirstTap_setsPendingStart() async {
        let sut = makeSUT()
        let coord = CourseCoordinate(latitude: 37.5, longitude: 127.0)
        await sut.handleMapTap(at: coord)
        XCTAssertEqual(sut.pendingTapStart?.latitude, coord.latitude, accuracy: 0.0001)
        XCTAssertNil(sut.course, "첫 탭만으로 course가 생기면 안 됨")
    }

    func testSecondTap_routesAndCommitsToSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertEqual(sut.session.segments.count, 1)
        XCTAssertNotNil(sut.course)
    }

    func testMultipleTapPairs_accumulate() async {
        let sut = makeSUT()
        // 첫 번째 쌍: A→B
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // 두 번째 쌍: C→D
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2, "탭이 누적되어야 함 — 두 번째 쌍이 덮어쓰면 안 됨")
        XCTAssertNotNil(sut.course)
    }

    func testTapUndo_removesLastSegment() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2)

        await sut.undoLastStroke()
        XCTAssertEqual(sut.session.segments.count, 1)
    }

    // MARK: - Incremental stroke pipeline

    func testAppendStrokeNearEndAppendsAndRoutesOnlyNewSegment() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        let callsAfterFirst = service.routeCallCount

        service.routeCallCount = 0
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertTrue(service.routeCallCount < callsAfterFirst + 3)
        XCTAssertNotNil(sut.course)
    }

    func testAppendStrokeNearStartPrepends() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.509, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(sut.course)
        if let first = sut.course?.coordinates.first {
            XCTAssertTrue(abs(first.latitude - 37.500) < 0.005)
        }
    }

    // MARK: - Undo with session

    func testUndoAllStrokesRestoresHistory() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let tapDistance = sut.course?.distanceMeters ?? 0

        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.undoLastStroke()

        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters ?? 0, tapDistance, accuracy: 1)
    }

    func testClearAlsoResetsSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        await sut.toggleDrawingMode()
        XCTAssertNotNil(sut.course)

        sut.clear()

        XCTAssertNil(sut.course)
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
    }

    func testUndoRemovesLastAddedStroke() async {
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.undoLastStroke()

        XCTAssertEqual(sut.drawnStrokes.count, 1)
        XCTAssertNotNil(sut.course)
    }

    func testThrottleErrorShowsUserMessage() async {
        let service = StubCoursePlanningService()
        service.stubbedError = CoursePlanningError.throttled
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.errorMessage, "요청이 많아 잠시 후 다시 시도해주세요")
    }

    // MARK: - Debounce

    func testRapidStrokesDebounceRecompute() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ])

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.drawnStrokes.count, 2)
    }

    // MARK: - Race condition

    func testToggleDuringRouteCalculationDiscardsStaleCourse() async {
        let service = BlockingCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        XCTAssertNotNil(sut.pendingTapStart)

        let calculateTask = Task {
            await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        }

        await service.waitUntilRouteEntered()

        await sut.toggleDrawingMode()
        XCTAssertEqual(sut.interactionMode, .draw)
        // draw 전환 시 session에 아직 아무것도 없으면 course = nil
        XCTAssertNil(sut.course)

        service.resumeRoute()
        await calculateTask.value

        XCTAssertNil(sut.course)
    }

    // MARK: - Path stitching

    func testTapRouteIsPreservedWhenEnteringDrawMode() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let tapCourse = sut.course
        XCTAssertNotNil(tapCourse)

        await sut.toggleDrawingMode()

        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters, tapCourse?.distanceMeters)
    }

    func testDrawRouteIsPreservedWhenEnteringTapMode() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        let drawCourse = sut.course
        XCTAssertNotNil(drawCourse)

        await sut.toggleDrawingMode()

        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters, drawCourse?.distanceMeters, accuracy: 1)
    }

    func testDrawRouteIsPreservedAsCourseOnModeSwitch() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNotNil(sut.course)
    }

    func testDrawNearRouteStartPrependsCorrectly() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.49, longitude: 127.00),
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(sut.course)
        if let first = sut.course?.coordinates.first {
            XCTAssertTrue(first.latitude < 37.505, "출발이 A(37.50) 이전으로 prepend 되어야 함")
        }
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubCoursePlanningService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    var stubbedResult: PlannedCourse?
    var stubbedError: Error?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedResult ?? PlannedCourse(
            segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
        )
    }
}

@MainActor
private final class BlockingCoursePlanningService: CoursePlanningServiceProtocol {
    private var routeEnteredContinuation: CheckedContinuation<Void, Never>?
    private var routeReleaseContinuation: CheckedContinuation<Void, Never>?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        if let continuation = routeEnteredContinuation {
            continuation.resume()
            routeEnteredContinuation = nil
        }
        await withCheckedContinuation { continuation in
            routeReleaseContinuation = continuation
        }
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }

    func waitUntilRouteEntered() async {
        await withCheckedContinuation { continuation in
            routeEnteredContinuation = continuation
        }
    }

    func resumeRoute() {
        routeReleaseContinuation?.resume()
        routeReleaseContinuation = nil
    }
}

@MainActor
private final class StubLocationService: LocationServiceProtocol {
    var stubbedLocation: CourseCoordinate? = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    var stubbedError: Error?

    func currentLocation() async throws -> CourseCoordinate {
        if let error = stubbedError { throw error }
        return stubbedLocation!
    }
}
```

- [ ] **Step 2-4: 빌드 확인**

```bash
xcodebuild build -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 2-5: ViewModel 테스트 실행**

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' -only-testing:TraceTests/CoursePlannerViewModelTests 2>&1 | tail -30
```
Expected: 모든 테스트 통과

- [ ] **Step 2-6: 전체 테스트 실행**

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 | tail -20
```
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 2-7: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift \
        TraceTests/CoursePlannerViewModelTests.swift
git commit -m "feat: ViewModel 교체 — session 도입 + 탭 누적 + undo 통합"
```
커밋 본문 (3-4줄):
```
history/preDrawTapState/startCoordinate/destinationCoordinate 제거
session + pendingTapStart로 교체; handleMapTap이 session.attach 호출
toggleDrawingMode async 전환; undoLastStroke가 탭·그리기 모드 모두 처리
course computed property로 전환 — session + accumulated 실시간 합성
```

---

### Task 3: View 업데이트

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`

**Interfaces:**
- Consumes: `viewModel.pendingTapStart` (대신 `startCoordinate`)
- Consumes: `viewModel.canUndo` (새 computed property)
- Consumes: `await viewModel.toggleDrawingMode()` (이제 async)
- Consumes: `await viewModel.undoLastStroke()` (tap 모드에서도 동작)

---

- [ ] **Step 3-1: CoursePlannerPage.swift — mapPins 업데이트**

`CoursePlannerPage.swift`의 `mapPins` 계산 프로퍼티에서 `startCoordinate` → `pendingTapStart`:

```swift
// 변경 전 (137번째 줄 근처):
} else if viewModel.interactionMode == .tap {
    if let start = viewModel.startCoordinate {

// 변경 후:
} else if viewModel.interactionMode == .tap {
    if let start = viewModel.pendingTapStart {
```

- [ ] **Step 3-2: CoursePlannerPage+ControlsComponent.swift — async + undo 통합**

`UIComponent/CoursePlannerPage+ControlsComponent.swift` 전체를 아래로 교체:

```swift
import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleDrawingMode() }
            } label: {
                Label(
                    viewModel.isDrawingMode ? "그리기" : "경로 찍기",
                    systemImage: viewModel.isDrawingMode ? "pencil.tip" : "mappin.and.ellipse"
                )
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("coursePlanner.undo")

            Button("초기화") { viewModel.clear() }
                .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
```

주요 변경:
- `toggleDrawingMode()` → `Task { await viewModel.toggleDrawingMode() }`
- 되돌리기 버튼: `if viewModel.isDrawingMode` 조건 제거 → 항상 표시, `disabled(!viewModel.canUndo)`
- 초기화 disabled: `startCoordinate == nil` → `pendingTapStart == nil`

- [ ] **Step 3-3: 빌드 확인**

```bash
xcodebuild build -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 3-4: 시뮬레이터 실행 + 골든 패스 검증**

XcodeBuildMCP 또는 다음 명령으로 앱 실행:
```bash
xcodebuild build-for-testing -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.5' 2>&1 | tail -5
```

시뮬레이터에서 수동으로 확인할 시나리오:
1. **탭 누적**: 탭 모드에서 A→B 탭 → 코스 표시 → C→D 탭 → 두 코스가 이어져서 표시되어야 함
2. **탭↔그리기 연결**: A→B 탭 후 그리기 모드 전환 → B 근처 그리기 → 탭 복귀 → 이어진 코스 확인
3. **탭 모드 되돌리기**: 탭 코스 2개 만든 후 되돌리기 → 1개로 줄어야 함
4. **되돌리기 버튼 탭 모드 표시**: 코스가 있을 때 탭 모드에서도 되돌리기 버튼이 활성화되어야 함
5. **초기화**: 어느 모드에서든 초기화 → 경로/상태 완전 리셋 확인

- [ ] **Step 3-5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift \
        Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
git commit -m "feat: View 업데이트 — pendingTapStart 핀 + undo 버튼 통합"
```
커밋 본문 (3-4줄):
```
mapPins에서 startCoordinate → pendingTapStart로 교체
되돌리기 버튼을 그리기 모드 전용에서 canUndo 기반 항상 표시로 변경
toggleDrawingMode가 async로 바뀌어 Task { await } 래핑 추가
초기화 disabled 조건도 pendingTapStart 기준으로 통일
```

---

## 자체 검토 결과

### 1. 스펙 커버리지

| 스펙 요구사항 | 구현 위치 |
|---|---|
| 탭 연속 이어붙이기 | Task 2: `handleMapTap` → `pendingTapStart` + `session.attach` |
| 탭↔그리기 자동 연결 | Task 1: `session.attach` 방향 판단·gap 라우팅 |
| undo 통합 (탭+그리기) | Task 2: `undoLastStroke()` — 모드 분기 처리 |
| clear 통합 | Task 2: `clear()` — `session.clear()` 호출 |
| dangling gap 버그 수정 | Task 1: gap + 새 세그먼트를 merged 1개로 병합 |
| draw prepend delta 버그 수정 | Task 2: `accumulatedCoordinates` 씨드 없이 시작, `session.attach` 처리 |
| 되돌리기 버튼 탭 모드 표시 | Task 3: `canUndo` 기반 항상 표시 |
| `preDrawTapState` 제거 | Task 2: ViewModel 전면 교체 |

### 2. 플레이스홀더 없음 ✅

### 3. 타입 일관성 확인

- `CourseEditSession.attach` 파라미터: `CourseSegment`, `CoursePlanningServiceProtocol` ✅
- `session.undo()`, `session.clear()` 시그니처 Task 1↔2 일치 ✅
- `pendingTapStart: CourseCoordinate?` — Task 2 ViewModel, Task 3 View 모두 동일 ✅
- `canUndo: Bool` — Task 2 정의, Task 3 소비 ✅

### 4. 주의사항

**`course` computed property의 Observation 동작**: `course`가 `session.segments`와 `accumulatedCoordinates`를 읽는 computed property이므로, View body 실행 중 두 값 모두 observation 의존성으로 등록된다. `@Observable` Observation 프레임워크는 런타임 접근 추적 기반이므로 정상 동작한다. 만약 View가 갱신되지 않으면: `course`를 stored property로 변경하고 `session`/`accumulatedCoordinates` 변경 시 명시적으로 갱신한다.

**draw 모드 중 session-to-draw 연결 실시간 표시 없음**: `accumulatedCoordinates`가 session 씨드 없이 시작하므로, draw 중 session 경로와 그린 경로 사이에 시각적 gap이 있다. 종료 시 `session.attach`가 올바르게 연결한다. 이는 MVP6 범위 내 허용된 UX 트레이드오프이며 향후 개선 가능하다.
