# MVP12 swift6-migration — Swift 6 동시성 전면 리팩토링 (2026-07-10)

MVP12 `swift6-migration` 마일스톤(사이클 1, **표준 무게**)의 스펙. 백로그(2026-07-08,
사용자 결정) 범위 ①~⑤를 그대로 따르되, 이번 조사로 확인한 현황과 접근 방식을 확정한다.
런타임 동작 변경 없음 — 목적은 "다음 persistence 확장(달리기 기록)과 design-apply가
처음부터 깨끗한 Swift 6 기반 위에서 작성되게 하는 정지작업"이다.

## 0. 현황 (2026-07-10 조사, refactor/swift6-migration 기준)

- `SWIFT_VERSION = 5.0` — 프로젝트/타깃 6개 설정 블록 전부
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — 전 블록
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **앱 타깃 2개 블록에만** 존재, 테스트 타깃엔 없음
  → 앱 타깃의 무표기 타입(Entity·DTO·순수 로직 전부)이 암묵 @MainActor가 되고, actor
  저장소(`SwiftDataCourseRepository`)·테스트에서 쓰일 때 "Swift 6에서 에러" 경고 ~40건
  (2026-07-08 전체 리빌드로 확인 — 증분 빌드는 이를 가림)
- 명시 `@MainActor` 11곳: Domain 프로토콜 `LocationServiceProtocol`·`CoursePlanningServiceProtocol`
  (타입 전체), `CourseEditSession`, `DependencyContainer`(멤버 2곳), `CoreLocationService`
  (+delegate 콜백 `Task { @MainActor in }` 3곳), `ContinuationBroadcaster`, `CoursePlannerPageViewModel`
- 레거시 GCD: `MapViewRepresentable.swift:554,564` — `DispatchQueue.main.asyncAfter` +
  `DispatchWorkItem` (마커 표시 지연 100ms, 탭 판별 윈도우 타이머; WorkItem cancel로 취소 구현)

## 1. 핵심 접근 결정: 기본 격리는 유지하고, 비-UI 타입을 명시적으로 뺀다

두 가지 접근을 비교했다:

- **(a) `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 유지 + 비-UI 타입에 `nonisolated` 명시** ← **채택**
  - Apple의 single-target 앱 권장 구성(approachable concurrency)과 일치. UI·ViewModel·
    오케스트레이터는 무표기로 main에 남고, 경계를 넘는 타입만 명시적으로 빠진다.
  - 표기가 늘어나는 곳 = Domain/Infrastructure의 값 타입·순수 로직 — "이 타입은 어디서나
    안전"이라는 의도가 코드에 드러난다.
- (b) 기본 격리를 제거하고 필요한 곳에 `@MainActor` 명시
  - UI 쪽 표기가 대폭 늘고(모든 View 헬퍼·ViewModel·세션), SwiftUI 앱에서 실수 방향이
    "UI가 main 밖" 쪽으로 뒤집혀 더 위험. 기각.

결정 (a)는 코드 조직 수준의 기술 결정이므로 Decision Policy상 에이전트가 확정하고
`project-decisions.md`에 기록한다(구현 커밋에 포함).

## 2. 작업 범위 (백로그 ①~⑤의 구체화)

### ① 암묵 isolation 정리 — 비-UI 타입 `nonisolated` 일괄 명시

대상(파일 단위 감사 후 확정, 예상 목록):

- Domain Entity·값: `CourseCoordinate`(+`+Geo`), `CourseSegment`, `PlannedCourse`, `SavedCourse`,
  `CoursePlanningError`, `LocationError`, `DrawnPathSampler`
- Infrastructure: `CoursePersistenceDTO`, `CoursePersistenceModels` — **`CourseRecord`(@Model)도
  `nonisolated` 대상**: actor 저장소가 자기 실행기에서 생성/읽기하므로 암묵 @MainActor로는 ⑤
  시점에 컴파일 에러가 된다. `nonisolated`는 암묵 main 격리만 제거하며, 비-Sendable·actor 내부
  유지 구조(③)는 그대로다. `CameraStateStore`(감사 필요 — UserDefaults 접근)
- Pages 순수 로직: `OverlapOffsetResolver`, `SegmentPalette`, `SegmentPanelLogic`, `TapClassifier`
  (View에서만 쓰이면 main 유지도 가능 — 테스트 타깃에서 접근하므로 nonisolated 우선 검토)

부분 수정(개별 메서드 `nonisolated`)은 경고를 옮길 뿐임이 실험으로 확인됐으므로(2026-07-08)
**타입 단위**로 정리한다.

### ② 명시 @MainActor 감사

| 대상 | 판정 방향 |
|---|---|
| `LocationServiceProtocol`, `CoursePlanningServiceProtocol` | **프로토콜에서 @MainActor 제거**(사용자 지적 사항) — Domain 프로토콜이 모든 구현체를 main으로 강제할 이유 없음. `nonisolated` + `async` 요구사항으로 두고 격리는 구현체가 선택 |
| `CoreLocationService` | CLLocationManager delegate 특성상 main 유지가 자연스러움 — 명시 @MainActor 유지(기본 격리로 커버되면 표기는 정리) |
| `MapKitCoursePlanningService` | **MainActor 유지**(앱 기본 격리 — 프로토콜 de-isolation 후 "구현체가 선택한" 격리를 명시) — 가변 라우트 캐시가 main 한정으로 남고 async MKDirections 호출은 영향 없음 |
| `CourseEditSession`, `DependencyContainer`, `CoursePlannerPageViewModel` | main 전용이 맞음 — 기본 격리(무표기)로 충분해지면 **중복 표기 제거** |
| `ContinuationBroadcaster` | main 유지(기본 격리로 무표기화). 가변 continuation 상태가 checked isolation에 의존하므로 **nonisolated화는 하지 않는다** — 비-main 사용처가 실제로 생기면 그때 재검토 |

### ③ Sendable 정합

- ①의 `nonisolated` 값 타입에 `Sendable` 명시. 단 `CourseCoordinate`·`CourseSegment`·
  `PlannedCourse`·`SavedCourse`는 **이미 명시돼 있음** — 실제 추가 대상은 `CoursePlanningError`·
  `LocationError`·`DrawnPathSampler`·`CoursePersistenceDTO`.
- 클로저 경계 `@Sendable` 정리 — 특히 서비스 프로토콜의 async 메서드와 delegate hop.
- SwiftData `@Model`(`CourseRecord`)은 Sendable 불가 — **actor(`SwiftDataCourseRepository`) 내부에
  유지하고 DTO로만 경계를 넘는 현 구조를 그대로 보존**(MVP11 affinity 수정 포함).

### ④ 동시성 문법 현대화

- `MapViewRepresentable`의 `asyncAfter`+`DispatchWorkItem` 2곳 → `Task` + `Task.sleep` +
  `task.cancel()`로 교체. ⚠️ 탭 판별 타이머(0.35초 보류 확정, MVP10)와 마커 지연(100ms)은
  **타이밍에 민감한 검증된 동작**. `TapClassifierTests`는 시간 주입 순수 상태머신만 검증하고
  교체 대상인 Coordinator 스케줄링(`MapViewRepresentable.swift:546~565`)은 커버하지 않는다 —
  **회귀 게이트는 시뮬레이터 스모크(수용 기준 3, 취소 레이스 포함)가 전담**한다.
- `CoreLocationService` delegate 콜백의 `Task { @MainActor in }` 패턴은 정석에 가까움 —
  격리 결정(②)에 맞춰 표기만 정돈.

### ⑤ 언어 모드 전환

- `SWIFT_VERSION = 5.0 → 6.0` — **6개 설정 블록 전부**(앱 + TraceTests + TraceUITests).
  격리·strict 설정은 step 0(§4)에서 이미 정렬됐으므로 ⑤는 **순수 버전 플립**이다.
- 전환 후 클린 `build-for-testing`에서 **경고 0** 확인.

## 3. 비목표 (Non-goals)

- 런타임 동작·UI 변경 없음. 기능 추가 없음.
- 디자인 적용 없음(design-apply 사이클 별도).
- 모듈 분리(SPM) 없음 — 추후 과제 유지.

## 4. 순서와 검증

작업 순서(플랜에서 Task로 세분화):

- **step 0 (착수 직후)**: 전 타깃 `SWIFT_STRICT_CONCURRENCY = complete` + 테스트 타깃
  (TraceTests·TraceUITests 모두)에 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 추가 —
  둘 다 Swift 5 모드에선 경고 수준이라 안전. 이 상태의 클린 전체 빌드 진단 목록이
  **확정 작업 인벤토리**(~40건 추정을 대체)이고, ① 감사는 이 최종 시맨틱스 기준으로
  수행한다(테스트 격리 정렬로 Pages 순수 로직 그룹이 ①에서 빠질 수 있음).
- ①→②→③ 파일 그룹 단위 진행, 각 체크포인트마다 **클린 빌드**(증분 빌드는 경고를 가림) +
  테스트 그린 유지 → ④ → ⑤(순수 언어 모드 플립 — 경고가 에러로 승격되는 시점).

수용 기준:

1. `SWIFT_VERSION = 6.0` 전 타깃, `xcodebuild clean build-for-testing`(앱+테스트 타깃 전부 컴파일) **경고 0**
2. 전체 테스트 그린(기존 17개 테스트 파일, 삭제·약화 없이)
3. 시뮬레이터 스모크: 탭 보류 확정(더블탭 줌 시 포인트 안 찍힘)·그리기·저장/불러오기 정상
   + ④ 취소 레이스: 빠른 연속 단일 탭 / 0.35초 경계 부근 더블탭 / 탭 직후 즉시 팬 —
   각각 잔여 마커·잔여 포인트 없음
4. `project-decisions.md`에 격리 전략(§1) 기록

리스크:

- iOS 18 `@Observable` malloc 크래시(문서화됨) — 테스트는 iOS 26 시뮬레이터 고정, 기존 방침 유지.
- MapKit/CoreLocation 타입의 Sendable 경계 — MKDirections 응답 등이 새 경고를 드러낼 수 있음.
  발견 시 어댑터 내부에서 값 타입으로 변환해 경계를 넘긴다(기존 포트-어댑터 원칙 그대로).
- 탭 제스처 타이밍 회귀(④) — 전용 스모크 시나리오로 방어.
