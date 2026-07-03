# MVP9 · edit-consistency 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이어붙이기 규칙을 임계값 기반(반전은 출발점 연장 단일 예외)으로 교체하고, 출발핀 탭 왕복·닫힌 코스 병합 핀·경유점 마커·redo를 추가해 코스 편집 정합성을 완성한다.

**Architecture:** `CourseEditSession`(Application)의 attach 판정을 4쌍 거리 비교에서 순서 규칙으로 교체하고 redo 스택을 얹는다. 핀 히트(화면 24pt)는 `MapViewRepresentable`(View)에서 판정해 결과만 ViewModel에 주입한다 — ViewModel은 MapKit을 import하지 않는 기존 경계 유지. 스펙: `docs/superpowers/specs/2026-07-03-edit-consistency-design.md`.

**Tech Stack:** Swift 6 async/await, iOS 17+ `@Observable`, SwiftUI + MKMapView(UIViewRepresentable), XCTest.

## Global Constraints

- ViewModel은 MapKit을 import하지 않는다 (화면 좌표 계산은 View 레이어).
- 테스트는 raw `xcodebuild ... -parallel-testing-enabled NO test`로만 실행 (XcodeBuildMCP 테스트 툴 금지, `docs/agent-rules/testing.md`).
- 시뮬레이터는 iOS 26+ 런타임 하나만 사용, 세션 중 교체 금지.
- force unwrap/cast/try 금지 (swiftlint 에러 + pre-commit 훅 차단).
- 커밋 전 build/test/lint 3종 통과 + `.git/trace-verify-{build,test,lint}.ok` 스탬프 필수 (Swift 변경 시).
- 커밋은 `scripts/trace-commit.sh -m "tag: 한국어 제목\n\n- 본문 3~4줄" -- <명시적 경로>`로 만든다.
- 연결 임계값 = 20m (기존 gap 판정과 동일 상수), 핀 히트 반경 = 24pt (시작값, QA 조정).

**공통 검증 명령** (아래 각 태스크의 "검증+커밋" 스텝에서 사용, `$SIM_UDID`는 testing.md Baseline 절차로 준비):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test \
  && touch .git/trace-verify-test.ok
swiftlint && touch .git/trace-verify-lint.ok
```

---

### Task 1: CourseEditSession — attach 순서 규칙 교체

**Files:**
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift`
- Test: `TraceTests/CourseEditSessionTests.swift`

**Interfaces:**
- Consumes: `CourseSegment.reversed()`, `CourseCoordinate.distanceMeters(to:)` (기존)
- Produces: `attach(_:using:)` 동작 계약 — ① 닫힌 코스(첫·끝 ≤20m)면 append ② 시작점이 도착점 ≤20m면 append ③ 시작점이 출발점 ≤20m(이고 ② 아님)면 반전 prepend ④ 그 외 도착점에서 gap 라우팅 후 그린 그대로 append. `static let connectionThresholdMeters: Double = 20`

- [x] **Step 1: 기존 테스트를 새 규칙 기대값으로 재구성 (실패 테스트 작성)**

`TraceTests/CourseEditSessionTests.swift`에서 아래 3개 테스트를 교체하고 2개를 추가한다. 나머지 테스트(`testAttachFirstSegment_appendsDirectly`, `testAttach_appendNoGap`, undo/clear/gap 테스트)는 그대로 둔다.

`testAttach_prependNoGap` → 교체 (prepend fixture는 "시작점이 기존 출발점 근처"여야 함):

```swift
// MARK: - attach: 규칙 3 — 출발점에서 시작한 구간은 반전 prepend (유일한 반전)

func testAttach_startNearExistingStart_reversePrepends() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    // Seed: B→C
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
    // New: near_B→A (출발점 B에서 시작해 바깥으로 그림) → 반전 prepend → 코스 A→…→C
    let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
    try await session.attach(.tapped(coordinates: [near_B, A], distanceMeters: 100), using: service)
    XCTAssertEqual(session.segments.count, 2)
    XCTAssertEqual(session.course?.coordinates.first, A, "반전 prepend로 코스 시작이 A여야 함")
    XCTAssertEqual(service.routeCallCount, 0, "출발점 근접이므로 gap 라우팅 없어야 함")
}
```

`testAttach_reversedAppend` → 교체 (자동 방향 감지 제거 — 원거리 스트로크는 그린 그대로 gap append):

```swift
// MARK: - attach: 규칙 4 — 양 끝점 모두에서 먼 스트로크는 그린 그대로 도착점 gap append

func testAttach_farStroke_appendsAsDrawnWithGap() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    // Seed: A→B
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    // New: C→D (양 끝점 모두에서 멂) → 도착점 B에서 C로 gap 라우팅 + 그린 그대로 append
    try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
    XCTAssertEqual(session.segments.count, 2)
    XCTAssertEqual(session.course?.coordinates.last, D, "그린 방향 그대로여야 함 (반전 금지)")
    XCTAssertEqual(service.routeCallCount, 1, "gap 라우팅 1회")
}
```

신규 2개 추가:

```swift
// MARK: - attach: 규칙 2 — 왕복 스트로크(도착점에서 시작)는 항상 append

func testAttach_roundTripStroke_appendsPreservingRunOrder() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    // Seed: A→B
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    // New: 도착점 B 근처에서 시작해 출발점 A 근처로 되짚는 왕복 스트로크
    let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
    let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
    try await session.attach(.drawn(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
    XCTAssertEqual(session.segments.count, 2)
    XCTAssertEqual(session.course?.coordinates.first, A, "출발은 A 유지 (prepend 금지)")
    XCTAssertEqual(session.course?.coordinates.last, near_A, "달리는 순서 유지")
}

// MARK: - attach: 규칙 1 — 닫힌 코스에는 무조건 append

func testAttach_closedCourse_alwaysAppends() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    // 닫힌 코스 구성: A→B, 그리고 B→A근처로 되짚기 → 첫·끝 좌표 ≤20m
    let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
    let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
    // 닫힌 코스에서 공유 지점 근처에서 시작하는 새 구간 → prepend가 아니라 append여야 함
    let near_A2 = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
    try await session.attach(.tapped(coordinates: [near_A2, C], distanceMeters: 100), using: service)
    XCTAssertEqual(session.course?.coordinates.first, A, "닫힌 코스 연장 시 출발점이 바뀌면 안 됨")
    XCTAssertEqual(session.course?.coordinates.last, C)
}
```

기존 prepend fixture 2곳 수정 — `testUndo_afterPrepend_removesMostRecentlyAttachedNotSpatialLast`와 `testSegmentColorKeys_stableAcrossPrepend`에서 prepend를 유발하는 attach를 `[D, near_A]`에서 `[near_A, D]`(시작점이 기존 출발점 근처)로 바꾼다. 두 테스트의 단언(assertion)은 그대로 유지된다 (반전 prepend 결과 코스 시작 = D).

```swift
// 변경 전: try await session.attach(.tapped(coordinates: [D, near_A], distanceMeters: 100), using: service)
// 변경 후:
try await session.attach(.tapped(coordinates: [near_A, D], distanceMeters: 100), using: service)
```

- [x] **Step 2: 테스트 실행 — 신규/교체 테스트 FAIL 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -only-testing:TraceTests/CourseEditSessionTests -parallel-testing-enabled NO test`
Expected: FAIL — `testAttach_closedCourse_alwaysAppends`가 실패해야 한다 (구규칙의 4쌍 비교가 ε 차이로 prepend 반전을 선택). 나머지 신규/교체 테스트는 구규칙에서도 같은 결과가 나와 우연히 통과할 수 있다 — 이들은 규칙 교체 후의 회귀 방어용이며, 판정 근거가 바뀌었는지는 Step 3 구현(resolveOrientation 삭제) 후 전체 PASS로 확인한다.

- [x] **Step 3: attach 규칙 구현**

`CourseEditSession.swift`에서 `resolveOrientation`/`AttachOrientation`을 삭제하고 `attach`를 다음으로 교체한다:

```swift
static let connectionThresholdMeters: Double = 20

// 이어붙이기 순서 규칙 (spec 규칙 1~4): 반전은 "출발점 연장"(규칙 3) 단 하나.
// 거리 비교로 앞/뒤를 추측하지 않는다 — 기본값은 항상 "도착점에서 이어진다".
func attach(
    _ newSegment: CourseSegment,
    using service: CoursePlanningServiceProtocol
) async throws {
    guard let existing = course,
          let existingStart = existing.coordinates.first,
          let existingEnd = existing.coordinates.last,
          let newStart = newSegment.coordinates.first else {
        append(newSegment)
        return
    }

    let threshold = Self.connectionThresholdMeters
    let isClosedCourse = existingStart.distanceMeters(to: existingEnd) <= threshold
    let startsNearEnd = newStart.distanceMeters(to: existingEnd) <= threshold
    let startsNearStart = newStart.distanceMeters(to: existingStart) <= threshold

    // 규칙 3: 열린 코스의 출발점에서 시작한 구간만 "출발 방향 연장" — 반전 prepend.
    // 반전 후 끝 좌표 = 원래 시작점 ≈ 기존 출발점이므로 gap 라우팅이 필요 없다.
    if !isClosedCourse, !startsNearEnd, startsNearStart {
        prepend(newSegment.reversed())
        return
    }

    // 규칙 1·2·4: 그린 그대로 도착점 뒤에 append (필요 시 gap 라우팅)
    var combinedCoords = newSegment.coordinates
    var combinedDistance = newSegment.distanceMeters
    if needsGap(from: existingEnd, to: newStart) {
        let gap = try await service.route(from: existingEnd, to: newStart)
        combinedCoords = gap.coordinates + Array(newSegment.coordinates.dropFirst())
        combinedDistance += gap.distanceMeters
    }
    append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
}
```

`needsGap`도 상수를 쓰도록 수정:

```swift
private func needsGap(from: CourseCoordinate, to: CourseCoordinate) -> Bool {
    from.distanceMeters(to: to) > Self.connectionThresholdMeters
}
```

클래스 상단 주석(공간순 vs 시간순 설명)은 유지한다. `makeMerged`, `append`, `prepend`, `undo`, `clear`는 이 태스크에서 변경하지 않는다.

- [x] **Step 4: 테스트 PASS 확인**

Run: Step 2와 동일 명령
Expected: `CourseEditSessionTests` 전체 PASS

- [x] **Step 5: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 (Global Constraints 참고) 후:

```bash
scripts/trace-commit.sh -m "feat: attach 판정을 임계값 순서 규칙으로 교체

- 4쌍 거리 비교(자동 방향 감지)를 제거하고 규칙 1~4로 교체한다
- 반전은 출발점 연장(규칙 3) 단일 예외로 한정한다
- 왕복 스트로크가 항상 append되어 핀 라벨 뒤집힘이 사라진다
- prepend fixture를 새 규칙에 맞게 재구성한다" \
  -- Trace/Application/CoursePlanning/CourseEditSession.swift TraceTests/CourseEditSessionTests.swift
```

---

### Task 2: CourseEditSession — redo 스택

**Files:**
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift`
- Test: `TraceTests/CourseEditSessionTests.swift`

**Interfaces:**
- Consumes: Task 1의 attach 규칙 (append/prepend 내부 메서드)
- Produces: `var canRedo: Bool`, `func redo()`. 계약: undo가 제거한 entry는 LIFO 스택에 보관, redo는 기록된 자리(맨 앞/뒤)에 order 보존 복원, **entry를 실제 추가한(성공한) attach**와 clear만 스택을 비운다.

- [x] **Step 1: 실패 테스트 작성**

`CourseEditSessionTests.swift`에 추가. 실패하는 서비스 스텁도 파일 하단 Stub 섹션에 추가한다:

```swift
// MARK: - redo

func testRedo_restoresUndoneSegment() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
    session.undo()
    XCTAssertTrue(session.canRedo)
    session.redo()
    XCTAssertEqual(session.segments.count, 2)
    XCTAssertEqual(session.course?.coordinates.last, C)
    XCTAssertEqual(session.segmentColorKeys, [0, 1], "order 보존")
    XCTAssertFalse(session.canRedo)
}

func testRedo_restoresPrependPosition() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
    // 반전 prepend 유발: 출발점 A 근처에서 시작해 D로
    let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
    try await session.attach(.tapped(coordinates: [near_A, D], distanceMeters: 100), using: service)
    XCTAssertEqual(session.course?.coordinates.first, D)

    session.undo()
    XCTAssertEqual(session.course?.coordinates.first, A)
    session.redo()
    XCTAssertEqual(session.course?.coordinates.first, D, "prepend 자리(맨 앞)로 복원되어야 함")
    XCTAssertEqual(session.segmentColorKeys, [2, 0, 1], "colorKey 보존")
}

func testRedo_multiple_restoresInReverseUndoOrder() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
    session.undo()
    session.undo()
    XCTAssertEqual(session.segments.count, 1)
    session.redo()
    XCTAssertEqual(session.course?.coordinates.last, C, "먼저 되돌린 것부터 역순 복원")
    session.redo()
    XCTAssertEqual(session.course?.coordinates.last, D)
}

func testAttach_success_clearsRedoStack() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
    session.undo()
    XCTAssertTrue(session.canRedo)
    try await session.attach(.tapped(coordinates: [B, D], distanceMeters: 100), using: service)
    XCTAssertFalse(session.canRedo, "성공한 attach는 미래를 무효화")
}

func testAttach_failure_preservesRedoStack() async throws {
    let session = CourseEditSession()
    let okService = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: okService)
    try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: okService)
    session.undo()
    XCTAssertTrue(session.canRedo)

    // gap 라우팅이 실패하는 원거리 attach → entry 미추가 → 스택 보존
    let failingService = FailingCourseService()
    do {
        try await session.attach(.tapped(coordinates: [D, C], distanceMeters: 100), using: failingService)
        XCTFail("gap 라우팅 실패로 throw되어야 함")
    } catch {}
    XCTAssertTrue(session.canRedo, "실패한 attach는 redo 스택을 보존해야 함")
    XCTAssertEqual(session.segments.count, 1)
}

func testClear_clearsRedoStack() async throws {
    let session = CourseEditSession()
    let service = StubCourseService()
    try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
    session.undo()
    XCTAssertTrue(session.canRedo)
    session.clear()
    XCTAssertFalse(session.canRedo)
}

func testRedo_empty_doesNothing() {
    let session = CourseEditSession()
    session.redo()
    XCTAssertTrue(session.segments.isEmpty)
}
```

Stub 섹션에 추가:

```swift
@MainActor
private final class FailingCourseService: CoursePlanningServiceProtocol {
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        throw CoursePlanningError.routeNotFound
    }
}
```

(주의: `testAttach_failure_preservesRedoStack`의 실패 attach는 시작점 `D`가 양 끝점 A·C…B에서 20m 초과가 되도록 D를 쓴다 — gap 라우팅 경로를 타야 throw된다.)

- [x] **Step 2: 테스트 실행 — FAIL 확인**

Run: Task 1 Step 2와 동일 명령
Expected: FAIL — `canRedo`/`redo()` 미정의 컴파일 에러

- [x] **Step 3: redo 구현**

`CourseEditSession.swift` 수정:

```swift
private struct Entry {
    let id: UUID
    let order: Int
    let placedAtFront: Bool   // redo가 같은 자리(맨 앞/뒤)에 복원하기 위한 기록
    let segment: CourseSegment
}

private var entries: [Entry] = []
private var redoStack: [Entry] = []   // undo가 제거한 entry (LIFO)
private var nextOrder = 0

var canRedo: Bool { !redoStack.isEmpty }

func undo() {
    guard let mostRecent = entries.max(by: { $0.order < $1.order }) else { return }
    entries.removeAll { $0.id == mostRecent.id }
    redoStack.append(mostRecent)
}

func redo() {
    guard let entry = redoStack.popLast() else { return }
    if entry.placedAtFront {
        entries.insert(entry, at: 0)
    } else {
        entries.append(entry)
    }
}

func clear() {
    entries = []
    redoStack = []
    nextOrder = 0
}

// MARK: - Private

// redo 스택은 여기(entry 실제 추가 시점)에서만 비운다 —
// attach가 gap 라우팅 실패로 throw하면 여기 도달하지 않아 스택이 보존된다.
private func append(_ segment: CourseSegment) {
    entries.append(Entry(id: UUID(), order: nextOrder, placedAtFront: false, segment: segment))
    nextOrder += 1
    redoStack = []
}

private func prepend(_ segment: CourseSegment) {
    entries.insert(Entry(id: UUID(), order: nextOrder, placedAtFront: true, segment: segment), at: 0)
    nextOrder += 1
    redoStack = []
}
```

- [x] **Step 4: 테스트 PASS 확인**

Run: Task 1 Step 2와 동일 명령
Expected: `CourseEditSessionTests` 전체 PASS

- [x] **Step 5: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 후:

```bash
scripts/trace-commit.sh -m "feat: CourseEditSession redo 스택 추가

- undo가 제거한 entry를 LIFO 스택에 보관하고 redo로 복원한다
- 자리(맨 앞/뒤)와 order를 보존해 색상·undo 체계와 충돌하지 않는다
- 성공한 attach와 clear만 스택을 비운다 (라우팅 실패는 보존)" \
  -- Trace/Application/CoursePlanning/CourseEditSession.swift TraceTests/CourseEditSessionTests.swift
```

---

### Task 3: ViewModel redo 노출 + 앞으로 돌리기 버튼

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: Task 2의 `session.canRedo`, `session.redo()`
- Produces: `viewModel.canRedo: Bool`, `viewModel.redo()` (undo와 동일하게 `selectedSegmentIndex` 초기화)

- [x] **Step 1: 실패 테스트 작성**

`CoursePlannerViewModelTests.swift`에 추가 (파일의 기존 스텁 서비스/생성 패턴을 그대로 따른다 — 기존 테스트가 ViewModel을 만드는 방식과 동일하게 구성):

```swift
func testRedo_restoresCourseAndResetsSelection() async {
    // 기존 테스트와 동일한 방식으로 viewModel 구성 (스텁 라우팅 서비스)
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
    XCTAssertEqual(viewModel.course?.segments.count, 2)

    await viewModel.undo()
    XCTAssertEqual(viewModel.course?.segments.count, 1)
    XCTAssertTrue(viewModel.canRedo)

    viewModel.selectSegment(at: 0)
    viewModel.redo()
    XCTAssertEqual(viewModel.course?.segments.count, 2)
    XCTAssertNil(viewModel.selectedSegmentIndex, "redo 후 선택 초기화 (prepend 복원 시 인덱스 밀림)")
    XCTAssertFalse(viewModel.canRedo)
}
```

- [x] **Step 2: 테스트 실행 — FAIL 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -only-testing:TraceTests/CoursePlannerViewModelTests -parallel-testing-enabled NO test`
Expected: FAIL — `canRedo`/`redo()` 미정의 컴파일 에러

- [x] **Step 3: 구현**

`CoursePlannerPageViewModel.swift`의 `// MARK: - Undo / Clear` 섹션에 추가:

```swift
var canRedo: Bool { session.canRedo }

func redo() {
    session.redo()
    selectedSegmentIndex = nil
}
```

`CoursePlannerPage+ControlsComponent.swift`의 되돌리기 버튼 아래에 추가:

```swift
Button("앞으로") { viewModel.redo() }
    .disabled(!viewModel.canRedo)
    .accessibilityIdentifier("coursePlanner.redo")
```

- [x] **Step 4: 테스트 PASS 확인**

Run: Step 2와 동일 명령
Expected: PASS

- [x] **Step 5: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 후:

```bash
scripts/trace-commit.sh -m "feat: 앞으로 돌리기(redo) 버튼 추가

- ViewModel에 canRedo/redo를 노출하고 선택 상태를 초기화한다
- 되돌리기 옆에 같은 스타일의 앞으로 버튼을 추가한다
- 복원할 것이 없으면 비활성화된다" \
  -- Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift "Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift" TraceTests/CoursePlannerViewModelTests.swift
```

---

### Task 4: ViewModel 핀 히트 분기 (탭 왕복·무시·안내) + statusPanel

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (statusPanel, onMapTap 호출부)
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1의 attach 규칙 (왕복 구간이 append로 붙음)
- Produces: `enum CoursePinRole: Equatable { case start, end, merged, pendingStart }` (ViewModel 파일 상단, MapKit 무관), `handleMapTap(at:hitPin:)` (기본값 `hitPin: nil` — 기존 호출부 호환), `var infoMessage: String?`, `var isClosedCourse: Bool`, `var roundTripHintVisible: Bool`. Task 5가 `CoursePinRole`을 View에서 소비한다.

- [x] **Step 1: 실패 테스트 작성**

`CoursePlannerViewModelTests.swift`에 추가 (스텁 라우팅은 요청 좌표 쌍을 기록하도록 기존 스텁을 확장하거나, 기존 스텁이 이미 기록한다면 그대로 사용):

```swift
func testHandleMapTap_startPinHit_appendsReturnLegSnappedToStart() async {
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: b)
    XCTAssertEqual(viewModel.course?.segments.count, 1)

    // 출발핀 히트 → 도착점에서 출발점 좌표(스냅)까지 왕복 구간 append
    let nearA = CourseCoordinate(latitude: 37.5001, longitude: 127.00)
    await viewModel.handleMapTap(at: nearA, hitPin: .start)
    XCTAssertEqual(viewModel.course?.segments.count, 2)
    XCTAssertEqual(viewModel.course?.coordinates.first, a, "출발 유지")
    XCTAssertEqual(viewModel.course?.coordinates.last, a, "탭 좌표가 아닌 출발점 좌표로 스냅")
    XCTAssertTrue(viewModel.isClosedCourse)
}

func testHandleMapTap_endPinHit_isNoOpWithInfo() async {
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: b)

    await viewModel.handleMapTap(at: b, hitPin: .end)
    XCTAssertEqual(viewModel.course?.segments.count, 1, "무시(no-op)")
    XCTAssertEqual(viewModel.infoMessage, "이미 도착점입니다")
}

func testHandleMapTap_mergedPinHit_isNoOpWithInfo() async {
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    await viewModel.handleMapTap(at: a, hitPin: .start) // 왕복으로 닫음

    await viewModel.handleMapTap(at: a, hitPin: .merged)
    XCTAssertEqual(viewModel.course?.segments.count, 2, "무시(no-op)")
    XCTAssertEqual(viewModel.infoMessage, "이미 닫힌 코스입니다")
}

func testInfoMessage_clearedOnNextAction() async {
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00), hitPin: .end)
    XCTAssertNotNil(viewModel.infoMessage)
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
    XCTAssertNil(viewModel.infoMessage, "다음 액션에서 안내가 사라져야 함")
}

func testRoundTripHintVisible_onlyForOpenCourseInTapMode() async {
    XCTAssertFalse(viewModel.roundTripHintVisible, "코스 없으면 숨김")
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    XCTAssertTrue(viewModel.roundTripHintVisible)
    await viewModel.handleMapTap(at: a, hitPin: .start)
    XCTAssertFalse(viewModel.roundTripHintVisible, "닫힌 코스면 숨김")
}
```

- [x] **Step 2: 테스트 실행 — FAIL 확인**

Run: Task 3 Step 2와 동일 명령
Expected: FAIL — `CoursePinRole`/`hitPin`/`infoMessage` 미정의 컴파일 에러

- [x] **Step 3: ViewModel 구현**

`CoursePlannerPageViewModel.swift` 상단(파일 스코프, `InteractionMode` 아래)에 추가:

```swift
// 지도 핀의 의미 역할. 화면 히트 판정은 View(MapViewRepresentable)가 하고,
// ViewModel은 판정 결과만 받는다 (MapKit 비의존 유지).
enum CoursePinRole: Equatable {
    case start        // 출발 핀
    case end          // 도착 핀
    case merged       // 닫힌 코스의 출발/도착 병합 핀
    case pendingStart // 첫 탭 대기 핀 (특수 동작 없음)
}
```

UI 상태에 추가:

```swift
private(set) var infoMessage: String?
```

computed 추가 (`distanceText` 근처):

```swift
// 닫힌 코스(왕복 완성) 판정 — 첫·끝 좌표가 연결 임계값 이내
var isClosedCourse: Bool {
    guard let course, course.coordinates.count > 1,
          let first = course.coordinates.first,
          let last = course.coordinates.last else { return false }
    return first.distanceMeters(to: last) <= CourseEditSession.connectionThresholdMeters
}

// 출발핀 탭 왕복 힌트 노출 조건 (statusPanel)
var roundTripHintVisible: Bool {
    interactionMode == .tap && course != nil && !isClosedCourse
}
```

`handleMapTap` 교체:

```swift
func handleMapTap(at coordinate: CourseCoordinate, hitPin: CoursePinRole? = nil) async {
    guard interactionMode == .tap else { return }
    infoMessage = nil

    // 핀 히트 분기 (상호배제, spec 설계 2)
    switch hitPin {
    case .merged:
        infoMessage = "이미 닫힌 코스입니다"
        return
    case .end:
        infoMessage = "이미 도착점입니다"
        return
    case .start:
        guard let course = session.course,
              let start = course.coordinates.first,
              let end = course.coordinates.last,
              course.coordinates.count > 1 else { break }
        // 왕복: 도착점 → 출발점 좌표(스냅). 시작점이 도착점이므로 항상 append.
        await routeAndAttach(from: end, to: start)
        return
    case .pendingStart, nil:
        break
    }

    if pendingTapStart == nil {
        if let start = nearestEndpoint(to: coordinate) {
            await routeAndAttach(from: start, to: coordinate)
            return
        }
        pendingTapStart = coordinate
        return
    }

    guard let start = pendingTapStart else { return }
    pendingTapStart = nil
    await routeAndAttach(from: start, to: coordinate)
}
```

`infoMessage = nil` 초기화를 다른 액션에도 추가: `toggleDrawingMode()` 두 분기, `appendStroke` 시작부, `undo()`, `redo()`, `clear()`.

- [x] **Step 4: statusPanel + 호출부 갱신**

`CoursePlannerPage.swift`의 `statusPanel`에서 error 분기 다음에 info 분기를 추가하고, distance 분기에 힌트를 붙인다:

```swift
} else if let infoMessage = viewModel.infoMessage {
    Text(infoMessage)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("coursePlanner.info")
} else if let distanceText = viewModel.distanceText {
    HStack(spacing: 6) {
        Text(distanceText)
            .fontWeight(.semibold)
            .accessibilityIdentifier("coursePlanner.distance")
        if viewModel.roundTripHintVisible {
            Text("· 출발핀을 탭하면 왕복 완성")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coursePlanner.roundTripHint")
        }
    }
} else {
```

(기존 distance 분기의 단독 `Text`는 위 HStack으로 대체된다. `onMapTap` 호출부는 이 태스크에서는 그대로 — 기본값 `hitPin: nil`로 호환된다.)

- [x] **Step 5: 테스트 PASS 확인**

Run: Task 3 Step 2와 동일 명령
Expected: PASS

- [x] **Step 6: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 후:

```bash
scripts/trace-commit.sh -m "feat: 출발핀 탭 왕복 분기와 안내 메시지 추가

- 핀 히트 결과(CoursePinRole)를 받아 왕복/무시/기존 동작으로 분기한다
- 출발핀 히트 시 도착점에서 출발점 좌표로 스냅 라우팅해 append한다
- 도착핀·병합 핀 히트는 무시하고 statusPanel에 안내를 표시한다
- 열린 코스에서 왕복 힌트 문구를 노출한다" \
  -- Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift TraceTests/CoursePlannerViewModelTests.swift
```

---

### Task 5: MapViewRepresentable — 핀 role + 화면 24pt 히트 판정 + 핀 diff 확장

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (mapPins role, onMapTap 클로저)

**Interfaces:**
- Consumes: Task 4의 `CoursePinRole`, `handleMapTap(at:hitPin:)`
- Produces: `MapPin.role: CoursePinRole`, `onMapTap: ((CourseCoordinate, CoursePinRole?) -> Void)?`

- [x] **Step 1: MapPin에 role 추가 + diff 확장**

`MapViewRepresentable.swift`:

```swift
struct MapPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: UIColor
    let systemImage: String
    let role: CoursePinRole

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title &&
            lhs.role == rhs.role   // 좌표가 같아도 스타일 전환(출발/도착 ↔ 병합)을 diff가 감지
    }
}
```

`ColoredPinAnnotation`에 `let role: CoursePinRole` 저장 프로퍼티와 init 파라미터를 추가한다.

`updateUIView`의 `pinsChanged` 판정을 MapPin 동등성 기반으로 교체:

```swift
let existing = uiView.annotations.compactMap { $0 as? ColoredPinAnnotation }
let existingAsPins = existing.map {
    MapPin(coordinate: $0.coordinate, title: $0.title ?? "", color: $0.color, systemImage: $0.systemImage, role: $0.role)
}
let pinsChanged = existingAsPins.count != pins.count ||
    zip(existingAsPins, pins).contains { $0 != $1 }
```

(추가하는 annotation 생성부에 `role: pin.role` 전달도 함께.)

- [x] **Step 2: 히트 판정 + 콜백 시그니처 변경**

`onMapTap` 선언 교체:

```swift
var onMapTap: ((CourseCoordinate, CoursePinRole?) -> Void)?
```

Coordinator의 `handleTap` 교체 + 헬퍼 추가:

```swift
@objc func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard let mapView = recognizer.view as? MKMapView else { return }
    let point = recognizer.location(in: mapView)
    let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
    let hit = pinHit(at: point, in: mapView)
    parent.onMapTap?(CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude), hit)
}

// 화면 포인트 기반 핀 히트 — 지도거리(줌 종속)가 아니라 화면 24pt 반경으로 판정한다.
private func pinHit(at point: CGPoint, in mapView: MKMapView) -> CoursePinRole? {
    let hitRadius: CGFloat = 24
    var best: (role: CoursePinRole, distance: CGFloat)?
    for annotation in mapView.annotations.compactMap({ $0 as? ColoredPinAnnotation }) {
        let pinPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
        let distance = hypot(pinPoint.x - point.x, pinPoint.y - point.y)
        if distance <= hitRadius, distance < (best?.distance ?? .infinity) {
            best = (annotation.role, distance)
        }
    }
    return best?.role
}
```

`CoursePlannerPage.swift` 갱신:
- `mapPins`의 세 핀 생성부에 role 추가 — 출발 `role: .start`, 도착 `role: .end`, pendingTapStart 핀 `role: .pendingStart`.
- `onMapTap` 클로저 교체:

```swift
onMapTap: { coord, hitPin in Task { await viewModel.handleMapTap(at: coord, hitPin: hitPin) } }
```

- [x] **Step 3: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 (뷰 레이어라 신규 단위 테스트 없음 — 빌드/기존 테스트/린트로 검증. 히트 반경 체감은 실기기 QA 항목):

```bash
scripts/trace-commit.sh -m "feat: 화면 24pt 핀 히트 판정을 탭에 연결

- MapPin에 role을 추가하고 diff가 스타일 전환을 감지하게 확장한다
- 탭 시 핀 화면 좌표와 24pt 반경으로 히트를 판정해 ViewModel에 전달한다
- 지도거리 기반 판정의 줌 종속 문제를 피한다" \
  -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
```

---

### Task 6: 닫힌 코스 병합 핀

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (mapPins)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (병합 핀 배지)

**Interfaces:**
- Consumes: Task 4의 `viewModel.isClosedCourse`, Task 5의 `MapPin.role`
- Produces: 닫힌 코스에서 `role: .merged` 핀 1개 (title "출발/도착")

- [x] **Step 1: mapPins 병합 분기**

`CoursePlannerPage.swift`의 `mapPins`에서 course 분기를 교체:

```swift
private var mapPins: [MapPin] {
    var pins: [MapPin] = []
    if let course = viewModel.course {
        if viewModel.isClosedCourse, let first = course.coordinates.first {
            // 닫힌 코스: 출발·도착이 같은 지점 — 병합 핀 하나만
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                title: "출발/도착",
                color: .systemGreen,
                systemImage: "figure.run",
                role: .merged
            ))
        } else {
            if let first = course.coordinates.first {
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    title: "출발",
                    color: .systemGreen,
                    systemImage: "figure.run",
                    role: .start
                ))
            }
            if let last = course.coordinates.last, course.coordinates.count > 1 {
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                    title: "도착",
                    color: .systemRed,
                    systemImage: "flag.checkered",
                    role: .end
                ))
            }
        }
    }
    // tap 모드에서 pendingTapStart는 코스가 비어 있을 때만 설정됨 (최초 2탭 대기)
    if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
        pins.append(MapPin(
            coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
            title: "출발",
            color: .systemGreen,
            systemImage: "figure.run",
            role: .pendingStart
        ))
    }
    return pins
}
```

- [x] **Step 2: 병합 핀 배지 (도착 요소 결합)**

`MapViewRepresentable.swift`의 `viewFor annotation` — ColoredPinAnnotation 처리부 끝에 추가 (매 호출 새 뷰를 만드는 기존 구조라 잔여 배지 제거를 먼저 한다):

```swift
view.subviews.filter { $0.tag == Self.mergedBadgeTag }.forEach { $0.removeFromSuperview() }
if pin.role == .merged {
    let badge = UIImageView(image: UIImage(systemName: "flag.checkered"))
    badge.tag = Self.mergedBadgeTag
    badge.tintColor = .white
    badge.backgroundColor = .systemRed
    badge.layer.cornerRadius = 7
    badge.clipsToBounds = true
    badge.contentMode = .scaleAspectFit
    badge.frame = CGRect(x: view.bounds.width - 10, y: -4, width: 14, height: 14)
    view.addSubview(badge)
}
```

Coordinator에 상수 추가:

```swift
static let mergedBadgeTag = 990
```

(참고: `guard let pin = annotation as? ColoredPinAnnotation`의 `pin`을 그대로 사용. 기존 `displayPriority = .required`, `collisionMode = .none`은 병합 핀에도 그대로 적용된다.)

- [x] **Step 3: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 후:

```bash
scripts/trace-commit.sh -m "feat: 닫힌 코스 병합 핀 표시

- 첫·끝 좌표가 임계값 이내면 출발/도착 핀을 하나로 병합한다
- 출발 스타일 기반에 체크무늬 배지를 결합해 닫힘을 표현한다
- 왕복 완성 시 핀 겹침 혼동을 제거한다" \
  -- Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
```

---

### Task 7: 경유점 마커

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` (`waypointCoordinates`)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (WaypointAnnotation 타입·뷰·갱신)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (파라미터 전달)
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `course.segments` (기존)
- Produces: `viewModel.waypointCoordinates: [CourseCoordinate]` (인접 구간 경계 = 각 구간 마지막 좌표, 최종 구간 제외), `MapViewRepresentable.waypoints: [CLLocationCoordinate2D]`

- [x] **Step 1: 실패 테스트 작성**

```swift
func testWaypointCoordinates_areSegmentBoundariesExceptFinal() async {
    let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    let c = CourseCoordinate(latitude: 37.52, longitude: 127.00)
    await viewModel.handleMapTap(at: a)
    await viewModel.handleMapTap(at: b)   // 구간 1: a→b
    await viewModel.handleMapTap(at: c)   // 구간 2: b→c
    XCTAssertEqual(viewModel.course?.segments.count, 2)

    let waypoints = viewModel.waypointCoordinates
    XCTAssertEqual(waypoints.count, 1, "구간 2개 → 경계 1개")
    XCTAssertEqual(waypoints.first, viewModel.course?.segments.first?.coordinates.last)
}

func testWaypointCoordinates_emptyForSingleSegment() async {
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    XCTAssertTrue(viewModel.waypointCoordinates.isEmpty)
}
```

- [x] **Step 2: 테스트 실행 — FAIL 확인**

Run: Task 3 Step 2와 동일 명령
Expected: FAIL — `waypointCoordinates` 미정의 컴파일 에러

- [x] **Step 3: ViewModel 구현**

`CoursePlannerPageViewModel.swift`에 추가 (`segmentColorKeys` 근처):

```swift
// 지도 경유점 마커용: 인접 구간이 만나는 경계 좌표 (각 구간의 마지막 좌표, 최종 구간 제외)
var waypointCoordinates: [CourseCoordinate] {
    guard let segments = course?.segments, segments.count > 1 else { return [] }
    return segments.dropLast().compactMap { $0.coordinates.last }
}
```

- [x] **Step 4: 테스트 PASS 확인**

Run: Task 3 Step 2와 동일 명령
Expected: PASS

- [x] **Step 5: annotation 타입·뷰·갱신 구현**

`MapViewRepresentable.swift`의 Supporting Types에 추가:

```swift
// 경유점(구간 경계) 마커 — 핀 diff와 분리된 별도 annotation 타입 (spec 설계 3 구현 노트)
final class WaypointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

final class WaypointAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.cornerRadius = 5
        backgroundColor = .white
        layer.borderColor = UIColor.systemGray.cgColor
        layer.borderWidth = 2
        // 조용한 시각 위계: 출발/도착 핀(.required/.none)이 항상 이기고, 겹치면 경유점이 양보한다
        displayPriority = .defaultLow
        collisionMode = .circle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

프로퍼티 추가:

```swift
var waypoints: [CLLocationCoordinate2D]
```

`updateUIView`의 세그먼트 스냅샷 게이트 블록 안(경유점은 세그먼트에서 파생되므로 같은 무효화 시점) 마지막에 추가:

```swift
uiView.removeAnnotations(uiView.annotations.filter { $0 is WaypointAnnotation })
for waypoint in waypoints {
    uiView.addAnnotation(WaypointAnnotation(coordinate: waypoint))
}
```

`viewFor annotation` 상단에 분기 추가:

```swift
if annotation is WaypointAnnotation {
    let identifier = "waypoint"
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? WaypointAnnotationView
        ?? WaypointAnnotationView(annotation: annotation, reuseIdentifier: identifier)
    view.annotation = annotation
    return view
}
```

`CoursePlannerPage.swift`의 `MapViewRepresentable(...)` 호출에 파라미터 추가:

```swift
waypoints: viewModel.waypointCoordinates.map {
    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
},
```

(주의: `WaypointAnnotationView`의 `fatalError`는 기존 `SegmentDistanceAnnotationView`와 동일 패턴 — swiftlint 설정에서 이미 허용되는 형태인지 해당 파일의 기존 코드로 확인하고 동일하게 따른다.)

- [x] **Step 6: 전체 검증 + 커밋**

공통 검증 명령 3종 실행 후:

```bash
scripts/trace-commit.sh -m "feat: 구간 경계 경유점 마커 표시

- 인접 구간 경계마다 작은 무번호 점을 표시한다
- 별도 annotation 타입으로 핀 diff와 분리한다
- defaultLow/circle로 출발·도착 핀에 항상 양보하는 조용한 위계를 준다" \
  -- Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift TraceTests/CoursePlannerViewModelTests.swift
```

---

### Task 8: 마무리 검증 + 문서 갱신

**Files:**
- Modify: `docs/roadmap.md` (마일스톤 체크), 이 플랜 파일 (체크박스)

**Interfaces:**
- Consumes: Task 1~7 전체

- [x] **Step 1: 전체 스위트 최종 실행**

공통 검증 명령 3종을 순서대로 실행하고 3개 모두 성공을 확인한다 (스탬프 갱신 포함).
Expected: build/test/lint 모두 성공, `TraceTests` 전체 PASS

- [x] **Step 2: 커밋 전 코드리뷰**

`superpowers:requesting-code-review` 관례에 따라 `/code-review`를 실행하고, CONFIRMED 결함은 수정 후 해당 태스크 커밋 대상 파일로 재검증한다 (workflow.md "구현 후 · 커밋 전" 체크포인트).

- [x] **Step 3: 로드맵 갱신 + 커밋**

`docs/roadmap.md`의 MVP9 `edit-consistency` 마일스톤을 `[x]`로 바꾸고, 이 플랜의 남은 체크박스를 확인한다:

```bash
scripts/trace-commit.sh -m "docs: MVP9 edit-consistency 마일스톤 완료 처리

- 구현·테스트·리뷰 완료에 따라 로드맵 체크박스를 갱신한다
- 실기기 QA 체크리스트는 MVP 완료 절차에서 별도 작성한다" \
  -- docs/roadmap.md docs/superpowers/plans/2026-07-03-edit-consistency.md
```

- [ ] **Step 4: 실기기 QA 체크리스트 작성 (MVP 완료 절차)**

`docs/qa/2026-MM-DD-edit-consistency-device-checklist.md`를 `docs/agent-rules/testing.md`의 Real-Device Verification 템플릿으로 작성해 사용자에게 제시한다. 스펙의 "실기기 QA" 절 항목(왕복 그리기/탭 왕복 핀·경유점·오프셋, 24pt 히트 체감, 20m 닫힘 판정, 힌트·안내 문구, 경유점 위계)을 포함한다.

---

## 스펙 커버리지 맵 (self-review용)

| 스펙 항목 | 태스크 |
|---|---|
| 설계 1 — attach 규칙 1~4 | Task 1 |
| 설계 2 — 핀 히트 분기·왕복·무시·안내·힌트 | Task 4 (분기·문구), Task 5 (24pt 히트 판정) |
| 설계 3 — 병합 핀·경유점·충돌 우선순위·diff 노트 | Task 5 (diff), Task 6 (병합 핀), Task 7 (경유점) |
| 설계 4 — redo | Task 2 (세션), Task 3 (VM·버튼) |
| 테스트 절 | 각 태스크 Step 1 + Task 8 |
| 기록·후속 (roadmap/backlog/decisions) | 킥오프 커밋(완료) + Task 8 |
