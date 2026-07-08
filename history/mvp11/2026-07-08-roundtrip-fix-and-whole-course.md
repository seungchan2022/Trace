# 왕복 버그 수정 + 전체 왕복 추가 Implementation Plan

> 완료(소급 확인, 2026-07-08): 전 스텝 구현 완료 — 근거 커밋 `e57e1cb`(왕복 버그 수정+전체 왕복),
> `d8b5334`(ViewModel 전체 왕복 노출), `e240e97`(컨트롤 바 버튼), `90c8b5e`(스펙 정정) + roadmap의
> "둘 다 완료" 기록과 실기기 QA 통과(2026-07-08). 체크박스는 실행 당시 미갱신.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MVP11 실기기 QA에서 발견된 "왕복 추가" 버튼의 거리·연결 버그를 고치고(중간 구간은 막고, 자유 끝 구간만 정확히 2× 거리로 동작하게), 코스 전체를 한 번에 왕복시키는 새 "전체 왕복" 버튼을 추가한다.

**Architecture:** `CourseEditSession.insertRoundTrip`을 "대상 구간의 역방향만 자유 끝에 붙이기"로 단순화하고(기존의 역+정 병합 방식 폐기), 코스의 자유 끝(맨 앞/맨 뒤)에서만 허용한다. redo 위치 복원을 위해 기존 anchor 메커니즘에 "anchor 앞/뒤" 방향 정보(`anchorInsertsBefore`)를 추가한다. 별개로 "전체 왕복"은 anchor 추적이 필요 없는 단순 append(코스 전체 좌표를 뒤집어 맨 뒤에 붙이는 것뿐이라 anchor 없이 undo/redo가 기존 규칙 그대로 동작).

**Tech Stack:** Swift 6, SwiftUI, MVVM, XCTest.

## Global Constraints

- 브랜치: 기존 `feature/course-save-roundtrip`에서 계속 진행 (새 브랜치 없음).
- 왕복 버튼은 코스의 자유 끝 구간(공간순 배열의 첫 번째 또는 마지막 엔트리)에서만 활성화된다. 중간 구간에서는 `canInsertRoundTrip`이 `false`를 반환한다 — 반대쪽이 다른 구간과 이어져 있어 그 구간만 되짚으면 코스가 끊기기 때문 (2026-07-08 실기기 QA + 어드바이저 검토로 확정, 이전 "역+정 병합" 설계를 대체).
- 왕복으로 삽입되는 세그먼트는 대상 구간의 좌표를 그대로 뒤집은 것뿐이다(`CourseSegment.reversed()` 재사용) — 거리는 대상 구간과 동일(1×), 코스 총 거리는 그 구간만큼 추가되어 결과적으로 2×가 된다. 좌표를 새로 만들거나 라우팅을 다시 호출하지 않는다.
- 뒤쪽 끝 구간이면 뒤에 append, 앞쪽 끝 구간이면 앞에 prepend. 구간이 하나뿐이면(양쪽 다 해당) append로 취급한다.
- "전체 왕복"은 현재 코스 전체 좌표(`PlannedCourse.coordinates`, 경계 중복 제거된 형태)를 뒤집어 맨 뒤에 단일 `.roundTrip` 엔트리로 append한다. anchor를 쓰지 않는다 — 일반 append와 동일하게 undo/redo가 동작한다.
- 좌표 상한(기존 `CourseEditSession.maxTotalCoordinates = 20_000`)은 두 연산 모두에서 삽입 전 가드로 유지한다.
- 초안 직렬화 포맷을 바꿀 때는 하위호환을 지킨다: 새 필드가 없는 옛 blob도 손상 취급하지 않고 정상 복원되어야 한다(기존 corrupt 판정 정책은 그대로 유지, 필드 누락은 corrupt가 아니다).
- 기존 코드 스타일을 따른다: 한국어 주석은 "왜"가 비직관적일 때만, docstring 없음, 명시적 필드 나열(구조체 생성 시 default 값에 의존하지 않고 모든 필드 명시).

---

## Task 1: `CourseEditSession` 왕복 로직 수정 + 전체 왕복 추가

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Entity/CourseDraft.swift`
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift`
- Test: `TraceTests/CourseRoundTripInsertTests.swift`

**Interfaces:**
- Consumes: `CourseSegment.reversed()`, `CourseSegment.roundTrip(coordinates:distanceMeters:)`, `CourseCoordinate`, `PlannedCourse.coordinates`/`distanceMeters` (기존, 변경 없음).
- Produces: `CourseDraft.Entry`에 새 필드 `anchorInsertsBefore: Bool` (Task 2가 이 필드를 그대로 DTO에 매핑). `CourseEditSession`의 공개 API 시그니처는 변경 없음: `canInsertRoundTrip(afterOrder: Int) -> Bool`, `insertRoundTrip(afterOrder: Int)`. 새 공개 API 추가: `canInsertWholeCourseRoundTrip() -> Bool`, `insertWholeCourseRoundTrip()`.

- [ ] **Step 1: `CourseDraft.Entry`에 `anchorInsertsBefore` 필드 추가**

`Trace/Domain/CoursePlanning/Entity/CourseDraft.swift` 전체를 아래로 교체:

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
        // anchorID가 있을 때만 의미 있음: true = anchor 바로 앞에 삽입(코스 앞쪽 끝 왕복),
        // false = anchor 바로 뒤(코스 뒤쪽 끝 왕복). anchorID가 nil이면 무시된다.
        let anchorInsertsBefore: Bool
        let segment: CourseSegment
    }

    var entries: [Entry]
    var nextOrder: Int

    var isEmpty: Bool { entries.isEmpty }

    static let empty = CourseDraft(entries: [], nextOrder: 0)
}
```

- [ ] **Step 2: 실패하는 테스트 작성 — 기존 왕복 테스트 재작성 + 신규 테스트 추가**

`TraceTests/CourseRoundTripInsertTests.swift` 전체를 아래로 교체 (기존 "중간 구간 병합" 테스트를 "중간 구간 불가"로, 나머지는 새 거리·좌표 규칙에 맞게 재작성하고 앞쪽 끝·전체 왕복 테스트를 추가):

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

    // MARK: - 자유 끝 제한 (2026-07-08 정정: 중간 구간은 불가)

    func testCanInsertRoundTrip_falseForMiddleSegment() async throws {
        let session = try await makeThreeSegmentSession()
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 1)) // B→C, 중간 구간
        session.insertRoundTrip(afterOrder: 1)
        XCTAssertEqual(session.segments.count, 3) // no-op
    }

    // MARK: - 뒤쪽 끝: append, 코스 끝이 대상 구간 시작점으로 이동

    func testInsertRoundTrip_lastSegment_appendsReversedWithSameDistance() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2) // C→D 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[3]
        XCTAssertTrue(inserted.isRoundTrip)
        // 왕복 좌표: D→C(대상 구간의 역방향뿐), 거리는 대상과 동일(1×)
        XCTAssertEqual(inserted.coordinates, [coord(37.53, 127.00), coord(37.52, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 1000)
        // 연결 유지: 왕복 시작(D) == 대상 구간 끝(D)
        XCTAssertEqual(inserted.coordinates.first, session.segments[2].coordinates.last)
        // 총 거리 = 3000 + 1000(대상 구간만큼 추가) = 4000
        XCTAssertEqual(session.course?.distanceMeters, 4000)
        // 코스 끝이 대상 구간 시작점(C)으로 이동
        XCTAssertEqual(session.course?.coordinates.last, coord(37.52, 127.00))
    }

    func testInsertRoundTrip_undoOnce_removesRoundTrip() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertRoundTrip(afterOrder: 2)
        session.undo()
        XCTAssertEqual(session.segments, before)
    }

    func testInsertRoundTrip_undoRedo_restoresAfterAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after)
    }

    func testInsertRoundTrip_clearsRedoStack() async throws {
        let session = try await makeThreeSegmentSession()
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.insertRoundTrip(afterOrder: 2)
        XCTAssertFalse(session.canRedo)
    }

    // MARK: - 앞쪽 끝: prepend, 코스 시작이 대상 구간 끝점으로 이동

    func testInsertRoundTrip_frontSegment_prependsReversedBeforeIt() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 0) // A→B 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[0] // 공간순 맨 앞에 삽입됨
        XCTAssertTrue(inserted.isRoundTrip)
        XCTAssertEqual(inserted.coordinates, [coord(37.51, 127.00), coord(37.50, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 1000)
        // 연결 유지: 왕복 끝(A) == 원래 대상 구간(A→B) 시작(A)
        XCTAssertEqual(inserted.coordinates.last, session.segments[1].coordinates.first)
        // 코스 시작이 대상 구간 끝점(B)으로 이동
        XCTAssertEqual(session.course?.coordinates.first, coord(37.51, 127.00))
        XCTAssertEqual(session.course?.distanceMeters, 4000)
    }

    func testInsertRoundTrip_frontSegment_undoRedo_restoresBeforeAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 0)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after) // 맨 뒤가 아니라 anchor 바로 앞으로 복원
    }

    // MARK: - 경계 케이스

    func testInsertRoundTrip_onRoundTripSegment_allowed() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2) // 뒤쪽 끝에 왕복(order 3) 삽입
        // 방금 삽입된 왕복도 새로운 뒤쪽 끝이므로 다시 왕복 가능 — 특수 케이스 없음
        XCTAssertTrue(session.canInsertRoundTrip(afterOrder: 3))
        session.insertRoundTrip(afterOrder: 3)
        XCTAssertEqual(session.segments.count, 5)
        XCTAssertEqual(session.segments[4].coordinates.first, session.segments[3].coordinates.last)
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
        // 좌표 15,000개짜리 단일 구간 — 왕복 시 +15,000으로 상한(20,000) 초과
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
        session.insertRoundTrip(afterOrder: 0) // 유일 구간 — 앞뒤 둘 다 해당, append로 처리
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.segments[1].coordinates, [b, a])
        XCTAssertEqual(session.course?.distanceMeters, 2000)
    }

    func testInsertRoundTrip_closedCourse_keepsClosure() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        // 닫힌 코스: A→B→A (첫·끝 좌표 동일 = 임계값 이내)
        try await session.attach(.drawn(coordinates: [a, b, a], distanceMeters: 2000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, a)
        XCTAssertEqual(session.course?.coordinates.last, a)
        XCTAssertEqual(session.course?.distanceMeters, 4000)
    }

    func testSnapshotRestore_preservesRoundTripRedoAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2)
        let restored = CourseEditSession()
        restored.restore(from: session.snapshot())
        let after = restored.segments
        restored.undo()
        restored.redo()
        XCTAssertEqual(restored.segments, after)
    }

    func testSnapshotRestore_preservesFrontAnchorPlacement() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 0) // 앞쪽 끝 — anchorInsertsBefore = true
        let restored = CourseEditSession()
        restored.restore(from: session.snapshot())
        let after = restored.segments
        restored.undo()
        restored.redo()
        XCTAssertEqual(restored.segments, after)
    }

    // MARK: - 전체 왕복 (2026-07-08 추가)

    func testCanInsertWholeCourseRoundTrip_falseForEmptyCourse() {
        let session = CourseEditSession()
        XCTAssertFalse(session.canInsertWholeCourseRoundTrip())
    }

    func testInsertWholeCourseRoundTrip_appendsFullReversedCourse() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertWholeCourseRoundTrip()

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[3]
        XCTAssertTrue(inserted.isRoundTrip)
        // 전체 코스(A,B,C,D — 경계 중복 제거)를 뒤집은 D,C,B,A
        XCTAssertEqual(
            inserted.coordinates,
            [coord(37.53, 127.00), coord(37.52, 127.00), coord(37.51, 127.00), coord(37.50, 127.00)]
        )
        XCTAssertEqual(inserted.distanceMeters, 3000) // 기존 코스 총 거리와 동일
        XCTAssertEqual(session.course?.coordinates.first, coord(37.50, 127.00))
        XCTAssertEqual(session.course?.coordinates.last, coord(37.50, 127.00))
        XCTAssertEqual(session.course?.distanceMeters, 6000)
    }

    func testInsertWholeCourseRoundTrip_undo_removesWholeSegment() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertWholeCourseRoundTrip()
        session.undo()
        XCTAssertEqual(session.segments, before)
    }

    func testCanInsertWholeCourseRoundTrip_falseWhenExceedingCoordinateCap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let bigCoords = (0..<15_000).map { coord(37.50 + Double($0) * 0.00001, 127.00) }
        try await session.attach(.drawn(coordinates: bigCoords, distanceMeters: 15_000), using: service)
        XCTAssertFalse(session.canInsertWholeCourseRoundTrip())
        session.insertWholeCourseRoundTrip()
        XCTAssertEqual(session.segments.count, 1) // no-op
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

- [ ] **Step 3: 테스트 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CourseRoundTripInsertTests 2>&1 | tail -60`

Expected: 컴파일 실패(`CourseDraft.Entry`에 `anchorInsertsBefore` 인자가 없다는 등) 또는 다수 테스트 FAIL — 아직 `CourseEditSession`을 고치지 않았으므로 정상.

- [ ] **Step 4: `CourseEditSession` 구현 — Entry 필드, 왕복 로직, redo, snapshot/restore/load, 전체 왕복**

`Trace/Application/CoursePlanning/CourseEditSession.swift`의 `private struct Entry` (기존 9-15행)를 아래로 교체:

```swift
    private struct Entry {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?   // 왕복 엔트리의 redo 재삽입 기준(대상 구간 id). 일반 엔트리는 nil.
        // anchorID가 있을 때만 의미 있음: true = anchor 바로 앞(코스 앞쪽 끝 왕복),
        // false = anchor 바로 뒤(코스 뒤쪽 끝 왕복).
        let anchorInsertsBefore: Bool
        let segment: CourseSegment
    }
```

`redo()` (기존 128-140행)를 아래로 교체:

```swift
    func redo() {
        guard let entry = redoStack.popLast() else { return }
        // 왕복 엔트리는 anchor 옆으로 복원 — anchor는 LIFO 순서상 항상 먼저 복원돼 있다 (스펙 §4).
        // anchorInsertsBefore로 anchor 앞/뒤 중 원래 삽입 위치를 재현한다.
        // anchor 미발견 시 placedAtFront/append 폴백 (스펙 증명상 도달 불가, 방어적).
        if let anchorID = entry.anchorID,
           let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }) {
            entries.insert(entry, at: entry.anchorInsertsBefore ? anchorIndex : anchorIndex + 1)
        } else if entry.placedAtFront {
            entries.insert(entry, at: 0)
        } else {
            entries.append(entry)
        }
    }
```

`// MARK: - Round Trip (MVP11 스펙 §4)` 섹션 전체(기존 148-174행, `canInsertRoundTrip`/`insertRoundTrip`)를 아래로 교체:

```swift
    // MARK: - Round Trip (MVP11 스펙 §4, 2026-07-08 정정)

    // 코스의 자유 끝(맨 앞 또는 맨 뒤) 구간에서만 왕복 가능하다. 중간 구간은 반대쪽이 다른
    // 구간과 이어져 있어, 그 구간만 되짚으면 연결이 끊긴다 — 안전하게 되짚을 수 있는 쪽은
    // 아무것도 이어지지 않은 자유 끝뿐이다 (실기기 QA 2026-07-08로 확정, 이전의 "역+정 병합"
    // 방식은 거리가 3×가 되고 코스가 끊기지 않는 대신 항상 원래 끝점에 머물러 사용자 의도와
    // 어긋났다 — 폐기).
    func canInsertRoundTrip(afterOrder order: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.order == order }),
              index == 0 || index == entries.count - 1 else { return false }
        let n = entries[index].segment.coordinates.count
        guard n >= 2 else { return false }
        return totalCoordinateCount + n <= Self.maxTotalCoordinates
    }

    // 대상 구간(A→B)의 역방향(B→A)만 만들어 자유 끝에 붙인다 — 거리는 대상 구간과 동일(1×),
    // 코스 총 거리는 그 구간만큼 늘어 결과적으로 2×가 된다. 뒤쪽 끝이면 뒤에 append, 앞쪽
    // 끝이면 앞에 prepend — 구간이 하나뿐이면(양쪽 다 해당) append로 취급한다.
    func insertRoundTrip(afterOrder order: Int) {
        guard canInsertRoundTrip(afterOrder: order),
              let index = entries.firstIndex(where: { $0.order == order }) else { return }
        let target = entries[index]
        let reversed = target.segment.reversed()
        let roundTrip = CourseSegment.roundTrip(
            coordinates: reversed.coordinates,
            distanceMeters: reversed.distanceMeters
        )
        let isBackMost = index == entries.count - 1
        let newEntry = Entry(
            id: UUID(), order: nextOrder, placedAtFront: false,
            anchorID: target.id, anchorInsertsBefore: !isBackMost,
            segment: roundTrip
        )
        entries.insert(newEntry, at: isBackMost ? index + 1 : index)
        nextOrder += 1
        redoStack = []
    }

    // MARK: - Whole Course Round Trip (2026-07-08 추가)

    // 지금까지 그린 코스 전체를 뒤집어 맨 뒤에 이어붙인다 — 언제나 코스의 열린 끝(마지막 좌표)
    // 에서 시작하는 연산이라 별도 anchor 추적 없이 항상 연결이 유지된다(일반 append와 동일하게
    // undo/redo). 라우팅 재호출 없음(§4와 동일 원칙).
    func canInsertWholeCourseRoundTrip() -> Bool {
        guard let course, course.coordinates.count >= 2 else { return false }
        return totalCoordinateCount + course.coordinates.count <= Self.maxTotalCoordinates
    }

    func insertWholeCourseRoundTrip() {
        guard canInsertWholeCourseRoundTrip(), let course else { return }
        append(.roundTrip(coordinates: course.coordinates.reversed(), distanceMeters: course.distanceMeters))
    }
```

`snapshot()`/`restore(from:)` (기존 176-201행의 `// MARK: - Snapshot` 섹션)를 아래로 교체:

```swift
    // MARK: - Snapshot (초안 저장·복원, MVP11 스펙 §3)

    // 복원은 엔트리 id를 보존해야 한다 — append/prepend 재사용 시 id가 재발급되어
    // 왕복 anchor 참조가 끊긴다 (스펙 §3·§4).
    func snapshot() -> CourseDraft {
        CourseDraft(
            entries: entries.map {
                CourseDraft.Entry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore, segment: $0.segment
                )
            },
            nextOrder: nextOrder
        )
    }

    func restore(from draft: CourseDraft) {
        entries = draft.entries.map {
            Entry(
                id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore, segment: $0.segment
            )
        }
        nextOrder = draft.nextOrder
        redoStack = []
    }

    // 저장 코스 불러오기: 공간순 세그먼트에 시간순을 0부터 재부여 (undo = 공간순 마지막부터 제거)
    func load(segments: [CourseSegment]) {
        entries = segments.enumerated().map { index, segment in
            Entry(id: UUID(), order: index, placedAtFront: false, anchorID: nil, anchorInsertsBefore: false, segment: segment)
        }
        nextOrder = segments.count
        redoStack = []
    }
```

`private func append`/`private func prepend` (기존 214-224행)를 아래로 교체:

```swift
    private func append(_ segment: CourseSegment) {
        entries.append(Entry(
            id: UUID(), order: nextOrder, placedAtFront: false,
            anchorID: nil, anchorInsertsBefore: false, segment: segment
        ))
        nextOrder += 1
        redoStack = []
    }

    private func prepend(_ segment: CourseSegment) {
        entries.insert(Entry(
            id: UUID(), order: nextOrder, placedAtFront: true,
            anchorID: nil, anchorInsertsBefore: false, segment: segment
        ), at: 0)
        nextOrder += 1
        redoStack = []
    }
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CourseRoundTripInsertTests 2>&1 | tail -60`

Expected: 모든 테스트 PASS.

- [ ] **Step 6: Commit**

```bash
git add Trace/Domain/CoursePlanning/Entity/CourseDraft.swift Trace/Application/CoursePlanning/CourseEditSession.swift TraceTests/CourseRoundTripInsertTests.swift
git commit -m "fix: 왕복 추가를 자유 끝 구간 전용 역방향(2배 거리)으로 수정, 전체 왕복 추가"
```

---

## Task 2: 초안 직렬화(`CoursePersistenceDTO`) 하위호환 필드 추가

**Files:**
- Modify: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift`
- Test: `TraceTests/SwiftDataCourseRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1의 `CourseDraft.Entry.anchorInsertsBefore: Bool`.
- Produces: `CoursePersistenceDTO.DraftEntry.anchorInsertsBefore: Bool` — 필드가 없는 구버전 JSON도 `false`로 기본 복원(손상 취급 아님).

- [ ] **Step 1: 실패하는 테스트 작성 — 기존 draft round-trip 테스트 갱신 + 하위호환 테스트 추가**

`TraceTests/SwiftDataCourseRepositoryTests.swift`의 `sampleDraft()` (기존 9-29행)를 아래로 교체:

```swift
    private func sampleDraft() -> CourseDraft {
        let segID = UUID()
        return CourseDraft(
            entries: [
                CourseDraft.Entry(
                    id: segID, order: 0, placedAtFront: false, anchorID: nil, anchorInsertsBefore: false,
                    segment: .tapped(
                        coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                    )
                ),
                CourseDraft.Entry(
                    id: UUID(), order: 1, placedAtFront: false, anchorID: segID, anchorInsertsBefore: false,
                    segment: .roundTrip(
                        coordinates: [coord(37.51, 127.00), coord(37.50, 127.00)],
                        distanceMeters: 1000
                    )
                )
            ],
            nextOrder: 2
        )
    }
```

같은 파일 끝(현재 마지막 `}` 앞, 102행 이후)에 아래 테스트를 추가:

```swift

    func testDecodeDraft_missingAnchorInsertsBeforeField_defaultsToFalse() {
        // 구버전(2026-07-07 이전) blob 형태 — anchorInsertsBefore 키 자체가 없음.
        // 손상으로 취급하지 않고 false(= anchor 뒤, 옛 동작과 동일)로 복원돼야 한다.
        let segID = UUID().uuidString
        let entryID = UUID().uuidString
        let json = """
        {
            "version": 1,
            "entries": [
                {
                    "id": "\(segID)",
                    "order": 0,
                    "placedAtFront": false,
                    "anchorID": null,
                    "segment": {
                        "kind": "tapped",
                        "coordinates": [{"lat": 37.50, "lon": 127.00}, {"lat": 37.51, "lon": 127.00}],
                        "distanceMeters": 1000
                    }
                },
                {
                    "id": "\(entryID)",
                    "order": 1,
                    "placedAtFront": false,
                    "anchorID": "\(segID)",
                    "segment": {
                        "kind": "roundTrip",
                        "coordinates": [{"lat": 37.51, "lon": 127.00}, {"lat": 37.50, "lon": 127.00}],
                        "distanceMeters": 1000
                    }
                }
            ],
            "nextOrder": 2
        }
        """
        let draft = SwiftDataCourseRepository.decodeDraft(Data(json.utf8))
        XCTAssertNotNil(draft) // 필드 누락은 손상이 아니다
        XCTAssertEqual(draft?.entries.map(\.anchorInsertsBefore), [false, false])
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SwiftDataCourseRepositoryTests 2>&1 | tail -60`

Expected: 컴파일 실패(`CourseDraft.Entry`/`DraftEntry` 인자 불일치) 또는 FAIL.

- [ ] **Step 3: `CoursePersistenceDTO` 구현**

`Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift`의 `struct DraftEntry: Codable { ... }` (기존 22-28행)를 아래로 교체:

```swift
    struct DraftEntry: Codable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        let anchorInsertsBefore: Bool
        let segment: Segment

        init(
            id: UUID, order: Int, placedAtFront: Bool,
            anchorID: UUID?, anchorInsertsBefore: Bool, segment: Segment
        ) {
            self.id = id
            self.order = order
            self.placedAtFront = placedAtFront
            self.anchorID = anchorID
            self.anchorInsertsBefore = anchorInsertsBefore
            self.segment = segment
        }

        // 구버전 blob(anchorInsertsBefore 필드 없음) 하위호환: 옛 왕복 엔트리는 항상 anchor
        // 뒤에 삽입됐으므로 false가 정확한 기본값이다 — 필드 누락을 손상으로 취급하지 않는다.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            order = try container.decode(Int.self, forKey: .order)
            placedAtFront = try container.decode(Bool.self, forKey: .placedAtFront)
            anchorID = try container.decodeIfPresent(UUID.self, forKey: .anchorID)
            anchorInsertsBefore = try container.decodeIfPresent(Bool.self, forKey: .anchorInsertsBefore) ?? false
            segment = try container.decode(Segment.self, forKey: .segment)
        }
    }
```

`extension CoursePersistenceDTO.Draft { ... }` (기존 73-98행)를 아래로 교체:

```swift
extension CoursePersistenceDTO.Draft {
    init(_ draft: CourseDraft) {
        self.init(
            version: CoursePersistenceDTO.currentVersion,
            entries: draft.entries.map {
                CoursePersistenceDTO.DraftEntry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore,
                    segment: CoursePersistenceDTO.Segment($0.segment)
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
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore,
                    segment: $0.segment.domain
                )
            },
            nextOrder: nextOrder
        )
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SwiftDataCourseRepositoryTests 2>&1 | tail -60`

Expected: 모든 테스트 PASS.

- [ ] **Step 5: Commit**

```bash
git add Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift TraceTests/SwiftDataCourseRepositoryTests.swift
git commit -m "fix: 초안 직렬화에 anchorInsertsBefore 하위호환 필드 추가"
```

---

## Task 3: ViewModel — 전체 왕복 노출 + 기존 왕복 거리 어서션 갱신

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Test: `TraceTests/CoursePlannerViewModelPersistenceTests.swift`

**Interfaces:**
- Consumes: Task 1의 `session.canInsertWholeCourseRoundTrip() -> Bool`, `session.insertWholeCourseRoundTrip()`.
- Produces: `viewModel.canInsertWholeCourseRoundTrip: Bool` (계산 프로퍼티), `viewModel.insertWholeCourseRoundTrip()`. Task 4의 UI가 이 둘을 소비한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/CoursePlannerViewModelPersistenceTests.swift`의 `draftWithOneSegment()` (기존 44-54행)를 아래로 교체:

```swift
    private func draftWithOneSegment() -> CourseDraft {
        CourseDraft(
            entries: [CourseDraft.Entry(
                id: UUID(), order: 0, placedAtFront: false, anchorID: nil, anchorInsertsBefore: false,
                segment: .tapped(
                    coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                )
            )],
            nextOrder: 1
        )
    }
```

`testInsertRoundTrip_viaViewModel_updatesCourseAndPersists` (기존 234-251행)의 거리 어서션을 새 규칙(2×가 아니라 대상 구간만큼 추가)에 맞게 교체 — 함수 전체를 아래로 교체:

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
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(대상 구간만큼 추가)
        XCTAssertNil(vm.selectedSegmentIndex)

        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 2) // 왕복 삽입도 초안 저장 트리거 (스펙 §3)
    }
```

파일 끝(현재 마지막 `}` 앞, `testCanInsertRoundTrip_unknownKey_false` 뒤)에 아래 테스트를 추가:

```swift

    func testInsertWholeCourseRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        XCTAssertTrue(vm.canInsertWholeCourseRoundTrip)
        vm.insertWholeCourseRoundTrip()

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(전체 코스 왕복)
        XCTAssertNil(vm.selectedSegmentIndex)

        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 2)
    }

    func testCanInsertWholeCourseRoundTrip_emptyCourse_false() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        XCTAssertFalse(vm.canInsertWholeCourseRoundTrip)
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelPersistenceTests 2>&1 | tail -60`

Expected: 컴파일 실패(`canInsertWholeCourseRoundTrip` 없음) 또는 거리 어서션 FAIL.

- [ ] **Step 3: ViewModel 구현**

`Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`의 `// MARK: - Round Trip (MVP11 스펙 §4) — colorKey = 세션 order` 섹션(기존 339-350행) 바로 뒤에 아래를 추가:

```swift

    // MARK: - Whole Course Round Trip (2026-07-08 추가)

    var canInsertWholeCourseRoundTrip: Bool {
        session.canInsertWholeCourseRoundTrip()
    }

    func insertWholeCourseRoundTrip() {
        infoMessage = nil
        session.insertWholeCourseRoundTrip()
        selectedSegmentIndex = nil
        persistDraft()
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelPersistenceTests 2>&1 | tail -60`

Expected: 모든 테스트 PASS.

- [ ] **Step 5: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift TraceTests/CoursePlannerViewModelPersistenceTests.swift
git commit -m "feat: ViewModel에 전체 왕복 노출, 왕복 거리 어서션을 새 규칙에 맞게 갱신"
```

---

## Task 4: UI — "전체 왕복" 버튼 추가

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`

**Interfaces:**
- Consumes: Task 3의 `viewModel.canInsertWholeCourseRoundTrip: Bool`, `viewModel.insertWholeCourseRoundTrip()`.

배치·아이콘 등 세부 UI 결정은 기존 컨트롤 바 스타일(아이콘 버튼, `.borderedProminent`, `accessibilityIdentifier` 네이밍 규칙)을 그대로 따른다.

- [ ] **Step 1: 버튼 추가**

`Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`의 목록 버튼(기존 36-41행, `coursePlanner.courseList`) 바로 뒤, `HStack` 닫히기 전에 아래를 추가:

```swift

            Button {
                viewModel.insertWholeCourseRoundTrip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .disabled(!viewModel.canInsertWholeCourseRoundTrip)
            .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: 시뮬레이터에서 육안 확인**

시뮬레이터를 실행해 코스를 하나 그린 뒤(예: 경로 찍기 모드로 2탭), 컨트롤 바에 새 버튼이 보이고 탭하면 코스가 왕복으로 늘어나는지, 코스가 비었을 때는 버튼이 비활성인지 확인한다.

- [ ] **Step 4: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
git commit -m "feat: 컨트롤 바에 전체 왕복 버튼 추가"
```

---

## Task 5: 문서 갱신 — 스펙 정정 + 백로그 정리

**Files:**
- Modify: `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md`
- Modify: `docs/backlog.md`

**Interfaces:** 없음 (문서 전용, 코드 변경 없음).

- [ ] **Step 1: 스펙 §4 정정 + 전체 왕복 절 추가**

`docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md`의 `## 4. roundtrip-insert — 동작 설계` 절(126-179행)을 아래로 교체:

```markdown
## 4. roundtrip-insert — 동작 설계 (2026-07-08 정정)

### 연산 정의: "왕복 추가"

> 최초 설계(역+정 병합, 3× 거리, 모든 위치 허용)는 2026-07-08 실기기 QA에서 거리·연결
> 문제가 발견돼 아래 내용으로 교체됐다. 교체 배경은 어드바이저 검토로 확정: 코스 중간
> 구간은 반대쪽이 다른 구간과 이어져 있어 그 구간만 되짚으면 코스가 끊긴다 — 안전하게
> 되짚을 수 있는 쪽은 아무것도 이어지지 않은 코스의 자유 끝(맨 앞/맨 뒤)뿐이다.

구간 패널의 각 구간 줄에 왕복 버튼을 둔다. **코스의 자유 끝 구간(맨 앞 또는 맨 뒤)에서만**
활성화되며, 대상 구간(A→B)의 **역방향(B→A)만** 만들어 그 자유 끝에 붙인다(거리는 대상과
동일한 1×):

```
뒤쪽 끝 (append):   … → 이전구간(…→A) → s(A→B) → 왕복(B→A)          [코스가 A에서 끝남]
앞쪽 끝 (prepend):   왕복(B→A) → s(A→B) → 다음구간(B→…) → …          [코스가 B에서 시작]
```

- 중간 구간(양옆 모두 다른 구간과 연결된 구간)은 왕복 버튼이 비활성이다 — 반대쪽 연결이
  끊기기 때문에 구조적으로 불가능하다.
- 구간이 하나뿐인 코스(양쪽 끝이 같은 구간)는 뒤쪽 끝으로 취급해 append한다.
- 삽입 결과 코스의 시작 또는 끝 지점이 대상 구간의 반대쪽 점으로 이동한다(뒤쪽 끝이면 코스
  끝이 대상 구간 시작점으로, 앞쪽 끝이면 코스 시작이 대상 구간 끝점으로). 총 거리는 대상
  구간의 거리만큼 늘어 결과적으로 그 구간이 2×가 된다.
- 라우팅 호출 없음: `CourseSegment.reversed()`로 대상 구간의 확정 좌표를 뒤집은 순수 데이터
  연산.
- **"왕복임"의 표현**: `CourseSegment.roundTrip` 케이스(변경 없음, MVP11 최초 설계 유지).
- 버튼 비활성 가드: 중간 구간, 좌표가 2개 미만인 구간(방어적 경계), 삽입 후 코스 총 좌표
  수가 상한(20,000)을 넘는 경우.

### undo/redo와의 상호작용

- 삽입은 기존 편집 연산과 동일하게 redo 스택을 비운다.
- undo로 왕복을 제거하면 redo 스택에 들어간다. redo 시 재삽입 위치는 anchor(대상 구간
  엔트리 id) 기준이되, **anchor 앞/뒤 중 어느 쪽이었는지**(`anchorInsertsBefore`)도 함께
  저장해 뒤쪽 끝(anchor 뒤)·앞쪽 끝(anchor 앞) 모두 정확히 복원한다.
- 초안 직렬화(`CourseDraft`)에 `anchorInsertsBefore`를 포함해 재시작 후에도 일관되게
  동작한다. 이 필드가 없는 구버전 blob(2026-07-07 최초 설계 시점)은 손상이 아니라 `false`
  (= anchor 뒤, 옛 동작과 동일)로 기본 복원된다 — 옛 왕복 엔트리는 항상 append였으므로
  정확한 값이다.

### 패널 표시

- 왕복 세그먼트는 일반 구간과 같은 줄 형식에 왕복 표식(아이콘)과 거리를 표시. 색상은 기존
  색상 키 규칙(attach 생성 순서)을 그대로 따른다.
- 지도 렌더링은 기존 겹침 오프셋(MVP8)이 왕복 구간의 겹침을 그대로 처리 — 신규 렌더링
  코드 없음.

## 4.5. 전체 왕복 (2026-07-08 추가)

지금까지 그린 코스 **전체**를 뒤집어 맨 뒤에 단일 왕복 세그먼트로 붙이는 별개의 액션.
구간 단위 왕복(위 §4)과 달리 특정 구간을 고르지 않고, 컨트롤 바의 별도 버튼으로 코스
전체에 적용한다.

- 항상 코스의 열린 끝(현재 마지막 좌표)에서 시작하는 연산이라 anchor 추적 없이 구조적으로
  항상 연결이 유지된다 — 중간 구간 제약이 없다(적용 대상이 애초에 "코스 전체"이므로).
- 좌표: `PlannedCourse.coordinates`(세그먼트 경계 중복 제거된 전체 좌표)를 뒤집은 것.
  거리: 뒤집기 전 코스 총 거리와 동일(결과적으로 코스 총 거리 2×).
- undo/redo는 일반 append와 동일하게 동작한다(anchor 없음).
- 용도: 막다른 길·산책로처럼 왔던 길 그대로 돌아 나오는 코스를 손으로 다시 그릴 필요 없이
  버튼 한 번으로 완성. 구간 단위 왕복(특정 골목만 왕복)과는 별개 용도로 공존한다.
```

- [ ] **Step 2: 백로그 "되짚어 오기" 항목을 완료로 정리**

`docs/backlog.md`의 77행("되짚어 오기 (마지막 구간 역방향 붙이기)" 항목)을 아래로 교체:

```markdown
- [x] **되짚어 오기 (마지막 구간 역방향 붙이기)** — *what:* 구간 패널 마지막 구간에 "되짚어 오기" 액션 추가 — 역방향 하나만 붙여 코스 끝을 그 구간 시작점으로 되돌림(그리던 중 막다른 골목·방파제에서 돌아 나와 이어 그리기 용도). *resolved:* 2026-07-08 실기기 QA에서 기존 "왕복 추가"(역+정 병합, 3× 거리) 자체가 버그로 확인되어, 정확히 이 항목이 원하던 동작(역방향만, 자유 끝 전용, 2× 거리)으로 교체됨 — 별도 액션을 새로 만들 필요 없이 "왕복 추가"가 곧 "되짚어 오기"가 됨. 설계: `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md` §4. `done`
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md docs/backlog.md
git commit -m "docs: 왕복 추가 스펙 정정, 전체 왕복 설계 추가, 되짚어 오기 백로그 완료 처리"
```

---

## Self-Review 메모 (계획 작성자용, 실행 시 참고)

- **스펙 커버리지**: §4 정정(중간 구간 금지, 2× 규칙, anchor 방향) — Task 1·5. §4.5 전체 왕복 — Task 1·3·4·5. 하위호환 — Task 2. 전부 태스크로 커버됨.
- **타입 일관성**: `anchorInsertsBefore: Bool`이 `CourseEditSession.Entry` → `CourseDraft.Entry` → `CoursePersistenceDTO.DraftEntry` 세 곳에서 이름·타입 동일하게 유지됨(Task 1→2 의존 순서 그대로).
- **의존 순서**: Task 1(Domain) → Task 2(Persistence, Task 1의 `CourseDraft.Entry` 필드에 의존) → Task 3(ViewModel, Task 1의 `CourseEditSession` API에 의존) → Task 4(UI, Task 3에 의존) → Task 5(문서, 코드 의존 없음— 아무 때나 가능하지만 마지막에 실제 동작과 맞춰 쓰는 것이 안전).
