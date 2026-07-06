# attach-nearest-fallback 구현 플랜 (MVP10 마일스톤 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `CourseEditSession.attach` 규칙 4를 "무조건 도착점 append"에서 "시작점 최근접 끝점 비교(출발점 쪽이면 반전 prepend + gap 라우팅)"로 교체해 탭↔그리기 판정 원리를 통일한다.

**Architecture:** Application 레이어 `CourseEditSession.attach` 한 메서드의 분기 하나만 교체. 규칙 1~3과 ViewModel/View는 불변. 스펙: `docs/superpowers/specs/2026-07-05-attach-nearest-fallback-design.md` (리뷰 완료 버전 — 진입 조건 게이트·near-tie 테스트·QA 실패 기준 포함).

**Tech Stack:** Swift 6 async/await, `@MainActor @Observable`, XCTest.

## Global Constraints

- 강제 언랩/강제 캐스트/강제 try 금지 — swiftlint 에러 + pre-commit 훅이 차단.
- ViewModel은 MapKit/UIKit을 import하지 않는다 (이번 작업은 ViewModel조차 안 건드림 — 변경 파일은 Application 레이어 1개 + 테스트 1개 + 문서 4개).
- 새 `.swift` 파일 없음 — 기존 파일 수정만.
- 시뮬레이터: 세션 시작 시 iOS 26.5 iPhone UDID 하나를 고정(`xcrun simctl list devices available | grep iPhone`), 이후 절대 변경 금지. 테스트는 raw `xcodebuild ... -parallel-testing-enabled NO test`로만 실행 (XcodeBuildMCP 테스트 툴 금지). `docs/agent-rules/testing.md`.
- 각 태스크의 커밋 전: 빌드/테스트/린트 3종 통과 후 `.git/trace-verify-{build,test,lint}.ok` 스탬프 생성 (pre-commit 훅 요건).
- 커밋은 `scripts/trace-commit.sh -m "tag: 한국어 제목\n\n- 본문 3~4줄" -- <경로들>`로 경로 명시 스테이징. `git push` 금지.
- 검증 명령 (UDID는 고정값 사용):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
  - 테스트: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test`
  - 린트: `swiftlint`
- ⚠️ 워킹 트리에 이 마일스톤과 무관한 미커밋 문서 3건(backlog/roadmap/QA 체크리스트 — 1차 QA 결과 반영분)이 있을 수 있다. 각 커밋은 반드시 태스크가 명시한 경로만 스테이징한다.

---

### Task 1: CourseEditSession 규칙 4 교체 (TDD)

**Files:**
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift:33-69` (attach 메서드 + 규칙 주석)
- Test: `TraceTests/CourseEditSessionTests.swift`

**Interfaces:**
- Consumes: 기존 `CourseEditSession.attach(_:using:)`, `CourseSegment.reversed()`, `CourseCoordinate.distanceMeters(to:)`, 테스트 파일 하단의 `StubCourseService`/`FailingCourseService` (기존 정의 그대로 사용, 새로 만들지 말 것).
- Produces: 공개 API 변경 없음 — `attach` 시그니처 동일, 내부 분기만 교체. 이후 태스크는 코드에 의존하지 않는다(문서만).

**배경 지식 (테스트 좌표 기하):** 이 테스트 파일의 고정 좌표 A(37.50)·B(37.51)·C(37.52)·D(37.53)는 같은 경도(127.00) 위에 남→북으로 나열되며, 위도 0.01° ≈ 1,110m, 0.0001° ≈ 11m(임계값 20m 이내)다. `StubCourseService.route`는 항상 `[start, destination]` 좌표에 거리 100을 반환한다.

- [ ] **Step 1: 신규 테스트 5개 작성** — `TraceTests/CourseEditSessionTests.swift`의 `// MARK: - attach: 규칙 4 — ...` 섹션(기존 `testAttach_farStroke_appendsAsDrawnWithGap`) 아래에 추가:

```swift
    // MARK: - attach: 새 규칙 4 — 원거리 스트로크 최근접 끝점 비교 (MVP10 마일스톤 4)

    /// 원거리 시작점이 출발점에 명백히 더 가까움 → 반전 prepend + gap 병합 (스펙 QA 케이스 324m vs 1241m 축소판)
    func testAttach_farStroke_nearerToStart_reversePrependsWithGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C (출발 B, 도착 C)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: P→A, P는 B에서 ~555m·C에서 ~1,665m (양쪽 임계값 밖, 출발점 쪽)
        let P = CourseCoordinate(latitude: 37.505, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P, A], distanceMeters: 500), using: service)

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "반전 prepend로 코스 시작이 A여야 함")
        XCTAssertEqual(session.course?.coordinates.last, C, "도착점은 그대로 C")
        XCTAssertEqual(service.routeCallCount, 1, "출발점 쪽 gap 라우팅 1회")
        // 병합 세그먼트: reversed(stroke) + gap(P→B).dropFirst() = [A, P] + [B]
        XCTAssertEqual(session.segments.first?.coordinates, [A, P, B])
        XCTAssertEqual(session.segments.first?.distanceMeters, 600, "스트로크 500 + gap 100")
    }

    /// near-tie 경계 (출발점 쪽): 이등분선보다 ~11m 출발점 쪽 → 결정론적으로 prepend
    func testAttach_nearTieBoundary_startSide_prepends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→C (이등분선 = 37.51)
        try await session.attach(.tapped(coordinates: [A, C], distanceMeters: 100), using: service)
        // New: P1→D, P1은 A에서 ~1,099m·C에서 ~1,121m (근소하게 출발점 쪽)
        let P1 = CourseCoordinate(latitude: 37.5099, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P1, D], distanceMeters: 300), using: service)

        XCTAssertEqual(session.course?.coordinates.first, D, "출발점 쪽 판정 → 반전 prepend → 시작이 D")
        XCTAssertEqual(session.course?.coordinates.last, C)
    }

    /// near-tie 경계 (도착점 쪽): 이등분선보다 ~11m 도착점 쪽 → 결정론적으로 append
    func testAttach_nearTieBoundary_endSide_appends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→C
        try await session.attach(.tapped(coordinates: [A, C], distanceMeters: 100), using: service)
        // New: P2→D, P2는 A에서 ~1,121m·C에서 ~1,099m (근소하게 도착점 쪽)
        let P2 = CourseCoordinate(latitude: 37.5101, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P2, D], distanceMeters: 300), using: service)

        XCTAssertEqual(session.course?.coordinates.first, A, "도착점 쪽 판정 → 출발점 불변")
        XCTAssertEqual(session.course?.coordinates.last, D, "그린 그대로 도착점 뒤 append")
    }

    /// 닫힌 코스 + 원거리 스트로크 → 여전히 append (규칙 1 선점 = 진입 조건 게이트 검증)
    func testAttach_closedCourse_farStroke_stillAppends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 닫힌 코스 구성: A→B, B근처→A근처 (첫·끝 좌표 ≤20m)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
        // New: E→C, E는 A 남쪽 ~1,110m — 닫힌 코스 양끝 어디서도 멀지만 출발점 A에 근소하게 더 가까움.
        // 비교가 게이트 없이 실행되면 prepend로 새어 규칙 1이 깨진다.
        let E = CourseCoordinate(latitude: 37.49, longitude: 127.00)
        try await session.attach(.tapped(coordinates: [E, C], distanceMeters: 100), using: service)

        XCTAssertEqual(session.course?.coordinates.first, A, "닫힌 코스는 무조건 append — 출발점 불변")
        XCTAssertEqual(session.course?.coordinates.last, C)
    }

    /// 출발점 쪽 gap 라우팅 실패 → 세션 상태 불변 + redo 스택 보존 (MVP9 에러 규칙의 새 분기 적용)
    func testAttach_farStrokeNearerToStart_gapFailure_preservesState() async throws {
        let session = CourseEditSession()
        let okService = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: okService)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: okService)
        session.undo()
        XCTAssertTrue(session.canRedo)

        // P는 A에서 ~333m·B에서 ~777m (출발점 쪽, 임계값 밖) → 새 분기의 gap 라우팅이 실패
        let P = CourseCoordinate(latitude: 37.503, longitude: 127.00)
        let failingService = FailingCourseService()
        do {
            try await session.attach(.drawn(coordinates: [P, D], distanceMeters: 300), using: failingService)
            XCTFail("gap 라우팅 실패로 throw되어야 함")
        } catch {}

        XCTAssertTrue(session.canRedo, "실패한 attach는 redo 스택을 보존해야 함")
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.course?.coordinates.first, A)
        XCTAssertEqual(session.course?.coordinates.last, B)
    }
```

- [ ] **Step 2: 테스트 실행해 red/green 분포 확인**

Run: 테스트 명령 (Global Constraints), 또는 빠르게 `-only-testing:TraceTests/CourseEditSessionTests` 추가.
Expected: **신규 5개 중 2개 FAIL** — `testAttach_farStroke_nearerToStart_reversePrependsWithGap`(코스 시작이 A가 아니라 B), `testAttach_nearTieBoundary_startSide_prepends`(시작이 D가 아니라 A). **나머지 3개는 현행 동작에서도 PASS**여야 한다(회귀 가드 — 구현 전후 모두 green 유지가 요구사항). 기존 테스트 전부 PASS.

- [ ] **Step 3: attach 구현 교체** — `Trace/Application/CoursePlanning/CourseEditSession.swift`. 먼저 메서드 위 규칙 주석(33~35행)을 교체:

```swift
    // 이어붙이기 순서 규칙 (spec 규칙 1~4): 반전은 "출발점 쪽 시작 = 출발 방향 연장" 하나뿐.
    // 규칙 4는 시작점 "단일 점"만 두 끝점과 최근접 비교한다(탭 nearestEndpoint와 동일한 <=) —
    // 스트로크 양끝 4쌍 비교·끝점 비교는 왕복 모호성을 재발시키므로 금지 (MVP9 → MVP10 스펙).
    // 1 attach = 1 segment 추가 = undo 1번에 완전 제거
```

그다음 규칙 3 분기와 append 블록 사이에 새 규칙 4(출발점 쪽) 분기를 삽입하고, append 블록 주석을 갱신:

```swift
        // 규칙 3: 열린 코스의 출발점에서 시작한 구간만 "출발 방향 연장" — 반전 prepend.
        // 반전 후 끝 좌표 = 원래 시작점 ≈ 기존 출발점이므로 gap 라우팅이 필요 없다.
        if !isClosedCourse, !startsNearEnd, startsNearStart {
            prepend(newSegment.reversed())
            return
        }

        // 규칙 4(출발점 쪽): 규칙 1~3이 모두 안 걸린 원거리 스트로크는 시작점을 두 끝점과
        // 최근접 비교해, 출발점 쪽(등거리 포함)이면 규칙 3의 원거리 확장 — 반전 prepend + gap.
        // 진입 조건상 시작점-출발점 거리 > threshold이므로 gap 라우팅이 항상 필요하다.
        if !isClosedCourse, !startsNearEnd, !startsNearStart,
           newStart.distanceMeters(to: existingStart) <= newStart.distanceMeters(to: existingEnd) {
            let gap = try await service.route(from: newStart, to: existingStart)
            let reversed = newSegment.reversed()
            prepend(makeMerged(
                like: newSegment,
                coordinates: reversed.coordinates + Array(gap.coordinates.dropFirst()),
                distance: reversed.distanceMeters + gap.distanceMeters
            ))
            return
        }

        // 규칙 1·2·4(도착점 쪽): 그린 그대로 도착점 뒤에 append (필요 시 gap 라우팅)
        var combinedCoords = newSegment.coordinates
        var combinedDistance = newSegment.distanceMeters
        if needsGap(from: existingEnd, to: newStart) {
            let gap = try await service.route(from: existingEnd, to: newStart)
            combinedCoords = gap.coordinates + Array(newSegment.coordinates.dropFirst())
            combinedDistance += gap.distanceMeters
        }
        append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
```

(append 블록 자체는 기존 코드 그대로 — 첫 줄 주석만 "규칙 1·2·4:" → "규칙 1·2·4(도착점 쪽):"으로 바뀐다.)

- [ ] **Step 4: 테스트 통과 확인**

Run: 테스트 명령 (Global Constraints).
Expected: 신규 5개 전부 PASS + **기존 테스트 전체 PASS** (특히 `testAttach_farStroke_appendsAsDrawnWithGap` — 시드 A→B에 스트로크 C→D는 C가 도착점 B에 더 가까워(1,110m vs 2,220m) 여전히 append; `testAttach_failure_preservesRedoStack` — D는 B 쪽이라 기존 append 실패 경로 유지).

- [ ] **Step 5: 린트 + 빌드**

Run: `swiftlint` 그리고 빌드 명령 (Global Constraints). Expected: 둘 다 PASS (경고 0 신규).

- [ ] **Step 6: 커밋**

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: attach 규칙 4를 시작점 최근접 끝점 비교로 교체

- 원거리 스트로크: 출발점 쪽(<=, 탭 nearestEndpoint와 동일)이면 반전 prepend + gap 라우팅
- 진입 조건(!closed && !nearEnd && !nearStart) 게이트로 규칙 1·2 선점 보존
- 신규 테스트 5개: prepend 병합, near-tie 경계 양쪽, 닫힌 코스 게이트, gap 실패 상태 보존" -- Trace/Application/CoursePlanning/CourseEditSession.swift TraceTests/CourseEditSessionTests.swift
```

---

### Task 2: 문서 반영 (project-decisions · QA 체크리스트)

**Files:**
- Modify: `docs/agent-rules/project-decisions.md` (Course attach rule 항목)
- Modify: `docs/qa/2026-07-04-gesture-consistency-device-checklist.md` (시나리오 추가)

**Interfaces:**
- Consumes: Task 1이 커밋된 상태.
- Produces: 코드 산출물 없음. 문서 2건의 정확한 문안.

참고: `docs/backlog.md`(항목 `planned` 전환)와 `docs/roadmap.md`(마일스톤 4 `[~]` 추가)는 핸드오프 시점(2026-07-05)에 이미 갱신·커밋됨 — 이 태스크에서 건드리지 않는다. 단, Task 3 완료 시 roadmap의 마일스톤 상태를 `[~]` → `[x]`로 바꾸는 것은 Task 3 Step 3에 포함.

- [ ] **Step 1: `docs/agent-rules/project-decisions.md`** — "Course attach rule" 항목의 규칙 4 문장을 교체. 기존:

```
④ 그 외 원거리 스트로크는 항상 도착점에서 gap 라우팅 append. 거리 비교로 앞/뒤를 추측하지 않는다. 상세: `history/mvp9/2026-07-03-edit-consistency-design.md`.
```

교체 후:

```
④ 그 외 원거리 스트로크는 시작점(단일 점)을 두 끝점과 최근접 비교(탭 nearestEndpoint와 동일, 마진 없는 `<=`)해 출발점 쪽이면 반전 prepend + gap 라우팅, 도착점 쪽이면 gap append (MVP10 재설계, 2026-07-05). 스트로크 양끝 4쌍 비교와 끝점 비교는 금지 유지 — 판정 입력은 시작점 하나뿐이다. 상세: `history/mvp9/2026-07-03-edit-consistency-design.md`(구 규칙 이력) + `docs/superpowers/specs/2026-07-05-attach-nearest-fallback-design.md`.
```

- [ ] **Step 2: `docs/qa/2026-07-04-gesture-consistency-device-checklist.md`** — 파일 끝의 `---\n체크리스트 경로:` 푸터 **앞**, "## 6. 알려진 한계" 섹션 뒤에 새 섹션 추가:

```markdown
## 7. 그리기 방향 판정 — attach-nearest-fallback (2026-07-05 추가, 마일스톤 4)

> 시나리오 8에서 발견된 중간지대 방향 판정 갭의 재설계 검증. 스펙:
> `docs/superpowers/specs/2026-07-05-attach-nearest-fallback-design.md`
> **실패 기준(사전 결정):** 시나리오 17에서 반전된 달리는 순서가 의도와 다르게 느껴지는 사례가
> 재현되면, 절충(부분 마진 등)을 새로 설계하지 않고 규칙 4를 무조건 append로 되돌린 뒤
> backlog 항목을 reopen한다.

### 시나리오 16: 중간지대(핀 히트 밖·20m 밖)에서 출발점에 훨씬 가까운 위치에서 긋기 → 출발점 쪽에 붙어야 함

**준비:** 이미 코스(출발~도착)가 그려진 상태. 지도를 적당히 줌아웃해 출발 핀에서 화면상 좀 떨어진(실거리 수백 m) 빈 공간이 보이게 한다. (1차 QA의 324m 케이스 재현.)

**수행:**
1. 그리기 모드에서, 출발 핀 근처(핀 히트는 안 걸릴 만큼 떨어진, 그러나 도착점보다는 확실히 출발점에 가까운) 위치에서 스트로크를 긋는다.
2. 새 구간이 어느 쪽에 붙는지 본다.

**기대 결과:** 출발점 쪽으로 이어붙는다(코스 출발 핀이 스트로크의 반대쪽 끝으로 이동). 예전처럼 도착점에서 긴 gap이 생기지 않는다.

**결과:** ☐ 통과 ☐ 실패
**메모:**

---

### 시나리오 17: 원거리에서 출발점을 향해 긋기 → 반전이 체감상 자연스러운지 (유일한 동작 변경점)

**준비:** 이미 코스가 그려진 상태. 출발점에서 수백 m 떨어진 지점이 보이는 배율.

**수행:**
1. 그리기 모드에서, 출발점에서 먼 지점에서 시작해 출발점 **방향으로** 스트로크를 긋는다(시작점이 도착점보다 출발점에 가까운 위치).
2. 코스의 달리는 순서(출발→도착)가 어떻게 되는지 확인한다 — 새로 붙은 구간이 "새 출발점 → 기존 출발점" 방향인지.

**기대 결과:** 스트로크가 반전되어 앞에 붙는다(그은 방향과 달리는 방향이 반대가 됨 — 규칙 3과 같은 "출발 방향 연장" 해석). 이게 체감상 자연스러운지 판단한다. 부자연스러우면 실패로 체크 — 위의 실패 기준이 발동된다.

**결과:** ☐ 통과 ☐ 실패
**메모:**

---

### 시나리오 18: 왕복 그리기 회귀 — 규칙 1·2 선점 유지

**준비:** 이미 코스(출발~도착)가 그려진 상태.

**수행:**
1. 도착 핀 근처에서 시작해 출발점 방향으로 되짚는 왕복 스트로크를 긋는다.
2. 닫힌 코스(출발≈도착)를 만든 뒤, 임의 위치에서 스트로크를 하나 더 긋는다.

**기대 결과:** 왕복 스트로크는 그린 그대로 도착점 뒤에 붙고(달리는 순서 유지), 닫힌 코스에서는 어떤 스트로크든 도착점 뒤에 붙는다(출발점이 바뀌지 않음) — 이번 변경 전과 동일해야 한다.

**결과:** ☐ 통과 ☐ 실패
**메모:**
```

- [ ] **Step 3: 커밋** (문서만 — 코드 스탬프는 Task 1 것이 남아있지 않으므로 다시 생성)

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "docs: attach-nearest-fallback 구현 반영 문서 갱신

- project-decisions: 규칙 4를 시작점 단일 최근접 비교로 갱신 (끝점 비교 금지 명문화)
- QA 체크리스트: 시나리오 16~18 (중간지대·반전 체감·왕복 회귀, 실패 기준 포함)" -- docs/agent-rules/project-decisions.md docs/qa/2026-07-04-gesture-consistency-device-checklist.md
```

---

### Task 3: 최종 검증 + 시뮬레이터 스모크

**Files:**
- 없음 (검증만 — 수정 발생 시 해당 파일)

**Interfaces:**
- Consumes: Task 1·2 커밋 완료 상태.
- Produces: 검증 결과 보고 (명령과 결과 그대로 — `superpowers:verification-before-completion`).

- [ ] **Step 1: 전체 검증 3종 재실행** — 빌드/테스트/린트 (Global Constraints 명령). Expected: 전부 PASS. 명령과 결과를 그대로 보고한다.

- [ ] **Step 2: 시뮬레이터 스모크** (XcodeBuildMCP `build_run_sim` — 테스트 툴 아님): 탭 2회로 경로 생성 → 그리기 모드 전환 → 기존 코스에서 떨어진 곳(출발점 쪽)에 스트로크 1회 → 코스가 출발점 쪽으로 연장되는지 + undo 1회 정상 동작 확인. 크래시·유령 마커 없음. (중간지대 거리 감각은 시뮬레이터로 판정 불가 — 정밀 검증은 실기기 QA 시나리오 16~18.)

- [ ] **Step 3: roadmap 마일스톤 상태 갱신 + 커밋** — `docs/roadmap.md`의 `- [~] **attach-nearest-fallback**` 줄을 `- [x]`로 바꾸고 줄 끝 `(구현 대기)`를 `(구현 완료, 실기기 QA 대기)`로 교체. 커밋:

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "docs: attach-nearest-fallback 마일스톤 구현 완료 표기" -- docs/roadmap.md
```

- [ ] **Step 4: 결과 보고** — 통과 시 "구현 완료, 실기기 QA(시나리오 16~18 + 기존 재검증 대기분) 대기" 상태로 보고. 아카이빙은 실기기 QA 통과 후 별도 진행.
