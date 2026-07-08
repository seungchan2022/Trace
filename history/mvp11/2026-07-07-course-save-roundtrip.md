# MVP11 course-save-roundtrip Implementation Plan

> 완료(소급 확인, 2026-07-08): 전 태스크 구현 완료 — 근거 커밋 `0d34611`~`1f7280e`(roundTrip 케이스,
> 왕복 삽입 연산, SwiftData 어댑터, 초안 자동 저장 배선, 저장/목록/불러오기/삭제 UI) + roadmap의
> "8개 태스크 전부 완료, 최종 전체 스위트 그린 확인" 기록. 체크박스는 실행 당시 미갱신.
> 단, 초안 자동 저장·복원 부분은 이후 제거됨(`2026-07-08-remove-draft-persistence.md` 참고).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 작업 중 코스의 자동 저장·복원 + 이름 붙여 저장/목록/불러오기/삭제(SwiftData) + 구간 패널의 "왕복 추가"(좌표 복제 삽입)를 구현한다.

**Architecture:** Domain에 `CourseRepositoryProtocol`·`CourseDraft`·`SavedCourse`를 추가하고 SwiftData 구현은 `Trace/Infrastructure/Persistence/SwiftData/` actor 어댑터로 격리한다(포트-어댑터, 도메인은 SwiftData를 모름). `CourseEditSession`에 스냅샷/복원과 왕복 삽입을 추가하고, ViewModel이 편집 연산 확정 시마다 직렬 Task 체인으로 초안을 저장한다.

**Tech Stack:** Swift 6 동시성(@MainActor ViewModel, actor 어댑터), SwiftData(iOS 17+), SwiftUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md`
**Branch:** `feature/course-save-roundtrip` (이미 생성됨 — 새 브랜치 만들지 말 것)

## Global Constraints

- iOS 17+, Swift 6 스타일 `async`/`await`, `@Observable` (ObservableObject 금지)
- force unwrap / force cast / force try 금지 (swiftlint가 에러로 차단)
- 파일 500줄 초과 금지(swiftlint file_length) — 테스트는 지정된 **새 파일**에 작성
- Xcode 프로젝트는 파일 시스템 동기화 그룹 — 새 파일은 해당 디렉터리에 생성만 하면 타깃에 자동 포함 (pbxproj 편집 금지)
- 검증 명령 (docs/agent-rules/testing.md — SIM_UDID는 기준 시뮬레이터 고정값, 세션당 하나만 사용):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
  - 테스트: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test` (`-parallel-testing-enabled NO` 필수, XcodeBuildMCP test_sim 사용 금지)
  - 린트: `swiftlint`
  - 통과 시 스탬프: `touch .git/trace-verify-build.ok` / `trace-verify-test.ok` / `trace-verify-lint.ok`
- 커밋: `scripts/trace-commit.sh -m "tag: 한국어 제목\n\n- 본문 3~4줄" -- <path>...` (git add -A 금지, 태그 영어·제목/본문 한국어)
- 상수: 연결 임계값 20m(`CourseEditSession.connectionThresholdMeters`), 코스 총 좌표 상한 **20,000**, 초안 저장 연속 실패 알림 임계 **3회**, 직렬화 포맷 버전 **1**
- 스펙과 다른 점 1건(의도된 단순화): `clearDraft`를 별도 메서드로 두지 않고 **빈 스냅샷 저장**으로 통일한다(초기화도 편집 연산의 하나로 같은 경로를 탄다)

---

### Task 1: CourseSegment에 왕복 케이스 추가

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift`
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift:204-213` (`makeMerged` switch 완전성)
- Test: `TraceTests/CourseSegmentTests.swift` (기존 파일에 추가)

**Interfaces:**
- Consumes: 없음 (기존 enum 확장)
- Produces: `CourseSegment.roundTrip(coordinates: [CourseCoordinate], distanceMeters: Double)` 케이스, `var isRoundTrip: Bool` — Task 3(삽입), Task 4(직렬화), Task 7(패널 표식)이 사용

- [ ] **Step 1: 실패하는 테스트 작성** — `TraceTests/CourseSegmentTests.swift`에 추가:

```swift
func testRoundTripCase_exposesCoordinatesAndDistance() {
    let a = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    let b = CourseCoordinate(latitude: 37.5670, longitude: 126.9790)
    let seg = CourseSegment.roundTrip(coordinates: [b, a, b], distanceMeters: 240)
    XCTAssertEqual(seg.coordinates, [b, a, b])
    XCTAssertEqual(seg.distanceMeters, 240)
    XCTAssertTrue(seg.isRoundTrip)
    XCTAssertFalse(CourseSegment.tapped(coordinates: [a, b], distanceMeters: 120).isRoundTrip)
}

func testRoundTripReversed_reversesCoordinatesKeepingCase() {
    let a = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    let b = CourseCoordinate(latitude: 37.5670, longitude: 126.9790)
    let c = CourseCoordinate(latitude: 37.5675, longitude: 126.9795)
    let reversed = CourseSegment.roundTrip(coordinates: [a, b, c], distanceMeters: 240).reversed()
    XCTAssertEqual(reversed, .roundTrip(coordinates: [c, b, a], distanceMeters: 240))
}
```

- [ ] **Step 2: 테스트 실패 확인** — 빌드 에러(케이스 없음)로 실패해야 정상. 컴파일 에러도 "실패 확인"으로 간주.
- [ ] **Step 3: 구현** — `CourseSegment.swift`를 다음으로 교체:

```swift
import Foundation

enum CourseSegment: Equatable, Sendable {
    case tapped(coordinates: [CourseCoordinate], distanceMeters: Double)
    case drawn(coordinates: [CourseCoordinate], distanceMeters: Double)
    // 기존 구간 뒤에 삽입되는 "갔다 되돌아오기"(역+정 병합) — 좌표 복제라 라우팅 비호출 (MVP11 스펙 §4)
    case roundTrip(coordinates: [CourseCoordinate], distanceMeters: Double)

    var coordinates: [CourseCoordinate] {
        switch self {
        case .tapped(let coords, _), .drawn(let coords, _), .roundTrip(let coords, _): return coords
        }
    }

    var distanceMeters: Double {
        switch self {
        case .tapped(_, let d), .drawn(_, let d), .roundTrip(_, let d): return d
        }
    }

    var isRoundTrip: Bool {
        if case .roundTrip = self { return true }
        return false
    }

    func reversed() -> CourseSegment {
        switch self {
        case .tapped(let coords, let dist):
            return .tapped(coordinates: coords.reversed(), distanceMeters: dist)
        case .drawn(let coords, let dist):
            return .drawn(coordinates: coords.reversed(), distanceMeters: dist)
        case .roundTrip(let coords, let dist):
            return .roundTrip(coordinates: coords.reversed(), distanceMeters: dist)
        }
    }
}
```

그리고 `CourseEditSession.makeMerged`의 switch에 케이스 추가 (attach는 `.tapped`/`.drawn`만 받지만 switch 완전성 필요):

```swift
    private func makeMerged(
        like original: CourseSegment,
        coordinates: [CourseCoordinate],
        distance: Double
    ) -> CourseSegment {
        switch original {
        case .tapped:    return .tapped(coordinates: coordinates, distanceMeters: distance)
        case .drawn:     return .drawn(coordinates: coordinates, distanceMeters: distance)
        case .roundTrip: return .roundTrip(coordinates: coordinates, distanceMeters: distance)
        }
    }
```

- [ ] **Step 4: 케이스 분기 전수 확인** — `grep -rn "case .tapped\|case \.drawn" Trace --include="*.swift"` 실행. 위 두 파일 외에 `.tapped`/`.drawn`으로 switch하는 곳이 없어야 한다(2026-07-07 기준 없음 확인됨 — 새로 생겼다면 그 지점도 처리).
- [ ] **Step 5: 테스트 통과 확인** — 전체 테스트 실행(Global Constraints 명령), PASS 확인.
- [ ] **Step 6: 커밋** — `feat: CourseSegment에 roundTrip 케이스 추가`

---

### Task 2: CourseDraft 스냅샷 — 세션 직렬화/복원/불러오기

**Files:**
- Create: `Trace/Domain/CoursePlanning/Entity/CourseDraft.swift`
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift` (Entry에 `anchorID` 추가, snapshot/restore/load API)
- Test: `TraceTests/CourseDraftSnapshotTests.swift` (새 파일)

**Interfaces:**
- Consumes: `CourseSegment` (Task 1의 `.roundTrip` 포함)
- Produces:
  - `struct CourseDraft: Equatable, Sendable { struct Entry; var entries: [Entry]; var nextOrder: Int; var isEmpty: Bool }`
  - `CourseEditSession.snapshot() -> CourseDraft`
  - `CourseEditSession.restore(from: CourseDraft)` — **엔트리 id 보존** (스펙 §3: append 경로 재사용 금지)
  - `CourseEditSession.load(segments: [CourseSegment])` — 저장 코스 불러오기용(공간순 → 시간순 재부여)

- [ ] **Step 1: CourseDraft 엔티티 작성** — `Trace/Domain/CoursePlanning/Entity/CourseDraft.swift`:

```swift
import Foundation

// 작업 중 코스(초안)의 세션 상태 스냅샷. undo가 재시작 후에도 동작하도록
// 시간순(order)·배치(placedAtFront)·왕복 anchor까지 담는다. redo 스택은 담지 않는다 (MVP11 스펙 §2).
struct CourseDraft: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        let segment: CourseSegment
    }

    var entries: [Entry]
    var nextOrder: Int

    var isEmpty: Bool { entries.isEmpty }

    static let empty = CourseDraft(entries: [], nextOrder: 0)
}
```

- [ ] **Step 2: 실패하는 테스트 작성** — `TraceTests/CourseDraftSnapshotTests.swift` (새 파일):

```swift
import XCTest
@testable import Trace

@MainActor
final class CourseDraftSnapshotTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func makeSessionWithTwoSegments() async throws -> (CourseEditSession, StubCourseService) {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: service
        )
        try await session.attach(
            .tapped(coordinates: [coord(37.51, 127.00), coord(37.52, 127.00)], distanceMeters: 1000),
            using: service
        )
        return (session, service)
    }

    func testSnapshotRestore_roundTripsCourseAndUndo() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        let draft = session.snapshot()

        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertEqual(restored.segments, session.segments)
        XCTAssertEqual(restored.segmentColorKeys, session.segmentColorKeys)

        // 복원 후 undo가 시간순 최신(두 번째 구간)을 제거해야 한다
        restored.undo()
        XCTAssertEqual(restored.segments.count, 1)
        XCTAssertEqual(restored.segments.first?.coordinates.first, coord(37.50, 127.00))
    }

    func testSnapshot_emptySession_isEmptyDraft() {
        let session = CourseEditSession()
        XCTAssertTrue(session.snapshot().isEmpty)
    }

    func testRestore_emptyDraft_clearsSession() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        session.restore(from: .empty)
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertFalse(session.canRedo)
    }

    func testRestore_preservesEntryIDs() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        let draft = session.snapshot()
        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertEqual(restored.snapshot().entries.map(\.id), draft.entries.map(\.id))
    }

    func testRestore_dropsRedoStack() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        session.undo()
        XCTAssertTrue(session.canRedo)
        let draft = session.snapshot()
        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertFalse(restored.canRedo) // 스냅샷에 redo가 없으므로 복원 후 비활성 (스펙 §1 제외 사항)
    }

    func testLoadSegments_reassignsSequentialOrders() {
        let session = CourseEditSession()
        let segs: [CourseSegment] = [
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            .drawn(coordinates: [coord(37.51, 127.00), coord(37.52, 127.00)], distanceMeters: 1000)
        ]
        session.load(segments: segs)
        XCTAssertEqual(session.segments, segs)
        XCTAssertEqual(session.segmentColorKeys, [0, 1])
        session.undo() // 공간순 마지막이 시간순 최신
        XCTAssertEqual(session.segments.count, 1)
    }
}

// StubCourseService: CourseEditSessionTests.swift의 것과 동일 형태 (private라 파일별 재정의)
private final class StubCourseService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}
```

- [ ] **Step 3: 테스트 실패 확인** — 컴파일 에러(snapshot/restore/load 없음)로 실패 확인.
- [ ] **Step 4: 구현** — `CourseEditSession.swift` 수정:

Entry에 `anchorID` 추가 (Task 3에서 왕복이 사용, 여기서는 nil만):

```swift
    private struct Entry {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?   // 왕복 엔트리의 redo 재삽입 기준(대상 구간 id). 일반 엔트리는 nil.
        let segment: CourseSegment
    }
```

기존 `append`/`prepend`의 Entry 생성에 `anchorID: nil` 추가:

```swift
    private func append(_ segment: CourseSegment) {
        entries.append(Entry(id: UUID(), order: nextOrder, placedAtFront: false, anchorID: nil, segment: segment))
        nextOrder += 1
        redoStack = []
    }

    private func prepend(_ segment: CourseSegment) {
        entries.insert(Entry(id: UUID(), order: nextOrder, placedAtFront: true, anchorID: nil, segment: segment), at: 0)
        nextOrder += 1
        redoStack = []
    }
```

스냅샷/복원/불러오기 API 추가 (`clear()` 아래에):

```swift
    // MARK: - Snapshot (초안 저장·복원, MVP11 스펙 §3)

    // 복원은 엔트리 id를 보존해야 한다 — append/prepend 재사용 시 id가 재발급되어
    // 왕복 anchor 참조가 끊긴다 (스펙 §3·§4).
    func snapshot() -> CourseDraft {
        CourseDraft(
            entries: entries.map {
                CourseDraft.Entry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, segment: $0.segment
                )
            },
            nextOrder: nextOrder
        )
    }

    func restore(from draft: CourseDraft) {
        entries = draft.entries.map {
            Entry(
                id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                anchorID: $0.anchorID, segment: $0.segment
            )
        }
        nextOrder = draft.nextOrder
        redoStack = []
    }

    // 저장 코스 불러오기: 공간순 세그먼트에 시간순을 0부터 재부여 (undo = 공간순 마지막부터 제거)
    func load(segments: [CourseSegment]) {
        entries = segments.enumerated().map { index, segment in
            Entry(id: UUID(), order: index, placedAtFront: false, anchorID: nil, segment: segment)
        }
        nextOrder = segments.count
        redoStack = []
    }
```

- [ ] **Step 5: 테스트 통과 확인** — 전체 테스트 PASS.
- [ ] **Step 6: 커밋** — `feat: CourseEditSession 스냅샷 직렬화·복원·불러오기 추가`

---

### Task 3: 왕복 삽입 (insertRoundTrip)

**Files:**
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift` (insertRoundTrip, canInsertRoundTrip, redo anchor 복원)
- Test: `TraceTests/CourseRoundTripInsertTests.swift` (새 파일)

**Interfaces:**
- Consumes: Task 1 `.roundTrip`·`isRoundTrip`, Task 2 Entry.anchorID
- Produces:
  - `CourseEditSession.insertRoundTrip(afterOrder: Int)` — order(=colorKey)로 대상 지정
  - `CourseEditSession.canInsertRoundTrip(afterOrder: Int) -> Bool`
  - `CourseEditSession.maxTotalCoordinates` (= 20_000)
  - Task 7의 ViewModel/패널이 order(colorKey)를 그대로 넘겨 호출

- [ ] **Step 1: 실패하는 테스트 작성** — `TraceTests/CourseRoundTripInsertTests.swift` (새 파일):

```swift
import XCTest
@testable import Trace

@MainActor
final class CourseRoundTripInsertTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    // 코스: A→B (order 0), B→C (order 1), C→D (order 2)
    private func makeThreeSegmentSession() async throws -> CourseEditSession {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        let c = coord(37.52, 127.00), d = coord(37.53, 127.00)
        try await session.attach(.tapped(coordinates: [a, b], distanceMeters: 1000), using: service)
        try await session.attach(.tapped(coordinates: [b, c], distanceMeters: 1000), using: service)
        try await session.attach(.tapped(coordinates: [c, d], distanceMeters: 1000), using: service)
        return session
    }

    func testInsertRoundTrip_middleSegment_insertsMergedPairAfterIt() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1) // B→C 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[2] // 공간순: [A→B, B→C, 왕복, C→D]
        XCTAssertTrue(inserted.isRoundTrip)
        // 왕복 좌표: C→B→C (역방향 + 정방향 dropFirst), 거리 2배
        XCTAssertEqual(inserted.coordinates, [coord(37.52, 127.00), coord(37.51, 127.00), coord(37.52, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 2000)
        // 연결 유지: 왕복 끝(C) == 다음 구간 시작(C)
        XCTAssertEqual(inserted.coordinates.last, session.segments[3].coordinates.first)
        // 총 거리 = 3000 + 2000
        XCTAssertEqual(session.course?.distanceMeters, 5000)
    }

    func testInsertRoundTrip_lastSegment_appendsAtEnd() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2)
        XCTAssertEqual(session.segments.count, 4)
        XCTAssertTrue(session.segments[3].isRoundTrip)
    }

    func testInsertRoundTrip_undoOnce_removesWholeRoundTrip() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertRoundTrip(afterOrder: 1)
        session.undo()
        XCTAssertEqual(session.segments, before) // undo 한 번 = 왕복 전체 취소 (스펙 §4)
    }

    func testInsertRoundTrip_undoRedo_restoresAtAnchorPosition() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after) // 맨 뒤가 아니라 anchor 바로 뒤로 복원 (스펙 §4)
    }

    func testInsertRoundTrip_onRoundTripSegment_allowed() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        // 방금 삽입된 왕복(order 3)에 다시 왕복 — 특수 케이스 없음 (스펙 §4)
        session.insertRoundTrip(afterOrder: 3)
        XCTAssertEqual(session.segments.count, 5)
        XCTAssertEqual(session.segments[3].coordinates.first, session.segments[2].coordinates.last)
    }

    func testInsertRoundTrip_clearsRedoStack() async throws {
        let session = try await makeThreeSegmentSession()
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.insertRoundTrip(afterOrder: 1)
        XCTAssertFalse(session.canRedo)
    }

    func testCanInsertRoundTrip_falseForUnknownOrder() async throws {
        let session = try await makeThreeSegmentSession()
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 99))
        session.insertRoundTrip(afterOrder: 99) // no-op이어야 함
        XCTAssertEqual(session.segments.count, 3)
    }

    func testCanInsertRoundTrip_falseWhenExceedingCoordinateCap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 좌표 15,000개짜리 구간 — 왕복 시 +29,999로 상한(20,000) 초과
        let bigCoords = (0..<15_000).map { coord(37.50 + Double($0) * 0.00001, 127.00) }
        try await session.attach(.drawn(coordinates: bigCoords, distanceMeters: 15_000), using: service)
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 0))
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 1) // no-op
    }

    func testInsertRoundTrip_singleSegmentCourse_appends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        try await session.attach(.tapped(coordinates: [a, b], distanceMeters: 1000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.segments[1].coordinates, [b, a, b])
        XCTAssertEqual(session.course?.distanceMeters, 3000)
    }

    func testInsertRoundTrip_closedCourse_keepsClosure() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        // 닫힌 코스: A→B→A (첫·끝 좌표 동일 = 임계값 이내)
        try await session.attach(.drawn(coordinates: [a, b, a], distanceMeters: 2000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        // 삽입 후에도 코스는 A에서 시작해 A에서 끝난다 (닫힘 유지, 스펙 §4)
        XCTAssertEqual(session.course?.coordinates.first, a)
        XCTAssertEqual(session.course?.coordinates.last, a)
    }

    func testSnapshotRestore_preservesRoundTripRedoAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        let restored = CourseEditSession()
        restored.restore(from: session.snapshot())
        let after = restored.segments
        restored.undo()
        restored.redo()
        XCTAssertEqual(restored.segments, after) // 복원 후에도 anchor 기반 redo 위치 유지 (스펙 §4)
    }
}

private final class StubCourseService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러로 실패 확인.
- [ ] **Step 3: 구현** — `CourseEditSession.swift`에 추가:

상수와 좌표 수 (기존 `connectionThresholdMeters` 근처에):

```swift
    static let maxTotalCoordinates = 20_000

    private var totalCoordinateCount: Int {
        entries.reduce(0) { $0 + $1.segment.coordinates.count }
    }
```

왕복 삽입 (`clear()` 위나 아래, MARK 구분):

```swift
    // MARK: - Round Trip (MVP11 스펙 §4)

    // 대상 구간(A→B) 바로 뒤에 역+정 병합 왕복(B→A→B, 거리 2×)을 한 엔트리로 삽입한다.
    // 한 덩어리인 이유: 두 엔트리로 나누면 undo 한 번 시점에 역방향만 남아 코스가 끊긴다.
    func canInsertRoundTrip(afterOrder order: Int) -> Bool {
        guard let entry = entries.first(where: { $0.order == order }) else { return false }
        let n = entry.segment.coordinates.count
        guard n >= 2 else { return false }
        return totalCoordinateCount + (2 * n - 1) <= Self.maxTotalCoordinates
    }

    func insertRoundTrip(afterOrder order: Int) {
        guard canInsertRoundTrip(afterOrder: order),
              let index = entries.firstIndex(where: { $0.order == order }) else { return }
        let target = entries[index]
        let coords = target.segment.coordinates
        let roundTrip = CourseSegment.roundTrip(
            coordinates: Array(coords.reversed()) + Array(coords.dropFirst()),
            distanceMeters: target.segment.distanceMeters * 2
        )
        entries.insert(
            Entry(id: UUID(), order: nextOrder, placedAtFront: false, anchorID: target.id, segment: roundTrip),
            at: index + 1
        )
        nextOrder += 1
        redoStack = []
    }
```

`redo()`를 anchor 우선으로 교체:

```swift
    func redo() {
        guard let entry = redoStack.popLast() else { return }
        // 왕복 엔트리는 anchor 바로 뒤로 복원 — anchor는 LIFO 순서상 항상 먼저 복원돼 있다 (스펙 §4).
        // anchor 미발견 시 placedAtFront/append 폴백 (스펙 증명상 도달 불가, 방어적).
        if let anchorID = entry.anchorID,
           let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }) {
            entries.insert(entry, at: anchorIndex + 1)
        } else if entry.placedAtFront {
            entries.insert(entry, at: 0)
        } else {
            entries.append(entry)
        }
    }
```

- [ ] **Step 4: 테스트 통과 확인** — 전체 테스트 PASS (기존 redo 테스트 3건 회귀 포함 확인).
- [ ] **Step 5: 커밋** — `feat: 구간 왕복 삽입 연산 추가`

---

### Task 4: SavedCourse + CourseRepositoryProtocol + SwiftData 어댑터

**Files:**
- Create: `Trace/Domain/CoursePlanning/Entity/SavedCourse.swift`
- Create: `Trace/Domain/CoursePlanning/Protocol/CourseRepositoryProtocol.swift`
- Create: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift`
- Create: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceModels.swift`
- Create: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataCourseRepository.swift`
- Test: `TraceTests/SwiftDataCourseRepositoryTests.swift` (새 파일)

**Interfaces:**
- Consumes: `CourseDraft`(Task 2), `CourseSegment`(Task 1)
- Produces:
  - `struct SavedCourse: Identifiable, Equatable, Sendable { let id: UUID; var name: String; let createdAt: Date; var segments: [CourseSegment]; var distanceMeters: Double }`
  - `protocol CourseRepositoryProtocol: Sendable { saveDraft/loadDraft/saveCourse/fetchCourses/deleteCourse }`
  - `actor SwiftDataCourseRepository: CourseRepositoryProtocol` — `init(inMemory: Bool = false)`
  - Task 5·6의 ViewModel/DI가 프로토콜 타입으로 사용

- [ ] **Step 1: 도메인 타입 작성** — `SavedCourse.swift`:

```swift
import Foundation

// 이름 붙여 저장한 코스 — 스냅샷 의미론: 저장 후 세션 편집과 무관하게 불변 (MVP11 스펙 §2)
struct SavedCourse: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var segments: [CourseSegment]

    var distanceMeters: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }
}
```

`CourseRepositoryProtocol.swift`:

```swift
import Foundation

// 코스 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다 — 도메인·ViewModel은
// 저장 방식을 모른다 (MVP11 스펙 §2). 초안 삭제는 빈 스냅샷 저장으로 표현한다.
protocol CourseRepositoryProtocol: Sendable {
    func saveDraft(_ draft: CourseDraft) async throws
    // 손상·부재 시 nil (크래시 금지, 스펙 §2 실패 처리)
    func loadDraft() async -> CourseDraft?
    func saveCourse(_ course: SavedCourse) async throws
    // 최신순 정렬. 손상 행은 건너뛰고 나머지 반환 (스펙 §2)
    func fetchCourses() async -> [SavedCourse]
    func deleteCourse(id: UUID) async throws
}
```

- [ ] **Step 2: 실패하는 테스트 작성** — `TraceTests/SwiftDataCourseRepositoryTests.swift` (새 파일):

```swift
import XCTest
@testable import Trace

final class SwiftDataCourseRepositoryTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func sampleDraft() -> CourseDraft {
        let segID = UUID()
        return CourseDraft(
            entries: [
                CourseDraft.Entry(
                    id: segID, order: 0, placedAtFront: false, anchorID: nil,
                    segment: .tapped(
                        coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                    )
                ),
                CourseDraft.Entry(
                    id: UUID(), order: 1, placedAtFront: false, anchorID: segID,
                    segment: .roundTrip(
                        coordinates: [coord(37.51, 127.00), coord(37.50, 127.00), coord(37.51, 127.00)],
                        distanceMeters: 2000
                    )
                )
            ],
            nextOrder: 2
        )
    }

    func testDraft_saveLoad_roundTripsAllFields() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let draft = sampleDraft()
        try await repo.saveDraft(draft)
        let loaded = await repo.loadDraft()
        XCTAssertEqual(loaded, draft) // id·order·placedAtFront·anchorID·세그먼트 케이스 전부 보존
    }

    func testDraft_secondSaveOverwritesFirst() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        try await repo.saveDraft(sampleDraft())
        try await repo.saveDraft(.empty)
        let loaded = await repo.loadDraft()
        XCTAssertEqual(loaded, .empty) // 단일 슬롯 — 마지막 저장이 이긴다
    }

    func testDraft_loadWithoutSave_returnsNil() async {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let loaded = await repo.loadDraft()
        XCTAssertNil(loaded)
    }

    func testCourses_saveFetchDelete() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let older = SavedCourse(
            id: UUID(), name: "한강 5km", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 5000)]
        )
        let newer = SavedCourse(
            id: UUID(), name: "남산 왕복", createdAt: Date(timeIntervalSince1970: 2000),
            segments: [.drawn(coordinates: [coord(37.55, 126.99), coord(37.56, 126.99)], distanceMeters: 3000)]
        )
        try await repo.saveCourse(older)
        try await repo.saveCourse(newer)

        let fetched = await repo.fetchCourses()
        XCTAssertEqual(fetched.map(\.id), [newer.id, older.id]) // 최신순
        XCTAssertEqual(fetched.first?.name, "남산 왕복")
        XCTAssertEqual(fetched.last?.segments, older.segments)

        try await repo.deleteCourse(id: older.id)
        let afterDelete = await repo.fetchCourses()
        XCTAssertEqual(afterDelete.map(\.id), [newer.id])
    }

    func testCourses_duplicateNamesAllowed() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let a = SavedCourse(
            id: UUID(), name: "아침 코스", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        let b = SavedCourse(
            id: UUID(), name: "아침 코스", createdAt: Date(timeIntervalSince1970: 2000),
            segments: a.segments
        )
        try await repo.saveCourse(a)
        try await repo.saveCourse(b)
        let fetched = await repo.fetchCourses()
        XCTAssertEqual(fetched.count, 2) // 같은 이름 중복 허용 (스펙 §2)
    }

    func testDecodeDraft_garbageData_returnsNil() {
        let garbage = Data("not json".utf8)
        XCTAssertNil(SwiftDataCourseRepository.decodeDraft(garbage)) // 손상 blob → nil (스펙 §2)
    }

    func testDecodeCourse_futureVersion_returnsNil() throws {
        // version=999 blob — 미래 포맷은 손상과 동일하게 취급 (스펙 §2 버전 필드)
        let payload = Data(#"{"version":999,"segments":[]}"#.utf8)
        XCTAssertNil(SwiftDataCourseRepository.decodeCourseSegments(payload))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인** — 컴파일 에러로 실패 확인.
- [ ] **Step 4: DTO 구현** — `CoursePersistenceDTO.swift`:

```swift
import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (MVP11 스펙 §2).
enum CoursePersistenceDTO {
    static let currentVersion = 1

    struct Coordinate: Codable {
        let lat: Double
        let lon: Double
    }

    struct Segment: Codable {
        enum Kind: String, Codable {
            case tapped, drawn, roundTrip
        }
        let kind: Kind
        let coordinates: [Coordinate]
        let distanceMeters: Double
    }

    struct DraftEntry: Codable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        let segment: Segment
    }

    struct Draft: Codable {
        let version: Int
        let entries: [DraftEntry]
        let nextOrder: Int
    }

    struct Course: Codable {
        let version: Int
        let segments: [Segment]
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension CoursePersistenceDTO.Coordinate {
    init(_ c: CourseCoordinate) {
        self.init(lat: c.latitude, lon: c.longitude)
    }
    var domain: CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }
}

extension CoursePersistenceDTO.Segment {
    init(_ segment: CourseSegment) {
        let coords = segment.coordinates.map(CoursePersistenceDTO.Coordinate.init)
        switch segment {
        case .tapped(_, let d):    self.init(kind: .tapped, coordinates: coords, distanceMeters: d)
        case .drawn(_, let d):     self.init(kind: .drawn, coordinates: coords, distanceMeters: d)
        case .roundTrip(_, let d): self.init(kind: .roundTrip, coordinates: coords, distanceMeters: d)
        }
    }

    var domain: CourseSegment {
        let coords = coordinates.map(\.domain)
        switch kind {
        case .tapped:    return .tapped(coordinates: coords, distanceMeters: distanceMeters)
        case .drawn:     return .drawn(coordinates: coords, distanceMeters: distanceMeters)
        case .roundTrip: return .roundTrip(coordinates: coords, distanceMeters: distanceMeters)
        }
    }
}

extension CoursePersistenceDTO.Draft {
    init(_ draft: CourseDraft) {
        self.init(
            version: CoursePersistenceDTO.currentVersion,
            entries: draft.entries.map {
                CoursePersistenceDTO.DraftEntry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, segment: CoursePersistenceDTO.Segment($0.segment)
                )
            },
            nextOrder: draft.nextOrder
        )
    }

    var domain: CourseDraft {
        CourseDraft(
            entries: entries.map {
                CourseDraft.Entry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, segment: $0.segment.domain
                )
            },
            nextOrder: nextOrder
        )
    }
}
```

- [ ] **Step 5: SwiftData 모델 구현** — `CoursePersistenceModels.swift`:

```swift
import Foundation
import SwiftData

// 어댑터 내부 전용 — 이 파일 밖(App/Domain/Pages)에서 import SwiftData 금지 (MVP11 스펙 §2)

@Model
final class DraftRecord {
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date) {
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class CourseRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var payload: Data

    init(id: UUID, name: String, createdAt: Date, payload: Data) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.payload = payload
    }
}
```

- [ ] **Step 6: 어댑터 구현** — `SwiftDataCourseRepository.swift`:

```swift
import Foundation
import SwiftData

// SwiftData 어댑터. actor 직렬화로 "저장은 연산 순서대로"의 실행부를 담당한다
// (호출 순서 보장은 ViewModel의 Task 체인 — 스펙 §2 순서 불변식).
actor SwiftDataCourseRepository: CourseRepositoryProtocol {
    enum RepositoryError: Error {
        case storeUnavailable
    }

    private let context: ModelContext?

    init(inMemory: Bool = false) {
        self.context = Self.makeContext(inMemory: inMemory)
    }

    // 컨테이너 생성 실패 정책 (스펙 §2): ① 정상 생성 → ② 스토어 파일을 백업으로 옮기고 재생성
    // (자산 즉시 삭제 금지) → ③ in-memory 폴백 → ④ nil(모든 연산 no-op/throw).
    // 어떤 경우에도 앱은 뜬다 — 런치 크래시 금지.
    private static func makeContext(inMemory: Bool) -> ModelContext? {
        let schema = Schema([DraftRecord.self, CourseRecord.self])

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "TraceCourseStore.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        // 스토어 손상 추정 — 백업 이름으로 옮기고 새로 생성
        let backupURL = storeURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).bak")
        try? FileManager.default.moveItem(at: storeURL, to: backupURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) else { return nil }
        return ModelContext(container)
    }

    // MARK: - Draft (단일 슬롯)

    func saveDraft(_ draft: CourseDraft) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let payload = try JSONEncoder().encode(CoursePersistenceDTO.Draft(draft))
        var descriptor = FetchDescriptor<DraftRecord>()
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.payload = payload
            record.updatedAt = Date()
        } else {
            context.insert(DraftRecord(payload: payload, updatedAt: Date()))
        }
        try context.save()
    }

    func loadDraft() async -> CourseDraft? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<DraftRecord>()
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        guard let draft = Self.decodeDraft(record.payload) else {
            // 손상 초안은 버린다 (스펙 §2)
            context.delete(record)
            try? context.save()
            return nil
        }
        return draft
    }

    // MARK: - Saved Courses

    func saveCourse(_ course: SavedCourse) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let dto = CoursePersistenceDTO.Course(
            version: CoursePersistenceDTO.currentVersion,
            segments: course.segments.map(CoursePersistenceDTO.Segment.init)
        )
        let payload = try JSONEncoder().encode(dto)
        context.insert(CourseRecord(
            id: course.id, name: course.name, createdAt: course.createdAt, payload: payload
        ))
        try context.save()
    }

    func fetchCourses() async -> [SavedCourse] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<CourseRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        // 손상 행은 건너뛰고 나머지 반환 (스펙 §2 — 행 삭제는 하지 않는다, 사용자 자산)
        return records.compactMap { record in
            guard let segments = Self.decodeCourseSegments(record.payload) else { return nil }
            return SavedCourse(
                id: record.id, name: record.name, createdAt: record.createdAt, segments: segments
            )
        }
    }

    func deleteCourse(id: UUID) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<CourseRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - Decode (테스트 가능한 손상 처리 경로)

    static func decodeDraft(_ data: Data) -> CourseDraft? {
        guard let dto = try? JSONDecoder().decode(CoursePersistenceDTO.Draft.self, from: data),
              dto.version <= CoursePersistenceDTO.currentVersion else { return nil }
        return dto.domain
    }

    static func decodeCourseSegments(_ data: Data) -> [CourseSegment]? {
        guard let dto = try? JSONDecoder().decode(CoursePersistenceDTO.Course.self, from: data),
              dto.version <= CoursePersistenceDTO.currentVersion else { return nil }
        return dto.segments.map(\.domain)
    }
}
```

- [ ] **Step 7: 테스트 통과 확인** — 전체 테스트 PASS.
- [ ] **Step 8: 격리 확인** — `grep -rn "import SwiftData" Trace --include="*.swift"` 결과가 `Trace/Infrastructure/Persistence/SwiftData/` 아래 2개 파일뿐이어야 한다.
- [ ] **Step 9: 커밋** — `feat: SwiftData 코스 저장소 어댑터 추가`

---

### Task 5: DI 배선 + 초안 자동 저장·복원 (ViewModel)

**Files:**
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `Trace/App/TraceApp.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (init, `.task`, scenePhase)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Test: `TraceTests/CoursePlannerViewModelPersistenceTests.swift` (새 파일)

**Interfaces:**
- Consumes: Task 2 `snapshot()`/`restore(from:)`, Task 4 `CourseRepositoryProtocol`/`SwiftDataCourseRepository`
- Produces (Task 6·7이 사용):
  - `CoursePlannerPageViewModel.init(coursePlanningService:locationService:cameraStateStore:courseRepository:)`
  - `func bootstrapDraft() async` — 앱 시작 복원
  - `func persistDraft()` — 직렬 Task 체인 저장 (편집 연산 확정 시 호출)
  - `func flushDraftSaves() async` — 대기 중 저장 완료 대기 (테스트·scenePhase용)
  - `MockCourseRepository` (테스트 파일 내 정의, Task 6 테스트도 같은 파일 사용)

- [ ] **Step 1: 실패하는 테스트 작성** — `TraceTests/CoursePlannerViewModelPersistenceTests.swift` (새 파일):

```swift
import XCTest
@testable import Trace

// Task 5·6 공용 목 저장소
actor MockCourseRepository: CourseRepositoryProtocol {
    var savedDrafts: [CourseDraft] = []
    var stubbedDraft: CourseDraft?
    var savedCourses: [SavedCourse] = []
    var draftSaveError: Error?

    func setStubbedDraft(_ draft: CourseDraft?) { stubbedDraft = draft }
    func setDraftSaveError(_ error: Error?) { draftSaveError = error }

    func saveDraft(_ draft: CourseDraft) async throws {
        if let draftSaveError { throw draftSaveError }
        savedDrafts.append(draft)
    }
    func loadDraft() async -> CourseDraft? { stubbedDraft }
    func saveCourse(_ course: SavedCourse) async throws { savedCourses.append(course) }
    func fetchCourses() async -> [SavedCourse] {
        savedCourses.sorted { $0.createdAt > $1.createdAt }
    }
    func deleteCourse(id: UUID) async throws {
        savedCourses.removeAll { $0.id == id }
    }
}

struct StubError: Error {}

@MainActor
final class CoursePlannerViewModelPersistenceTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func makeViewModel(repo: MockCourseRepository) -> CoursePlannerPageViewModel {
        CoursePlannerPageViewModel(
            coursePlanningService: StubPlannerService(),
            locationService: StubLocationService(),
            courseRepository: repo
        )
    }

    private func draftWithOneSegment() -> CourseDraft {
        CourseDraft(
            entries: [CourseDraft.Entry(
                id: UUID(), order: 0, placedAtFront: false, anchorID: nil,
                segment: .tapped(
                    coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                )
            )],
            nextOrder: 1
        )
    }

    func testBootstrapDraft_restoresSession() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        XCTAssertEqual(vm.course?.segments.count, 1)
        XCTAssertEqual(vm.course?.distanceMeters, 1000)
    }

    func testBootstrapDraft_nilDraft_keepsEmptySession() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        XCTAssertNil(vm.course)
    }

    func testUndo_persistsDraftSnapshot() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved[0].isEmpty) // undo로 비워진 상태가 저장됨
    }

    func testClear_persistsEmptyDraft() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        vm.clear()
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.last?.isEmpty, true) // 초기화 = 빈 스냅샷 저장 (clearDraft 대체)
    }

    func testPersistDraft_savesInOperationOrder() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()   // 빈 스냅샷 (entries 0)
        vm.redo()         // 복구 스냅샷 (entries 1)
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.map(\.entries.count), [0, 1]) // 연산 순서 보존 (스펙 §2 순서 불변식)
    }

    func testDraftSaveFailure_threeConsecutive_notifiesOnce() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        await repo.setDraftSaveError(StubError())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()
        vm.redo()
        await vm.undo()
        await vm.flushDraftSaves()

        XCTAssertNotNil(vm.errorMessage) // 3회 연속 실패 → 1회 알림 (스펙 §2)

        // 4번째 실패는 다시 알리지 않는다 (세션당 1회) — 메시지가 그대로임으로 확인
        let message = vm.errorMessage
        vm.redo()
        await vm.flushDraftSaves()
        XCTAssertEqual(vm.errorMessage, message)
    }
}

private final class StubPlannerService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}

private final class StubLocationService: LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate {
        CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러(init 파라미터·메서드 없음)로 실패 확인.
- [ ] **Step 3: ViewModel 구현** — `CoursePlannerPageViewModel.swift` 수정:

저장소 프로퍼티·init (기존 init 교체 — `cameraStateStore` 기본값 유지):

```swift
    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private let courseRepository: CourseRepositoryProtocol
    private var recomputeGeneration = 0

    // 초안 저장 직렬화: 이전 저장을 await한 뒤 다음 저장 — 연산 순서 보장 (스펙 §2 순서 불변식)
    private var draftSaveTask: Task<Void, Never>?
    private var draftSaveFailureCount = 0
    private var didNotifyDraftSaveFailure = false
    static let draftSaveFailureNotifyThreshold = 3

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore(),
        courseRepository: CourseRepositoryProtocol
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
        self.courseRepository = courseRepository
    }
```

초안 복원·저장 메서드 추가 (`// MARK: - Draft Persistence` 섹션):

```swift
    // MARK: - Draft Persistence (MVP11 스펙 §3)

    // 앱 시작 시 1회: 초안이 있으면 세션 복원 — "껐다 켜면 마지막 모습 그대로"
    func bootstrapDraft() async {
        guard let draft = await courseRepository.loadDraft(), !draft.isEmpty else { return }
        session.restore(from: draft)
    }

    // 편집 연산 확정 시마다 호출. 스냅샷은 호출 시점(연산 직후)에 동기로 뜨고,
    // 쓰기는 이전 쓰기를 await한 뒤 실행 — 디스크 도달 순서 = 연산 순서.
    func persistDraft() {
        let draft = session.snapshot()
        let previous = draftSaveTask
        draftSaveTask = Task { [courseRepository] in
            await previous?.value
            do {
                try await courseRepository.saveDraft(draft)
                self.draftSaveFailureCount = 0
            } catch {
                self.recordDraftSaveFailure()
            }
        }
    }

    // 대기 중인 저장 완료 대기 — scenePhase background 안전망·테스트에서 사용
    func flushDraftSaves() async {
        await draftSaveTask?.value
    }

    private func recordDraftSaveFailure() {
        draftSaveFailureCount += 1
        guard draftSaveFailureCount >= Self.draftSaveFailureNotifyThreshold,
              !didNotifyDraftSaveFailure else { return }
        didNotifyDraftSaveFailure = true
        errorMessage = "코스 자동 저장이 계속 실패하고 있습니다. 저장 공간을 확인해주세요."
    }
```

편집 연산 확정 지점에 `persistDraft()` 삽입 — 정확히 다음 5곳:

1. `routeAndAttach`: `try await session.attach(segment, using: coursePlanningService)` 성공 직후(`selectedSegmentIndex = nil` 다음 줄)
2. `routeStrokeAndAttach`: 동일 위치
3. `undo()`: `session.undo()` 다음
4. `redo()`: `session.redo()` 다음
5. `clear()`: `session.clear()` 다음

- [ ] **Step 4: DI·Page 배선** — `DependencyContainer.swift`:

```swift
struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol
    let cameraStateStore: CameraStateStore
    let courseRepository: CourseRepositoryProtocol

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService(),
            cameraStateStore: CameraStateStore(),
            courseRepository: SwiftDataCourseRepository()
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        let uiTestingDefaults = UserDefaults(suiteName: "uiTesting") ?? .standard
        return DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService(),
            cameraStateStore: CameraStateStore(defaults: uiTestingDefaults),
            // in-memory: UI 테스트는 런치마다 빈 상태에서 시작 (기존 UI 테스트 전제 보존)
            courseRepository: SwiftDataCourseRepository(inMemory: true)
        )
    }
}
```

`TraceApp.swift` — `CoursePlannerPage` 호출에 `courseRepository: container.courseRepository` 추가. `CoursePlannerPage.swift` — init 파라미터 추가 후 ViewModel로 전달, Preview도 동일 수정:

```swift
    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore(),
        courseRepository: CourseRepositoryProtocol
    ) {
        self.cameraStateStore = cameraStateStore
        _viewModel = State(initialValue: CoursePlannerPageViewModel(
            coursePlanningService: coursePlanningService,
            locationService: locationService,
            cameraStateStore: cameraStateStore,
            courseRepository: courseRepository
        ))
    }
```

`.task`의 첫 줄에 초안 복원 추가 (카메라 복원과 bootstrapLocation보다 먼저 — 로컬 로드는 ms 단위라 빈 지도 노출은 무시 가능, 스펙 §7 결정):

```swift
            .task {
                await viewModel.bootstrapDraft()
                if let bounds = cameraStateStore.restore() {
                // ... 이하 기존 그대로
```

scenePhase 핸들러에 초안 안전망 저장 추가:

```swift
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    saveCameraPosition()
                    viewModel.persistDraft()
                }
            }
```

- [ ] **Step 5: 테스트 통과 확인** — 전체 테스트 PASS. 기존 `CoursePlannerViewModelTests.swift`가 init 변경으로 컴파일 실패하면, 해당 파일의 ViewModel 생성부에 `courseRepository: MockCourseRepository()`를 추가한다 (MockCourseRepository는 이 태스크의 테스트 파일에 internal로 정의됨).
- [ ] **Step 6: 커밋** — `feat: 초안 자동 저장·복원 배선`

---

### Task 6: 이름 저장 / 목록 / 불러오기 / 삭제 (ViewModel + UI)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`
- Create: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+CourseListComponent.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (sheet·알럿 연결)
- Test: `TraceTests/CoursePlannerViewModelPersistenceTests.swift` (기존 파일에 추가)

**Interfaces:**
- Consumes: Task 4 저장소, Task 5 `persistDraft()`, Task 2 `session.load(segments:)`
- Produces: ViewModel — `canSaveCourse`, `savedCourses`, `isCourseListPresented`, `isSavePromptPresented`, `courseNameInput`, `pendingLoadCourse`, `saveCurrentCourse()`, `presentCourseList()`, `requestLoad(_:)`, `confirmPendingLoad()`, `deleteSavedCourse(_:)`

- [ ] **Step 1: 실패하는 테스트 작성** — `CoursePlannerViewModelPersistenceTests.swift`에 추가:

```swift
    func testSaveCurrentCourse_savesSnapshotWithTrimmedName() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        vm.courseNameInput = "  한강 5km  "
        await vm.saveCurrentCourse()

        let saved = await repo.savedCourses
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "한강 5km")
        XCTAssertEqual(saved.first?.segments, vm.course?.segments)
    }

    func testSaveCurrentCourse_emptyNameOrCourse_doesNothing() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        vm.courseNameInput = "이름"
        await vm.saveCurrentCourse() // 코스 없음
        vm.courseNameInput = "   "
        await vm.saveCurrentCourse() // 이름 없음(코스도 없지만 이름 가드 선행)
        let saved = await repo.savedCourses
        XCTAssertTrue(saved.isEmpty)
    }

    func testPresentCourseList_loadsCoursesNewestFirst() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let older = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        let newer = SavedCourse(
            id: UUID(), name: "B", createdAt: Date(timeIntervalSince1970: 2000), segments: older.segments
        )
        try? await repo.saveCourse(older)
        try? await repo.saveCourse(newer)

        await vm.presentCourseList()

        XCTAssertTrue(vm.isCourseListPresented)
        XCTAssertEqual(vm.savedCourses.map(\.name), ["B", "A"])
    }

    func testRequestLoad_emptySession_loadsImmediately() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        await vm.requestLoad(saved)
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 1) // 불러오기도 초안으로 저장됨 (스펙 §3 트리거)
    }

    func testRequestLoad_nonEmptySession_asksConfirmationThenReplaces() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [
                .drawn(coordinates: [coord(37.55, 126.99), coord(37.56, 126.99)], distanceMeters: 3000)
            ]
        )

        await vm.requestLoad(saved)
        XCTAssertEqual(vm.pendingLoadCourse, saved) // 즉시 교체 아님 — 확인 대기
        XCTAssertNotEqual(vm.course?.segments, saved.segments)

        await vm.confirmPendingLoad()
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
        XCTAssertFalse(vm.isCourseListPresented) // 불러오면 시트 닫힘
    }

    func testDeleteSavedCourse_removesFromRepositoryAndList() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        try? await repo.saveCourse(saved)
        await vm.presentCourseList()
        XCTAssertEqual(vm.savedCourses.count, 1)

        await vm.deleteSavedCourse(saved)

        XCTAssertTrue(vm.savedCourses.isEmpty)
        let remaining = await repo.savedCourses
        XCTAssertTrue(remaining.isEmpty)
    }
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러로 실패 확인.
- [ ] **Step 3: ViewModel 구현** — `CoursePlannerPageViewModel.swift`에 추가:

```swift
    // MARK: - Saved Courses (MVP11 스펙 §3)

    private(set) var savedCourses: [SavedCourse] = []
    var isCourseListPresented = false
    var isSavePromptPresented = false
    var courseNameInput = ""
    private(set) var pendingLoadCourse: SavedCourse?

    var canSaveCourse: Bool { course != nil }

    // 스냅샷 의미론: 저장 시점의 세그먼트를 복사 — 이후 편집과 무관 (스펙 §2)
    func saveCurrentCourse() async {
        let name = courseNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let course = session.course else { return }
        let saved = SavedCourse(id: UUID(), name: name, createdAt: Date(), segments: course.segments)
        do {
            try await courseRepository.saveCourse(saved)
            infoMessage = "'\(name)' 저장됨"
            courseNameInput = ""
        } catch {
            errorMessage = "코스 저장에 실패했습니다."
        }
    }

    func presentCourseList() async {
        savedCourses = await courseRepository.fetchCourses()
        isCourseListPresented = true
    }

    // 작업 중 코스가 있으면 교체 확인을 거친다 (스펙 §3)
    func requestLoad(_ saved: SavedCourse) async {
        if course == nil {
            applyLoadedCourse(saved)
        } else {
            pendingLoadCourse = saved
        }
    }

    func confirmPendingLoad() async {
        guard let saved = pendingLoadCourse else { return }
        pendingLoadCourse = nil
        applyLoadedCourse(saved)
    }

    func cancelPendingLoad() {
        pendingLoadCourse = nil
    }

    // 스와이프 삭제는 확인 알럿을 거친다 (스펙 §3)
    private(set) var pendingDeleteCourse: SavedCourse?

    func requestDelete(_ saved: SavedCourse) {
        pendingDeleteCourse = saved
    }

    func confirmPendingDelete() async {
        guard let saved = pendingDeleteCourse else { return }
        pendingDeleteCourse = nil
        await deleteSavedCourse(saved)
    }

    func cancelPendingDelete() {
        pendingDeleteCourse = nil
    }

    func deleteSavedCourse(_ saved: SavedCourse) async {
        do {
            try await courseRepository.deleteCourse(id: saved.id)
            savedCourses.removeAll { $0.id == saved.id }
        } catch {
            errorMessage = "코스 삭제에 실패했습니다."
        }
    }

    private func applyLoadedCourse(_ saved: SavedCourse) {
        session.load(segments: saved.segments)
        pendingTapStart = nil
        selectedSegmentIndex = nil
        errorMessage = nil
        infoMessage = nil
        isCourseListPresented = false
        persistDraft()
    }
```

- [ ] **Step 4: UI 구현** — `CoursePlannerPage+ControlsComponent.swift`의 HStack 끝(초기화 버튼 뒤)에 추가:

```swift
            Button {
                viewModel.isSavePromptPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!viewModel.canSaveCourse)
            .accessibilityIdentifier("coursePlanner.saveCourse")

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityIdentifier("coursePlanner.courseList")
```

`CoursePlannerPage+CourseListComponent.swift` (새 파일):

```swift
import SwiftUI

extension CoursePlannerPage {
    var courseListSheet: some View {
        NavigationStack {
            Group {
                if viewModel.savedCourses.isEmpty {
                    ContentUnavailableView(
                        "저장된 코스가 없습니다",
                        systemImage: "map",
                        description: Text("코스를 만들고 저장 버튼을 눌러보세요")
                    )
                } else {
                    savedCourseList
                }
            }
            .navigationTitle("저장된 코스")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var savedCourseList: some View {
        List {
            ForEach(viewModel.savedCourses) { course in
                Button {
                    Task { await viewModel.requestLoad(course) }
                } label: {
                    savedCourseRow(course)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coursePlanner.savedCourse.\(course.name)")
            }
            .onDelete { indexSet in
                // 즉시 삭제하지 않고 확인 알럿을 띄운다 (스펙 §3)
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.savedCourses[first])
            }
        }
        .alert(
            "코스를 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteCourse != nil },
                set: { if !$0 { viewModel.cancelPendingDelete() } }
            )
        ) {
            Button("삭제", role: .destructive) { Task { await viewModel.confirmPendingDelete() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingDelete() }
        } message: {
            Text(viewModel.pendingDeleteCourse.map { "'\($0.name)'은(는) 되돌릴 수 없습니다" } ?? "")
        }
    }

    private func savedCourseRow(_ course: SavedCourse) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.body.weight(.semibold))
                Text(course.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.2f km", course.distanceMeters / 1000))
                .font(.callout.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}
```

`CoursePlannerPage.swift`의 body 모디파이어 체인(기존 `.alert("위치 권한…")` 뒤)에 추가:

```swift
            .sheet(isPresented: $viewModel.isCourseListPresented) {
                courseListSheet
            }
            .alert("코스 이름", isPresented: $viewModel.isSavePromptPresented) {
                TextField("예: 한강 5km", text: $viewModel.courseNameInput)
                Button("저장") { Task { await viewModel.saveCurrentCourse() } }
                Button("취소", role: .cancel) { viewModel.courseNameInput = "" }
            } message: {
                Text("현재 코스를 저장합니다")
            }
            .alert(
                "지금 만들던 코스를 대체할까요?",
                isPresented: Binding(
                    get: { viewModel.pendingLoadCourse != nil },
                    set: { if !$0 { viewModel.cancelPendingLoad() } }
                )
            ) {
                Button("대체", role: .destructive) { Task { await viewModel.confirmPendingLoad() } }
                Button("취소", role: .cancel) { viewModel.cancelPendingLoad() }
            } message: {
                Text("작업 중인 코스는 사라집니다")
            }
```

- [ ] **Step 5: 테스트 통과 확인** — 전체 테스트 PASS.
- [ ] **Step 6: 시뮬레이터 스모크** — XcodeBuildMCP `build_run_sim`으로 실행(테스트 실행 아님 — test_sim 금지), 저장 버튼 → 이름 알럿 → 목록 시트 → 불러오기 확인 알럿 흐름을 스크린샷으로 확인.
- [ ] **Step 7: 커밋** — `feat: 코스 이름 저장·목록·불러오기·삭제 UI 추가`

---

### Task 7: 구간 패널 왕복 버튼 + 왕복 표식

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift` (`segmentRow`)
- Test: `TraceTests/CoursePlannerViewModelPersistenceTests.swift` (기존 파일에 추가)

**Interfaces:**
- Consumes: Task 3 `insertRoundTrip(afterOrder:)`/`canInsertRoundTrip(afterOrder:)` (order = 패널의 colorKey), Task 5 `persistDraft()`
- Produces: `viewModel.insertRoundTrip(afterColorKey:)`, `viewModel.canInsertRoundTrip(afterColorKey:)`

- [ ] **Step 1: 실패하는 테스트 작성** — `CoursePlannerViewModelPersistenceTests.swift`에 추가:

```swift
    func testInsertRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        XCTAssertTrue(vm.canInsertRoundTrip(afterColorKey: 0))
        vm.insertRoundTrip(afterColorKey: 0)

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 3000) // 1000 + 2000
        XCTAssertNil(vm.selectedSegmentIndex)

        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 2) // 왕복 삽입도 초안 저장 트리거 (스펙 §3)
    }

    func testCanInsertRoundTrip_unknownKey_false() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        XCTAssertFalse(vm.canInsertRoundTrip(afterColorKey: 0)) // 빈 코스
    }
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러로 실패 확인.
- [ ] **Step 3: ViewModel 구현** — `CoursePlannerPageViewModel.swift`에 추가 (`// MARK: - Segment selection` 근처):

```swift
    // MARK: - Round Trip (MVP11 스펙 §4) — colorKey = 세션 order

    func canInsertRoundTrip(afterColorKey key: Int) -> Bool {
        session.canInsertRoundTrip(afterOrder: key)
    }

    func insertRoundTrip(afterColorKey key: Int) {
        infoMessage = nil
        session.insertRoundTrip(afterOrder: key)
        selectedSegmentIndex = nil
        persistDraft()
    }
```

- [ ] **Step 4: 패널 행 UI** — `CoursePlannerPage+SegmentPanelComponent.swift`의 `segmentRow`를 다음으로 교체 (왕복 표식 + 왕복 버튼 추가):

```swift
    private func segmentRow(_ row: PanelRow) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectSegment(at: row.index)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                        .frame(width: 10, height: 10)
                    Text("\(row.index + 1)")
                        .font(.caption.weight(.semibold))
                    if row.segment.isRoundTrip {
                        // 왕복 구간 표식 — 저장·불러오기를 통과해도 유지된다 (스펙 §4)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("왕복 구간")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0fm", row.segment.distanceMeters))
                            .font(.caption)
                        Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: row.index) / 1000))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(row.index)")

            // 왕복 추가: 이 구간 뒤에 "갔다 되돌아오기" 삽입 (스펙 §4)
            Button {
                viewModel.insertRoundTrip(afterColorKey: row.colorKey)
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInsertRoundTrip(afterColorKey: row.colorKey))
            .accessibilityIdentifier("coursePlanner.segmentPanel.roundTrip.\(row.index)")
        }
    }
```

- [ ] **Step 5: 테스트 통과 확인** — 전체 테스트 PASS.
- [ ] **Step 6: 시뮬레이터 스모크** — `build_run_sim`: 구간 2개 코스 생성 → 패널 펼침 → 중간 구간 왕복 버튼 탭 → 지도 경로·총 거리(해당 구간 2배 증가)·패널 왕복 표식 스크린샷 확인. 되돌리기 1회로 원상복구 확인.
- [ ] **Step 7: 커밋** — `feat: 구간 패널 왕복 추가 버튼·표식 구현`

---

### Task 8: 통합 검증 + 마무리

**Files:**
- Modify: `docs/roadmap.md` (마일스톤 체크박스)
- Create: `docs/qa/2026-07-XX-course-save-roundtrip-device-checklist.md` (실행 날짜로)

**Interfaces:**
- Consumes: Task 1~7 전부
- Produces: 검증 완료 상태 + 실기기 QA 체크리스트

- [ ] **Step 1: 전체 검증 3종** — Global Constraints의 빌드/테스트/린트 명령을 순서대로 실행, 각 통과 시 스탬프 갱신. 실패 시 수정 후 재실행 (임의 테스트 스킵 금지).
- [ ] **Step 2: 시뮬레이터 통합 스모크** — `build_run_sim`으로 핵심 왕복 시나리오 1회: 코스 생성 → 왕복 추가 → 이름 저장 → 초기화 → 목록에서 불러오기(왕복 표식 유지 확인) → 앱 종료 후 재실행(`stop_app_sim` → `launch_app_sim`) → 코스 그대로 복원 확인. 각 단계 스크린샷.
- [ ] **Step 3: 실기기 QA 체크리스트 작성** — `docs/agent-rules/testing.md`의 시나리오 카드 템플릿(쉬운 말 규칙 — 헤딩/인트로/푸터 포함)으로 작성. 필수 시나리오: ① 그리다 앱 완전 종료 → 다시 열면 그대로 + 뒤로가기 동작 ② 초기화 후 종료 → 빈 상태 시작 ③ 이름 저장 → 목록 → 작업 중 불러오기 확인창 → 삭제 ④ 중간 구간 왕복 추가 → 거리 2배 증가 → 뒤로가기 한 번에 취소 ⑤ 왕복 포함 코스 저장 → 불러오기 → 왕복 표식 유지.
- [ ] **Step 4: roadmap 갱신** — `docs/roadmap.md` MVP11의 `course-save`·`roundtrip-insert`를 `[x]`로.
- [ ] **Step 5: 커밋** — `docs: MVP11 실기기 QA 체크리스트 작성 + roadmap 갱신`
- [ ] **Step 6: 사용자에게 보고** — 실기기 QA 체크리스트 제시 + 병합은 사용자 확인 후 `scripts/trace-integrate.sh` (push는 사용자 직접).
