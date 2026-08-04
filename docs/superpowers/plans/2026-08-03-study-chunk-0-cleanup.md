# 청크 0 학습에서 나온 정비 — 대상 목록·분류

> **작업 종류: 정비** (`workflow.md` 작업 종류 표). 설계 문서·문서 리뷰·최종 브랜치 리뷰 없음.
> **이 표가 정비 경로의 1단계**이고 생략 금지 항목이다.
> 재료: 2026-08-03 학습 청크 0에서 사용자 질문으로 발견한 6건. 원문은 `docs/backlog.md`.
> 노트: `docs/study/0-app-architecture.html`

**Goal:** 앱 동작을 바꾸지 않으면서, 학습 중 드러난 잔재와 구멍 5건을 정리한다.

**결정(2026-08-04): MVP에 편입하지 않고 독립 정비 사이클로 돌린다.** 근거는 ①진행 중 MVP가
없고 ②다음 MVP "코스 연동"과 이 대상들이 무관하며 ③`workflow.md`의 새 MVP 기준(하나의 사용자
시나리오 완결 · 마일스톤 2~5개)에 미달한다는 것. `docs/roadmap.md` "진행 중 / 예정"에 등록했다.

---

## 분류 표

| # | 대상 | 갈래 | 위험 | 처분 |
|---|---|---|---|---|
| 1 | `Trace/App/ContentView.swift` | 죽은 코드 | 낮음 | 삭제 |
| 2 | `CoursePlannerPage.init`의 `cameraStateStore` 기본값 | 주입 구멍 | 낮음 | 기본값 제거 |
| 3 | `RunHistoryViewModel` 위치·이름 | 잘못 놓인 파일 | 중간 | `HistoryPage/`로 이동 + 개명 검토 |
| 4 | 테스트 전용 코드가 출시 빌드에 포함 | 빌드 구성 | 중간 | **선행 조사 필요** |
| 5 | Domain 프로토콜 4개의 `@MainActor` | 동시성 | 높음(검증만) | 떼고 컴파일 → 스모크 |
| — | 저장소 손상 복구 무고지 | **새 동작** | — | **이번 범위 제외** |

### 왜 6번을 뺐나

*"저장소가 고장 나면 사용자에게 알린다"*는 **없던 동작이 생긴다** — 무엇을 언제 몇 번 띄울지,
백업 파일 접근을 줄지가 전부 새 결정이다. 정비 조건("새 동작이 없다")을 위반하므로
**작은 기능 이상으로 따로 간다.** 발생 빈도가 매우 낮아 급하지 않다. 백로그에 그대로 둔다.

### 순서 근거

**1·2를 함께 먼저** — 둘이 이어져 있다. `cameraStateStore` 기본값이 있었기에 죽은 `ContentView`가
컴파일된 채 남아 있을 수 있었다. 기본값을 지우면 `ContentView`가 컴파일 에러가 나므로 같이 처리한다.

**5는 마지막** — MVP12에서 실기기 크래시(`18fa11a`)를 낸 영역이다. 앞의 것들이 그린인 상태에서
단독으로 건드려야 원인 추적이 된다. **다만 작업 자체는 4줄이라 계획 문서는 쓰지 않는다**(Task 4 머리말).

---

## Task 1: 죽은 코드와 주입 구멍 (#1 + #2)

**Files:**
- Delete: `Trace/App/ContentView.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (init 기본값 제거)

- [x] `ContentView.swift`를 삭제하고 Xcode 프로젝트에서도 제외한다.
      → 프로젝트가 `PBXFileSystemSynchronizedRootGroup`을 쓰므로 **디스크에서 지우면 끝**이고
      `.pbxproj` 편집이 필요 없었다(빌드 로그가 `ContentView.o` 스테일 제거로 확인).
- [x] `CoursePlannerPage.init`의 `cameraStateStore: CameraStateStore = CameraStateStore()`에서
      기본값을 제거한다. 호출부는 `RootView` 하나뿐이므로 파급이 없어야 한다 — 실측으로 확인한다.
      → **실측 정정: 호출부는 셋이다** — `RootView` · 삭제한 `ContentView` · `CoursePlannerPage.swift`
      맨 아래 `#Preview`. 다만 `#Preview`는 이미 `container.cameraStateStore`를 명시하고 있어
      기본값에 기대던 곳은 `ContentView` 하나뿐이었다. 결론(파급 없음)은 그대로다.
      → `CoursePlannerPageViewModel.init`에도 같은 기본값이 있으나 **건드리지 않는다**: 단위 테스트
      ~18개 호출부 중 3곳만 명시 전달이라 나머지가 전부 깨진다. 백로그가 지적한 구멍(uiTesting의
      격리된 `CameraStateStore(defaults:)`가 조용히 무시됨)은 Page 쪽 기본값이 사라지면 닫힌다 —
      Page는 받은 것을 항상 그대로 ViewModel에 넘기기 때문이다.
- [x] 빌드·테스트·린트 통과 확인. → 빌드 성공 · 테스트 384/384 통과 · 린트 5건(전부 사전 존재
      ③ 구조 경고, 백로그 기록분).

## Task 2: `RunHistoryViewModel` 위치와 이름 (#3)

**Files:**
- Move: `Trace/Pages/RunPage/RunHistoryViewModel.swift` → `Trace/Pages/HistoryPage/`

- [x] 파일을 `HistoryPage/`로 옮긴다(사용처는 `HistoryPage`와 `RootView`뿐, `RunPage`는 안 쓴다).
      → `git mv`만으로 끝. 동기화 그룹이라 `.pbxproj` 편집 불필요.
- [x] 개명(`RunHistoryStore` 등)을 할지 결정한다 — 이름은 ViewModel인데 실제 역할은
      공유 데이터 창고다. **개명은 참조가 여러 곳이라 이동과 분리해서 판단한다.**
      → **결정: 개명하지 않는다(보류).** 이름이 역할과 어긋난다는 지적 자체는 타당하다. 그런데
      `RunHistoryStore`로 가면 **`@Observable` 화면 상태에 `*Store`라는 새 명명 범주**가 생긴다 —
      이 프로젝트는 지금 전부 `*ViewModel`이다. 명명 규약은 `project-decisions.md`에 남길
      **열린 결정**이고, "열린 아키텍처 결정이 없다"는 정비 경로의 전제를 깬다. 파급도 참조
      개수(14곳)보다 넓다: 타입명 + `DependencyContainer.runHistoryViewModel` 프로퍼티 +
      `HistoryPageViewModel.history` + 테스트 파일명·클래스명. **위치 문제만 이번에 닫고,
      이름은 백로그에 남긴다.**
- [x] 빌드·테스트·린트 통과 확인. → 빌드 성공 · 테스트 383/383 통과 · 린트 5건(사전 존재분).

## Task 3: 테스트 전용 코드의 출시 빌드 포함 (#4) — 선행 조사

**Files:**
- Investigate: `Trace/App/DependencyContainer.swift`, `Trace/App/UITestingRunLocationStream.swift`

- [x] **먼저 UI 테스트가 어느 빌드 구성에서 도는지 확인한다.** Release에서 돈다면
      `#if DEBUG`로 감싸는 순간 UI 테스트가 깨진다 — 이 확인 없이 착수하지 않는다.
      → **Debug 전용 확인.** `Trace.xcscheme`의 `<TestAction buildConfiguration = "Debug">`.
      게이트 통과.
- [x] 확인 결과에 따라 처분을 정한다. Debug 전용이면 `#if DEBUG` 적용, 아니면 **이 Task는 접고**
      백로그로 되돌린다(무리해서 고치지 않는다). → `#if DEBUG` 적용.

**적용 범위 4곳:** `DependencyContainer.uiTesting()` · 파일 하단 private 가짜 3개 · `UITestingRunLocationStream`
전체 · `TraceApp.init`의 `-traceUITesting` 분기(Release는 `.live()` 직행).

**플랜이 예상 못 한 걸림돌 — `#Preview`가 Release에서도 컴파일된다.** 첫 Release 빌드가
`CoursePlannerPage.swift:361: type 'DependencyContainer' has no member 'uiTesting'`로 깨졌다.
앱 전체에 `#Preview`가 **하나뿐**이라 같은 기제(`#if DEBUG`)로 2줄 감싸 해결했다 — 프리뷰
구조를 손대지 않았으므로 "무리해서 고치지 않는다"에 걸리지 않는다.

**목적 달성 실측(바이너리 대조):**

| 산출물 | `UITesting`·`NoopVoice` 문자열 |
|---|---|
| Release `Trace.app/Trace` | **0건** ← 출시 빌드에서 사라짐 |
| Debug `Trace.debug.dylib` | 13건 ← UI 테스트 경로는 그대로 |

(같은 Release 바이너리에서 `CoursePlannerPage`는 10건 잡혀 `strings` 자체는 정상 동작 확인.)

- [x] 빌드(Debug·**Release 둘 다**)·테스트·린트 통과 확인. → Debug 빌드 성공 · Release 빌드 성공 ·
      테스트 383/383 통과(UI 테스트 8개 포함) · 린트 5건(사전 존재분).

## Task 4: Domain 프로토콜의 `@MainActor` 떼기 (#5)

> **계획 문서를 쓰지 않는다.** 처음엔 "위험 갈래 = 계획 문서" 규칙을 분류만 보고 적용했으나,
> **위험도와 계획 문서 필요성은 다른 축**이다. 위험하다는 건 *깨질 수 있다*(→ 검증 필요)이고,
> 계획 문서가 필요하다는 건 *정할 게 많다*는 뜻인데 **여기는 정할 게 없다** — 4줄을 떼고
> 컴파일러가 가리키는 곳을 고치면 끝이다. **대신 스모크는 면제하지 않는다.**

**Files:**
- `Trace/Domain/Location/Protocol/LocationServiceProtocol.swift`
- `Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift`
- `Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift`
- `Trace/Domain/RunTracking/Protocol/RunLocationStreamProtocol.swift`

- [ ] 네 프로토콜에서 `@MainActor` 한 줄씩을 뗀다.
- [ ] 컴파일한다. **깨지는 곳은 대부분 가짜 구현체 6개**로 예상된다 —
      진짜 구현체 4개는 이미 자체 `@MainActor`를 갖고 있어 영향이 없다(실측 확인).
      가짜는 `UITestingCoursePlanningService`·`UITestingLocationService`·`NoopVoiceAnnouncer`
      (`DependencyContainer.swift` 내부) · `UITestingRunLocationStream` ·
      `FakeVoiceAnnouncer`·`MockRunLocationStream`(테스트 타깃).
- [ ] ⚠️ `VoiceAnnouncerProtocol`은 나머지 셋과 다르다 — `announce`가 **`async`가 아니라서**
      파급이 다르게 나올 수 있다. 여기서 크게 번지면 **이 프로토콜만 남겨두고 셋만 처리**해도 된다.
- [ ] **시뮬레이터 스모크 필수** — 저장 코스 불러오기 · 지도 렌더링 · 달리기 시작 · 음성 안내.
      MVP12 크래시가 컴파일 경고 없이 런타임에만 드러났다(`ios-swift.md` "위험 신호 셋").

### 이 Task의 요점과 중단 기준

**요점:** 프로토콜이 "너희 전부 메인에서 돌아라"고 강제하던 것을 빼서,
**필요한 곳에서만 각자 `@MainActor`를 붙이게** 한다. MVP12 설계가 원했던 형태다(*"격리는 구현체가 선택"*).

**중단 기준 — 아래가 나오면 되돌리고 백로그로 돌린다.**

| 신호 | 판정 |
|---|---|
| 구현체에 `@MainActor`가 **늘어난다** | ✅ 통과 — 예상된 결과다. 조이는 방향이라 안전하다 |
| **`nonisolated`를 새로 붙여야 한다** | 🛑 **멈춤** — 푸는 방향이다. *"메인 아니어도 된다"*고 우겼다가 실제로는 메인이어야 했던 것이 **MVP12에서 앱이 죽은 방식**이다. 왜 필요한지 이해하기 전엔 붙이지 않는다 |
| 컴파일 에러가 **가짜 구현체 밖으로 번진다** | 🛑 멈춤 — 진짜 구현체·호출부까지 고쳐야 하면 예상 밖이다 |
| 스모크에서 뭐라도 이상하다 | 🛑 멈춤 |

**되돌리기는 쉽다** — Task 1~3이 먼저 커밋된 상태에서 시작하므로 그 커밋으로 돌아가면 된다.

---

## 마친 뒤

- [ ] `/trace-study`로 `docs/study/0-app-architecture.html`에 "정비에서 이렇게 바꿨다"를 덧쓴다.
      노트의 "왜 이렇게 됐나"와 백로그 언급이 지금 상태와 어긋나므로 반드시 갱신한다.
- [ ] 처리된 백로그 항목을 닫는다.
- [ ] `ce-compound` 판단 — 재사용 가능한 교훈이 있으면 기록한다.
