# Swift 6 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swift 6 언어 모드 전환 — 암묵/명시 isolation 정리, Sendable 정합, GCD 현대화, `SWIFT_VERSION = 6.0` + 경고 0.

**Architecture:** 스펙 `docs/superpowers/specs/2026-07-10-swift6-migration-design.md` 확정 전략 (a): `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 유지, 비-UI 타입만 `nonisolated` 명시. step 0에서 strict concurrency와 테스트 타깃 격리를 먼저 정렬해 확정 인벤토리를 얻고, 마지막에 순수 버전 플립.

**Tech Stack:** Swift 6.x / Xcode(`Trace.xcodeproj`, scheme `Trace`) / XCTest / SwiftLint

## Global Constraints

- **런타임 동작·UI 변경 금지** (리팩토링 전용). 테스트 삭제·약화 금지.
- 시뮬레이터: **iOS 26.5 고정**, `id=` destination만 사용(`name=` 금지), 세션당 시뮬레이터 하나만. UDID 취득:
  `SIM_UDID=$(xcrun simctl list devices "iOS 26.5" available | grep iPhone | head -1 | grep -oE '[0-9A-F-]{36}')`
- 테스트 실행은 반드시 raw xcodebuild + `-parallel-testing-enabled NO` (XcodeBuildMCP `test_sim` 금지 — testing.md 참고). 빌드/런치/UI 자동화에는 XcodeBuildMCP 사용 가능.
- 검증 명령 (이하 "BUILD"/"TEST"/"LINT"로 지칭):
  - BUILD: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" clean build-for-testing`
  - TEST: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test`
  - LINT: `swiftlint`
  - 경고 수 확인: BUILD 출력에서 `grep " warning:" | sort -u` (클린 빌드 필수 — 증분은 경고를 가림)
- 커밋: 각 Task 끝에서 BUILD/TEST/LINT 성공 후 스탬프 3종 갱신(`touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok`) → `scripts/trace-commit.sh -m "..." -- <경로들>`. push 금지.
- 브랜치: `refactor/swift6-migration` (이미 생성됨, 스펙 커밋 포함).

---

### Task 1: step 0 — 설정 선행 + 확정 인벤토리

**Files:**
- Modify: `Trace.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: 전 타깃 `SWIFT_STRICT_CONCURRENCY = complete`, 테스트 타깃 2개(TraceTests·TraceUITests)에 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. 클린 빌드 경고 목록 = **확정 작업 인벤토리**(이후 Task들의 대상 판정 기준).

- [ ] **Step 1: pbxproj 설정 추가** — 6개 빌드 설정 블록 전부(현재 `SWIFT_APPROACHABLE_CONCURRENCY = YES`가 있는 각 블록)에 `SWIFT_STRICT_CONCURRENCY = complete;` 추가. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;`가 없는 4개 블록(TraceTests·TraceUITests의 Debug/Release)에 추가. 알파벳 순서 유지(`SWIFT_STRICT_...`는 `SWIFT_DEFAULT_...` 뒤, `SWIFT_UPCOMING_...` 앞).
- [ ] **Step 2: 인벤토리 확보** — BUILD 실행, 출력의 `grep " warning:" | sort -u` 목록을 저장(예: `docs/superpowers/plans/swift6-warning-inventory.txt`에 임시 기록 — 커밋 제외, 작업용). Expected: 빌드 성공, 동시성 경고 다수(Swift 5 모드라 에러 아님).
- [ ] **Step 3: TEST 실행** — Expected: 전체 그린(경고는 무관).
- [ ] **Step 4: 스탬프 갱신 후 커밋** — `chore: Swift 6 전환 step 0 — strict concurrency·테스트 격리 정렬` (본문 3줄: 설정 2종 추가 이유, 인벤토리 확보, Swift 5 모드라 경고 수준임을 명시). 경로: `Trace.xcodeproj/project.pbxproj`

### Task 2: Domain 타입 nonisolated + Sendable (스펙 ①③)

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Entity/CourseCoordinate.swift`, `CourseSegment.swift`, `PlannedCourse.swift`, `SavedCourse.swift`, `Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift`, `CoursePlanningError.swift`, `DrawnPathSampler.swift`, `Trace/Domain/Location/LocationError.swift`

**Interfaces:**
- Produces: Domain 값 타입 전부 `nonisolated` — actor·테스트 어디서나 격리 경고 없이 사용 가능. 기존 API 시그니처 불변.

- [ ] **Step 1: 타입 선언에 `nonisolated` 접두** — 기계적 변환: 각 파일의 최상위 타입 선언 `struct|enum|final class X: ...` → `nonisolated struct|enum|final class X: ...`. extension도 동일(`nonisolated extension CourseCoordinate`). 예(검증된 현재 선언): `struct CourseCoordinate: Equatable, Sendable` → `nonisolated struct CourseCoordinate: Equatable, Sendable`.
- [ ] **Step 2: Sendable 명시 추가** — 아직 없는 타입에만: `CoursePlanningError`·`LocationError`(enum: Error 뒤에 `, Sendable` — 이미 Error가 Sendable을 함의하나 스펙이 의도 문서화를 요구), `DrawnPathSampler`. `CourseCoordinate`·`CourseSegment`·`PlannedCourse`·`SavedCourse`는 이미 명시돼 있음 — 건드리지 않는다.
- [ ] **Step 3: BUILD** — Expected: 성공, Task 1 인벤토리 대비 Domain 타입 관련 경고 소멸(경고 수 감소를 수치로 기록).
- [ ] **Step 4: TEST** — Expected: 전체 그린.
- [ ] **Step 5: LINT + 스탬프 + 커밋** — `refactor: Domain 값 타입 nonisolated·Sendable 명시` (경로: 위 8개 파일)

### Task 3: Infrastructure 타입 nonisolated (스펙 ①③)

**Files:**
- Modify: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift`, `CoursePersistenceModels.swift`, (인벤토리 조건부) `Trace/Infrastructure/Camera/CameraStateStore.swift`

**Interfaces:**
- Consumes: Task 1 인벤토리.
- Produces: `CourseRecord`가 actor 실행기에서 에러 없이 생성/접근 가능(비-Sendable·actor 내부 유지 그대로).

- [ ] **Step 1: CourseRecord nonisolated** — 검증된 현재 선언 기준:
```swift
@Model
nonisolated final class CourseRecord {
```
(암묵 @MainActor만 제거 — Sendable 아님, `SwiftDataCourseRepository` actor 밖으로 나가지 않는 기존 구조·MVP11 lazy context 수정 보존)
- [ ] **Step 2: CoursePersistenceDTO** — 타입 선언 `nonisolated` 접두 + `Sendable` 명시(없다면).
- [ ] **Step 3: CameraStateStore 판정** — Task 1 인벤토리에 CameraStateStore 관련 경고가 **있으면** `nonisolated` 접두(UserDefaults는 스레드 세이프), **없으면 무변경**(main 전용 사실이 확인된 것 — 판정 결과를 커밋 본문에 기록).
- [ ] **Step 4: BUILD·TEST·LINT + 스탬프 + 커밋** — `refactor: Persistence 타입 nonisolated 정리` (경로: 변경 파일만)

### Task 4: Pages 순수 로직 감사 (스펙 ① — 조건부)

**Files:**
- Modify(조건부): `Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift`, `SegmentPalette.swift`, `SegmentPanelLogic.swift`, `TapClassifier.swift`

**Interfaces:**
- Consumes: Task 1 인벤토리(테스트 격리 정렬 **이후** 시맨틱스 — 스펙 리뷰 반영: 이 그룹은 ①에서 빠질 가능성 높음).

- [ ] **Step 1: 인벤토리 대조** — 위 4개 타입 관련 경고가 인벤토리에 남아 있는지 확인. **없으면 이 Task는 변경 없이 종료**(체크만 하고 다음 Task로 — 판정 근거를 다음 커밋 본문에 한 줄 기록). 있으면 해당 타입만 `nonisolated` 접두.
- [ ] **Step 2(변경 시에만): BUILD·TEST·LINT + 스탬프 + 커밋** — `refactor: Pages 순수 로직 nonisolated 정리`

### Task 5: 명시 @MainActor 감사 (스펙 ②)

**Files:**
- Modify: `Trace/Domain/Location/Protocol/LocationServiceProtocol.swift`, `Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift`, `Trace/Domain/CoursePlanning/Protocol/CourseRepositoryProtocol.swift`, `Trace/Application/CoursePlanning/CourseEditSession.swift`, `Trace/App/DependencyContainer.swift`, `Trace/Infrastructure/Location/CoreLocation/CoreLocationService.swift`, `Trace/Infrastructure/Location/CoreLocation/ContinuationBroadcaster.swift`, `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`

**Interfaces:**
- Produces: Domain 프로토콜은 `nonisolated protocol`(구현체가 격리 선택), main 전용 타입들은 무표기(기본 격리가 커버). 시그니처·동작 불변.

⚠️ 핵심: 기본 격리 모드에서는 **무표기 프로토콜도 암묵 @MainActor**가 된다. 따라서 "제거"가 아니라 **`nonisolated` 명시**가 맞다.

- [ ] **Step 1: 서비스 프로토콜 2개** — `@MainActor` 줄 삭제 + `nonisolated` 접두:
```swift
nonisolated protocol LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate
}
```
`CoursePlanningServiceProtocol`도 동일 + 그 아래 `extension CoursePlanningServiceProtocol`을 `nonisolated extension CoursePlanningServiceProtocol`로(기본 구현 `snappedRoute`/`routeWithRetry`가 main에 묶이지 않게).
- [ ] **Step 2: CourseRepositoryProtocol** — actor 구현체(`SwiftDataCourseRepository`)를 가지므로 `nonisolated protocol`로 명시(스펙 ①의 취지 — 무표기 방치 시 암묵 @MainActor).
- [ ] **Step 3: 구현체·main 전용 타입 중복 표기 제거** — 기본 격리가 동일 의미를 제공하므로 명시 `@MainActor`만 삭제(동작 불변): `CourseEditSession.swift:4`, `DependencyContainer.swift:9,19`(멤버 2곳), `CoreLocationService.swift:4`(delegate 콜백의 `Task { @MainActor in }` 3곳은 **유지**), `ContinuationBroadcaster.swift:6`, `CoursePlannerPageViewModel.swift:18`. `MapKitCoursePlanningService`는 무표기 그대로 = MainActor 유지(스펙 ② 표의 "구현체가 선택한 격리" — 가변 라우트 캐시 main 한정). isolated conformance 경고가 새로 나오면 해당 conformer 선언에 `@MainActor`를 남기는 쪽으로 되돌린다(삭제는 경고 0을 깨지 않는 범위에서만).
- [ ] **Step 4: BUILD** — Expected: 성공, 프로토콜 강제 격리 관련 경고 소멸. **새 경고 0건 추가 확인**(nonisolated 프로토콜 × MainActor conformer의 isolated conformance는 `SWIFT_APPROACHABLE_CONCURRENCY`가 허용).
- [ ] **Step 5: TEST·LINT + 스탬프 + 커밋** — `refactor: Domain 프로토콜 nonisolated 명시 및 중복 @MainActor 정리`

### Task 6: GCD → Task 교체 (스펙 ④)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (Coordinator, 현재 546~565행 부근 + `markerShowWorkItem`/`confirmWorkItem` 참조 전부)

**Interfaces:**
- Consumes: Coordinator는 기본 격리로 main-isolated → `Task {}`가 MainActor를 상속(스레드 의미 동일).
- Produces: 동일한 스케줄/취소 시맨틱스의 `markerShowTask`/`confirmTask`.

- [ ] **Step 1: 프로퍼티 교체** — `private var markerShowWorkItem: DispatchWorkItem?` → `private var markerShowTask: Task<Void, Never>?`, `confirmWorkItem` → `confirmTask` (선언부를 grep으로 찾아 교체).
- [ ] **Step 2: 스케줄 함수 교체** — 검증된 현재 코드(546~565행)를 다음으로:
```swift
private func scheduleMarkerShow() {
    markerShowTask?.cancel()
    guard let coordinate = pendingCoordinate else { return }
    let role = pendingPinRole
    markerShowTask = Task { [weak self] in
        try? await Task.sleep(until: .now + .seconds(Self.markerShowDelay), tolerance: .zero, clock: .continuous)
        guard !Task.isCancelled else { return }
        self?.parent.onPendingTap?(coordinate, role)
    }
}

private func scheduleConfirm(in mapView: MKMapView) {
    confirmTask?.cancel()
    let window = tapClassifier.window
    confirmTask = Task { [weak self, weak mapView] in
        try? await Task.sleep(until: .now + .seconds(window), tolerance: .zero, clock: .continuous)
        guard !Task.isCancelled, let self, let mapView else { return }
        self.process(self.tapClassifier.windowElapsed(time: CACurrentMediaTime()), in: mapView)
    }
}
```
(`tolerance: .zero` + `.continuous`는 `asyncAfter` deadline과의 타이밍 패리티용 — 스펙 리뷰 잔여 리스크 반영)
- [ ] **Step 3: 나머지 참조 치환** — `grep -n "WorkItem" Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`로 남은 참조(취소 지점: 535행 부근 등) 전부 `xxxTask?.cancel()` / `xxxTask = nil` 패턴으로 교체. `import Dispatch`성 잔재 없음 확인.
- [ ] **Step 4: BUILD·TEST** — Expected: 그린. ⚠️ `TapClassifierTests`는 이 변경을 커버하지 않음(순수 상태머신만) — 회귀 검증은 Task 8 스모크가 전담.
- [ ] **Step 5: LINT + 스탬프 + 커밋** — `refactor: 탭 판별·마커 지연 타이머를 Task 기반으로 교체`

### Task 7: 언어 모드 플립 + 결정 기록 (스펙 ⑤)

**Files:**
- Modify: `Trace.xcodeproj/project.pbxproj`, `docs/agent-rules/project-decisions.md`

- [ ] **Step 1: SWIFT_VERSION 플립** — 6개 블록 전부 `SWIFT_VERSION = 5.0;` → `SWIFT_VERSION = 6.0;` (설정은 step 0에서 정렬 완료 — 이 Task는 순수 플립).
- [ ] **Step 2: BUILD (경고 0 게이트)** — Expected: 빌드 성공 + `grep -c " warning:"` = **0**. 에러 발생 시: 인벤토리 밖의 신규 진단(주로 MapKit/CoreLocation Sendable 경계) → 어댑터 내부에서 값 타입 변환으로 해결(스펙 리스크 절의 포트-어댑터 원칙), 해결 불가 판단이면 **중단하고 보고**(스펙 재검토 필요 신호).
- [ ] **Step 3: TEST** — Expected: 전체 그린.
- [ ] **Step 4: project-decisions.md 기록** — Current Defaults에 한 줄 추가:
```markdown
- Swift 언어 모드: Swift 6 (2026-07-10, MVP12) — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 유지 + 비-UI 타입(nonisolated)·Domain 프로토콜(nonisolated protocol) 명시 전략. 새 타입 작성 시 이 규칙을 따른다. 상세: `docs/superpowers/specs/2026-07-10-swift6-migration-design.md` §1
```
- [ ] **Step 5: LINT + 스탬프 + 커밋** — `refactor: Swift 6 언어 모드 전환 — 전 타깃 경고 0` (경로: pbxproj + project-decisions.md)

### Task 8: 시뮬레이터 스모크 + 마무리

**Files:** 없음 (검증 전용)

- [ ] **Step 1: 앱 실행** — XcodeBuildMCP `build_run_sim`(동일 시뮬레이터). Expected: 정상 부팅, 지도 표시.
- [ ] **Step 2: 스모크 시나리오 (수용 기준 3 전체)** — 각각 확인:
  1. 탭 2회 → 경로 생성·거리 표시 (탭 보류 확정 정상)
  2. 더블탭 → 줌만 되고 **포인트 안 찍힘**
  3. 빠른 연속 단일 탭 → 잔여 마커·잔여 포인트 없음 (취소 레이스)
  4. 탭 직후 즉시 팬 → 포인트 안 찍힘 (취소 경로)
  5. 그리기 모드로 스트로크 → 경로 붙음
  6. 코스 저장 → 목록에서 불러오기 정상
- [ ] **Step 3: 최종 검증** — `superpowers:verification-before-completion` 기준으로 BUILD(경고 0)·TEST·LINT 최종 1회 재확인 + roadmap의 `swift6-migration` 마일스톤 `[x]` 갱신·커밋(`docs: swift6-migration 마일스톤 완료`).
- [ ] **Step 4: 브랜치 리뷰 요청** — 표준 무게 최종 리뷰: `superpowers:requesting-code-review`(또는 `/code-review`)로 브랜치 전체 diff 리뷰 → 발견 반영 후 사용자에게 통합(`scripts/trace-integrate.sh`) 여부 확인. **push·통합은 사용자 승인 후에만.**

---

## 참고 (구현 세션용)

- 스펙: `docs/superpowers/specs/2026-07-10-swift6-migration-design.md` (리뷰 반영 확정본, 커밋 ccd3a25)
- 알려진 함정: iOS 26.5 외 런타임 금지(`@Observable` malloc 크래시), 병렬 테스트 금지, 훅 우회 금지(`--no-verify` 차단됨), 시뮬레이터 전환 금지(세션당 하나)
- Task 4가 no-op이어도 실패가 아님 — step 0의 테스트 격리 정렬이 근거를 제거한 정상 경로(스펙 리뷰 A2 반영)
