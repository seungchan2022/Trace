# MVP5 Implementation Plan — path-stitching + two-finger-pan-ux + test-ios-versions

> **완료(소급 확인) — 근거 커밋:** `1118d86`~`f7ba4b4` (feature/mvp5-path-stitching). 63/63 테스트 통과 + 실기기 QA 확인.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 탭↔그리기 경로를 이어붙이는 세그먼트 모델을 도입하고, 그리기 모드 두 손가락 UX 버그 3개를 수정하며, iOS 버전별 테스트 크래시 원인을 규명한다.

**Architecture:** ViewModel에 `history: [CourseSegment]`를 추가해 완료된 세션을 봉인하고, `course: PlannedCourse?`를 `history + 현재 세션`으로 명시적으로 재구성한다. `PlannedCourse`는 `segments: [CourseSegment]`를 갖고 `coordinates`/`distanceMeters`를 computed property로 제공한다.

**Tech Stack:** Swift 6, SwiftUI + UIViewRepresentable(MKMapView), `@Observable` + `@MainActor`, XCTest

## Global Constraints

- iOS 17+ (최소 지원 버전)
- `@Observable` + `@MainActor` 패턴 유지 — `ObservableObject` / `@Published` 사용 금지
- `nonisolated deinit {}` 추가 금지 (test-ios-versions 리서치 전에 임의 적용 금지)
- `git add -A` 금지; 파일 경로 명시 스테이징
- 커밋은 사용자가 요청할 때만

---

## 파일 구조

| 파일 | 변경 |
|---|---|
| `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift` | **신규** |
| `Trace/Domain/CoursePlanning/Entity/PlannedCourse.swift` | **수정** — segments 기반으로 전환 |
| `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` | **수정** — PlannedCourse 생성자 변경 |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` | **수정** — history + mode transition + undo + clear |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift` | **수정** — clear 비활성 조건 갱신 |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` | **수정** — 두 손가락 pan + pitch/rotate + 그리기 오염 |
| `TraceTests/CourseSegmentTests.swift` | **신규** |
| `TraceTests/CoursePlannerViewModelTests.swift` | **수정** — 스텁 업데이트 + 기존 테스트 수정 + 새 테스트 |

---

## Task 1: CourseSegment 엔티티

**Files:**
- Create: `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift`
- Create: `TraceTests/CourseSegmentTests.swift`

**Interfaces:**
- Produces: `CourseSegment` enum (`.tapped(coordinates:distanceMeters:)`, `.drawn(coordinates:distanceMeters:)`) + `coordinates: [CourseCoordinate]`, `distanceMeters: Double` computed props

- [ ] **Step 1: Write failing tests**

```swift
// TraceTests/CourseSegmentTests.swift
import XCTest
@testable import Trace

final class CourseSegmentTests: XCTestCase {
    private let a = CourseCoordinate(latitude: 37.5, longitude: 127.0)
    private let b = CourseCoordinate(latitude: 37.6, longitude: 127.0)

    func testTappedCoordinates() {
        let seg = CourseSegment.tapped(coordinates: [a, b], distanceMeters: 100)
        XCTAssertEqual(seg.coordinates, [a, b])
    }

    func testTappedDistance() {
        let seg = CourseSegment.tapped(coordinates: [a, b], distanceMeters: 500)
        XCTAssertEqual(seg.distanceMeters, 500)
    }

    func testDrawnCoordinates() {
        let seg = CourseSegment.drawn(coordinates: [a, b], distanceMeters: 200)
        XCTAssertEqual(seg.coordinates, [a, b])
    }

    func testDrawnDistance() {
        let seg = CourseSegment.drawn(coordinates: [a, b], distanceMeters: 200)
        XCTAssertEqual(seg.distanceMeters, 200)
    }

    func testEquality() {
        let seg1 = CourseSegment.tapped(coordinates: [a], distanceMeters: 100)
        let seg2 = CourseSegment.tapped(coordinates: [a], distanceMeters: 100)
        XCTAssertEqual(seg1, seg2)
    }
}
```

- [ ] **Step 2: 테스트 실행 — FAIL 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing TraceTests/CourseSegmentTests 2>&1 | tail -20
```

Expected: `CourseSegment` not found 오류

- [ ] **Step 3: CourseSegment 구현**

```swift
// Trace/Domain/CoursePlanning/Entity/CourseSegment.swift
import Foundation

enum CourseSegment: Equatable, Sendable {
    case tapped(coordinates: [CourseCoordinate], distanceMeters: Double)
    case drawn(coordinates: [CourseCoordinate], distanceMeters: Double)

    var coordinates: [CourseCoordinate] {
        switch self {
        case .tapped(let coords, _), .drawn(let coords, _): return coords
        }
    }

    var distanceMeters: Double {
        switch self {
        case .tapped(_, let d), .drawn(_, let d): return d
        }
    }
}
```

- [ ] **Step 4: 테스트 재실행 — PASS 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing TraceTests/CourseSegmentTests 2>&1 | tail -10
```

Expected: `Test Suite 'CourseSegmentTests' passed`

---

## Task 2: PlannedCourse → segments 기반으로 전환

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Entity/PlannedCourse.swift`
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift` (StubCoursePlanningService, BlockingCoursePlanningService)

**Interfaces:**
- Consumes: `CourseSegment` (Task 1)
- Produces: `PlannedCourse(segments:)` init, `coordinates: [CourseCoordinate]`, `distanceMeters: Double` (computed)

- [ ] **Step 1: PlannedCourse 수정**

`Trace/Domain/CoursePlanning/Entity/PlannedCourse.swift`를 아래로 교체:

```swift
import Foundation

struct PlannedCourse: Equatable, Sendable {
    var segments: [CourseSegment]

    // 세그먼트 사이 첫 좌표 중복 제거: i>0이면 첫 좌표를 dropFirst
    var coordinates: [CourseCoordinate] {
        segments.enumerated().flatMap { i, seg in
            i == 0 ? seg.coordinates : Array(seg.coordinates.dropFirst())
        }
    }

    var distanceMeters: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }
}
```

- [ ] **Step 2: MapKitCoursePlanningService 업데이트**

`MapKitCoursePlanningService.swift`에서 `PlannedCourse` 생성 부분을 수정:

```swift
// 수정 전:
let result = PlannedCourse(
    coordinates: coordinates.map(CourseCoordinate.init),
    distanceMeters: route.distance
)

// 수정 후:
let result = PlannedCourse(
    segments: [.tapped(
        coordinates: coordinates.map(CourseCoordinate.init),
        distanceMeters: route.distance
    )]
)
```

- [ ] **Step 3: 테스트 스텁 업데이트**

`TraceTests/CoursePlannerViewModelTests.swift`의 `StubCoursePlanningService.route()` 수정:

```swift
// 수정 전:
return stubbedResult ?? PlannedCourse(
    coordinates: [start, destination],
    distanceMeters: 100
)

// 수정 후:
return stubbedResult ?? PlannedCourse(
    segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
)
```

`BlockingCoursePlanningService.route()` 수정:

```swift
// 수정 전:
return PlannedCourse(coordinates: [start, destination], distanceMeters: 100)

// 수정 후:
return PlannedCourse(
    segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
)
```

- [ ] **Step 4: 빌드 확인 (컴파일 에러 제로)**

```bash
xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 5: 기존 테스트 실행 — 현재 통과 범위 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "passed|failed|error"
```

이 시점에서 `testToggleToDrawClearsTapState`, `testToggleToTapClearsDrawState` 등 기존 행동 변경 테스트는 ViewModel 미수정으로 여전히 통과한다. Task 3에서 ViewModel을 바꾸면 실패로 전환된다.

---

## Task 3: ViewModel — history 추가 + toggleDrawingMode 재작성

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `CourseSegment` (Task 1), `PlannedCourse(segments:)` (Task 2)
- Produces: `private var history: [CourseSegment]` — 완료된 세션의 봉인된 배열

**설계 요점:**
- `history` = 이전 세션(탭 또는 그리기)에서 완료·봉인된 세그먼트 배열
- `course` = `history + 현재 세션`으로 명시적으로 설정 (computed property가 아닌 stored)
- 탭→그리기: `course.segments.dropFirst(history.count)` 로 현재 세션 탭 leg만 추출해 history에 append; `accumulatedCoordinates`를 history 끝점으로 seed
- 그리기→탭: `accumulatedCoordinates`를 `.drawn` 세그먼트로 history에 append; `startCoordinate`를 마지막 좌표로 설정

- [ ] **Step 1: 기존 행동 변경 테스트 업데이트**

`TraceTests/CoursePlannerViewModelTests.swift`에서 아래 두 테스트를 수정 (ViewModel 수정 전에 기대값 먼저 확정):

```swift
// testToggleToDrawClearsTapState 수정
// 탭 경로가 있는 상태에서 그리기 전환 시 course가 보존된다
func testToggleToDrawPreservesTapRouteAsHistory() async {
    let sut = makeSUT()
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
    XCTAssertNotNil(sut.course)

    sut.toggleDrawingMode()

    XCTAssertEqual(sut.interactionMode, .draw)
    XCTAssertNil(sut.startCoordinate)
    XCTAssertNil(sut.destinationCoordinate)
    XCTAssertNotNil(sut.course, "탭 경로가 history로 보존되어야 함")
}

// testToggleToTapClearsDrawState 수정
// 그리기 후 탭 전환 시 drawnStrokes는 초기화되지만 course는 보존된다
func testToggleToTapPreservesDrawnRouteAsHistory() async {
    let sut = makeSUT()
    sut.toggleDrawingMode()
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertNotNil(sut.course)

    sut.toggleDrawingMode()

    XCTAssertEqual(sut.interactionMode, .tap)
    XCTAssertTrue(sut.drawnStrokes.isEmpty)
    XCTAssertNotNil(sut.course, "그리기 경로가 history로 보존되어야 함")
}
```

기존 `testToggleToDrawClearsTapState`, `testToggleToTapClearsDrawState` 함수명을 위 함수명으로 교체(내용 포함).

- [ ] **Step 2: 이어붙이기 시나리오 새 테스트 추가**

```swift
// testToggleDuringRouteCalculationDiscardsStaleCourse 아래에 추가

// MARK: - Path stitching

func testTapRouteIsPreservedWhenEnteringDrawMode() async {
    let sut = makeSUT()
    // 탭으로 A→B 생성
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    try? await Task.sleep(nanoseconds: 100_000_000)
    let tapCourse = sut.course
    XCTAssertNotNil(tapCourse)

    // 그리기 모드 전환
    sut.toggleDrawingMode()

    // 탭 경로가 course에 보존되어야 함
    XCTAssertNotNil(sut.course)
    XCTAssertEqual(sut.course?.distanceMeters, tapCourse?.distanceMeters)
}

func testDrawRouteIsPreservedWhenEnteringTapMode() async {
    let sut = makeSUT()
    sut.toggleDrawingMode()
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)
    let drawCourse = sut.course
    XCTAssertNotNil(drawCourse)

    // 탭 모드 전환
    sut.toggleDrawingMode()

    // 그리기 경로가 course에 보존되어야 함
    XCTAssertNotNil(sut.course)
    XCTAssertEqual(sut.course?.distanceMeters, drawCourse?.distanceMeters)
}

func testStartCoordinateIsSetFromDrawnRouteEndOnModeSwitch() async {
    let sut = makeSUT()
    sut.toggleDrawingMode()
    let endPoint = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        endPoint,
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    sut.toggleDrawingMode()

    // startCoordinate가 그리기 끝점 근처로 설정되어야 함
    XCTAssertNotNil(sut.startCoordinate)
}
```

- [ ] **Step 3: 테스트 실행 — 새 테스트 FAIL 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing TraceTests/CoursePlannerViewModelTests/testTapRouteIsPreservedWhenEnteringDrawMode -only-testing TraceTests/CoursePlannerViewModelTests/testDrawRouteIsPreservedWhenEnteringTapMode 2>&1 | tail -15
```

Expected: FAIL (ViewModel 미수정)

- [ ] **Step 4: ViewModel에 history 추가 및 toggleDrawingMode 재작성**

`CoursePlannerPageViewModel.swift`에서:

1. 클래스 상단에 프로퍼티 추가:
```swift
private var history: [CourseSegment] = []
```

2. `toggleDrawingMode()` 전체 교체:
```swift
func toggleDrawingMode() {
    switch interactionMode {
    case .tap:
        // 현재 탭 세션의 leg를 history에 봉인
        if let course {
            let sessionSegments = Array(course.segments.dropFirst(history.count))
            history.append(contentsOf: sessionSegments)
        }
        // history 끝점을 그리기 시작점으로 seed
        if let lastCoord = history.last?.coordinates.last {
            accumulatedCoordinates = [lastCoord]
        } else {
            accumulatedCoordinates = []
        }
        accumulatedDistance = 0
        startCoordinate = nil
        destinationCoordinate = nil
        recomputeGeneration += 1
        errorMessage = nil
        isLoading = false
        interactionMode = .draw
        course = history.isEmpty ? nil : PlannedCourse(segments: history)

    case .draw:
        // 현재 그리기 세션을 history에 봉인
        if !accumulatedCoordinates.isEmpty {
            history.append(.drawn(
                coordinates: accumulatedCoordinates,
                distanceMeters: accumulatedDistance
            ))
        }
        startCoordinate = accumulatedCoordinates.last
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        recomputeGeneration += 1
        errorMessage = nil
        interactionMode = .tap
        course = history.isEmpty ? nil : PlannedCourse(segments: history)
    }
}
```

- [ ] **Step 5: 새 테스트 재실행 — PASS 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing TraceTests/CoursePlannerViewModelTests 2>&1 | grep -E "passed|failed|Test Suite"
```

Expected: `CoursePlannerViewModelTests` suite passed

---

## Task 4: ViewModel — calculateCourse + incrementalRoute (segments 반영)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`

**설계 요점:**
- `calculateCourse()`: 서비스가 반환한 leg를 `history + [.tapped(leg)]`로 `course` 재구성
- `incrementalRoute()`: 누적 완료 시 `history + [.drawn(accumulatedCoordinates)]`로 `course` 재구성

- [ ] **Step 1: handleMapTap 수정**

`handleMapTap`의 첫 번째 분기(새 startCoordinate 설정 시)에서 `course = nil` → history 유지로 교체:

```swift
// 수정 전:
course = nil

// 수정 후:
course = history.isEmpty ? nil : PlannedCourse(segments: history)
```

- [ ] **Step 2: calculateCourse 수정**

`private func calculateCourse()` 내 course 할당 부분만 교체:

```swift
// 수정 전:
course = route

// 수정 후:
let tap = CourseSegment.tapped(
    coordinates: route.coordinates,
    distanceMeters: route.distanceMeters
)
course = PlannedCourse(segments: history + [tap])
```

또한 로딩 시작 시 history 표시 유지:
```swift
// 수정 전:
course = nil

// 수정 후 (isLoading = true 바로 아래):
course = history.isEmpty ? nil : PlannedCourse(segments: history)
```

- [ ] **Step 2: incrementalRoute 수정**

`private func incrementalRoute(rawStroke:generation:)` 내 마지막 course 할당 교체:

```swift
// 수정 전 (incrementalRoute 마지막 성공 경로):
course = PlannedCourse(coordinates: accumulatedCoordinates, distanceMeters: accumulatedDistance)

// 수정 후:
let drawn = CourseSegment.drawn(
    coordinates: accumulatedCoordinates,
    distanceMeters: accumulatedDistance
)
course = PlannedCourse(segments: history + [drawn])
```

- [ ] **Step 4: 빌드 + 기존 테스트 전체 실행**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "passed|failed|Test Suite"
```

Expected: 전체 suite passed

---

## Task 5: ViewModel — undoLastStroke + clear + UI 조건 갱신

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**설계 요점:**
- `undoLastStroke()`: 모든 stroke 제거 후 `accumulatedCoordinates`를 history 끝점으로 re-seed (다음 그리기가 history에서 이어지도록)
- `clear()`: `history = []` 추가
- clear 버튼 비활성 조건: `course == nil && startCoordinate == nil`

- [ ] **Step 1: undo 테스트 추가**

```swift
// MARK: - Undo with history

func testUndoAllStrokesRestoresHistory() async {
    let sut = makeSUT()
    // tap A→B
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    try? await Task.sleep(nanoseconds: 100_000_000)
    let tapDistance = sut.course?.distanceMeters ?? 0

    // draw B→C
    sut.toggleDrawingMode()
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
        CourseCoordinate(latitude: 37.52, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    // undo drawn stroke
    await sut.undoLastStroke()

    // history(탭 경로)만 남아야 함
    XCTAssertTrue(sut.drawnStrokes.isEmpty)
    // course는 history(탭) 기반으로 존재해야 함
    XCTAssertNotNil(sut.course)
    XCTAssertEqual(sut.course?.distanceMeters ?? 0, tapDistance, accuracy: 1)
}

func testClearAlsoResetsHistory() async {
    let sut = makeSUT()
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    try? await Task.sleep(nanoseconds: 100_000_000)
    sut.toggleDrawingMode()
    XCTAssertNotNil(sut.course)

    sut.clear()

    XCTAssertNil(sut.course)
    XCTAssertNil(sut.startCoordinate)
    XCTAssertTrue(sut.drawnStrokes.isEmpty)
}
```

- [ ] **Step 2: 테스트 실행 — FAIL 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing TraceTests/CoursePlannerViewModelTests/testUndoAllStrokesRestoresHistory -only-testing TraceTests/CoursePlannerViewModelTests/testClearAlsoResetsHistory 2>&1 | tail -15
```

Expected: FAIL

- [ ] **Step 3: undoLastStroke 수정**

```swift
func undoLastStroke() async {
    guard strokeEntries.popLast() != nil else { return }
    drawnStrokes.removeLast()
    recomputeGeneration += 1

    if strokeEntries.isEmpty {
        accumulatedCoordinates = []
        accumulatedDistance = 0
        // history 끝점으로 re-seed (다음 그리기가 history에서 이어지도록)
        if let lastCoord = history.last?.coordinates.last {
            accumulatedCoordinates = [lastCoord]
        }
        course = history.isEmpty ? nil : PlannedCourse(segments: history)
        errorMessage = nil
    } else {
        recomputeGeneration += 1
        let generation = recomputeGeneration
        let savedStrokes = drawnStrokes
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        if let lastCoord = history.last?.coordinates.last {
            accumulatedCoordinates = [lastCoord]
        }
        course = history.isEmpty ? nil : PlannedCourse(segments: history)
        errorMessage = nil

        for stroke in savedStrokes {
            await incrementalRoute(rawStroke: stroke, generation: generation)
            guard generation == recomputeGeneration else { isLoading = false; return }
        }
    }
}
```

- [ ] **Step 4: clear 수정**

`clear()` 함수에 `history = []` 추가:

```swift
func clear() {
    recomputeGeneration += 1
    history = []          // 추가
    startCoordinate = nil
    destinationCoordinate = nil
    drawnStrokes = []
    strokeEntries = []
    accumulatedCoordinates = []
    accumulatedDistance = 0
    course = nil
    errorMessage = nil
    isLoading = false
}
```

- [ ] **Step 5: ControlsComponent clear 비활성 조건 수정**

`CoursePlannerPage+ControlsComponent.swift`의 clear Button에서:

```swift
// 수정 전:
.disabled(
    viewModel.startCoordinate == nil
    && viewModel.drawnStrokes.isEmpty
)

// 수정 후:
.disabled(viewModel.course == nil && viewModel.startCoordinate == nil)
```

- [ ] **Step 6: 테스트 재실행 — PASS 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "passed|failed|Test Suite"
```

Expected: 전체 suite passed

---

## Task 6: MapView — 두 손가락 pan 방향 수정 + pitch/rotate 비활성화

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`

**수정 위치:**
1. `handleTwoFingerPan` — 위도/경도 양축 부호 반전
2. `updateUIView` — 그리기 모드 진입 시 `isPitchEnabled`, `isRotateEnabled` 동기화

- [ ] **Step 1: handleTwoFingerPan 부호 수정**

`handleTwoFingerPan` 내 `newCenter` 계산 부분:

```swift
// 수정 전:
let newCenter = CLLocationCoordinate2D(
    latitude: startCenter.latitude - translation.y * latPerPoint,
    longitude: startCenter.longitude + translation.x * lonPerPoint
)

// 수정 후 (손가락 밑 지점이 손가락을 따라오는 불변식: 양축 부호 반전):
let newCenter = CLLocationCoordinate2D(
    latitude: startCenter.latitude + translation.y * latPerPoint,
    longitude: startCenter.longitude - translation.x * lonPerPoint
)
```

- [ ] **Step 2: updateUIView에 pitch/rotate 동기화 추가**

`updateUIView`의 "제스처 모드 동기화" 블록에 두 줄 추가:

```swift
// 수정 전:
if wasDrawing != isDrawingMode {
    uiView.isScrollEnabled = !isDrawingMode
    uiView.isZoomEnabled = !isDrawingMode
    context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.pinchGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
}

// 수정 후:
if wasDrawing != isDrawingMode {
    uiView.isScrollEnabled = !isDrawingMode
    uiView.isZoomEnabled = !isDrawingMode
    uiView.isPitchEnabled = !isDrawingMode      // 추가: 3D 틸트 방지
    uiView.isRotateEnabled = !isDrawingMode     // 추가: 회전 방지
    context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.pinchGestureRecognizer?.isEnabled = isDrawingMode
    context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
}
```

- [ ] **Step 3: 빌드 확인**

```bash
xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: 실기기 검증 (수동)**

실기기에서 그리기 모드 진입 후:
- 두 손가락을 오른쪽으로 밀면 지도가 오른쪽으로 이동하는지 확인 (경도 수정)
- 두 손가락을 위로 밀면 지도가 위로 이동하는지 확인 (위도 수정)
- 두 손가락 드래그 시 3D 틸트가 없는지 확인
- 두 손가락 비틀기 시 지도가 회전하지 않는지 확인

위도 방향이 여전히 반대라면 `+ translation.y` → `- translation.y`로 수정.

---

## Task 7: MapView — 그리기 오염 수정 (두 번째 손가락 도착 전 stroke 시작)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`

**문제:** `drawGR.maximumNumberOfTouches = 1`이지만 두 번째 손가락이 닿기 전 짧은 시간에 그리기가 시작될 수 있음.

- [ ] **Step 1: handleDraw에 touch count 확인 추가**

`handleDraw` 함수 내 `.began` case에 guard 추가:

```swift
@objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
    guard let mapView = recognizer.view as? MKMapView else { return }
    
    // 두 번째 손가락이 들어오면 진행 중인 stroke 취소
    if recognizer.numberOfTouches > 1 {
        currentStrokePoints = []
        currentStrokeCoords = []
        parent.onStrokeUpdate([])
        recognizer.state = .cancelled  // GR을 cancelled로 강제 전환
        return
    }
    
    let point = recognizer.location(in: mapView)
    let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
    let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

    switch recognizer.state {
    case .began, .changed:
        currentStrokePoints.append(point)
        currentStrokeCoords.append(coord)
        parent.onStrokeUpdate(currentStrokePoints)
    case .ended, .cancelled:
        currentStrokePoints.append(point)
        currentStrokeCoords.append(coord)
        let stroke = currentStrokeCoords
        currentStrokePoints = []
        currentStrokeCoords = []
        parent.onStrokeUpdate([])
        if stroke.count >= 2 {
            parent.onStrokeEnded(stroke)
        }
    default:
        break
    }
}
```

- [ ] **Step 2: 빌드 + 테스트 확인**

```bash
xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "passed|failed|Test Suite"
```

Expected: 전체 suite passed

- [ ] **Step 3: 실기기 검증 (수동)**

그리기 모드에서 한 손가락으로 그리다가 두 번째 손가락을 올릴 때 stroke가 취소되고 두 손가락 pan으로 전환되는지 확인.

---

## Task 8: test-ios-versions 리서치

**Files:**
- Modify: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md` (리서치 완료 후)

**현황:** iOS 18.x 시뮬레이터에서 `@Observable` + `@MainActor` ViewModel의 XCTest 실행 시 malloc 크래시 발생. 현재 iOS 26.5로 우회 중. 원인은 경험적 관찰에 기반하며 공식 확인 안 됨.

**수행 흐름:**

- [ ] **Step 1: 리서치 — Swift 공식 채널**

아래 소스에서 검색어 `@Observable malloc crash XCTest iOS 18` / `Observable MainActor XCTest crash` / `swift observation deinit crash`:
- Swift 이슈 트래커: `github.com/swiftlang/swift/issues`
- Swift Forums: `forums.swift.org`
- Xcode Release Notes (18.x 계열)
- Apple Developer Forums

확인 목표:
1. 이 크래시가 알려진 버그로 보고됐는지 (이슈 번호 확인)
2. Swift/iOS 어느 버전에서 수정됐는지 (official fix commit 또는 release note)
3. `nonisolated deinit {}` 가 커뮤니티에서 유효한 mitigation으로 검증됐는지

- [ ] **Step 2: 원인 확정 및 문서 업데이트**

리서치 결과에 따라 `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`를 팩트 기반으로 갱신:
- 이슈 URL, 수정 버전, 검증된 mitigation 등 출처 명시
- 경험적 관찰 표기를 사실로 확인된 내용으로 교체

- [ ] **Step 3: 수정 방법 결정**

리서치 결과에 따라:
- **우리 코드로 근본 수정 가능**: 수정 적용 → iOS 18 시뮬레이터에서 테스트 통과 확인
- **Apple 런타임 버그**: 원인 규명 + 출처 명시 문서화로 완료 처리 (무한정 열어두지 않음)

결정 내용을 `docs/agent-rules/project-decisions.md`에 기록.
