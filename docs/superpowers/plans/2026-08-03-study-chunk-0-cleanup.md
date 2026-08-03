# 청크 0 학습에서 나온 정비 — 대상 목록·분류

> **작업 종류: 정비** (`workflow.md` 작업 종류 표). 설계 문서·문서 리뷰·최종 브랜치 리뷰 없음.
> **이 표가 정비 경로의 1단계**이고 생략 금지 항목이다.
> 재료: 2026-08-03 학습 청크 0에서 사용자 질문으로 발견한 6건. 원문은 `docs/backlog.md`.
> 노트: `docs/study/0-app-architecture.html`

**Goal:** 앱 동작을 바꾸지 않으면서, 학습 중 드러난 잔재와 구멍 5건을 정리한다.

**미결(킥오프에서 사용자가 정할 것):** 이 정비를 어느 MVP 아래 마일스톤으로 붙일지, 아니면
독립 사이클로 돌릴지. `docs/roadmap.md`의 다음 MVP는 "코스 연동"으로 예정돼 있다.

---

## 분류 표

| # | 대상 | 갈래 | 위험 | 처분 |
|---|---|---|---|---|
| 1 | `Trace/App/ContentView.swift` | 죽은 코드 | 낮음 | 삭제 |
| 2 | `CoursePlannerPage.init`의 `cameraStateStore` 기본값 | 주입 구멍 | 낮음 | 기본값 제거 |
| 3 | `RunHistoryViewModel` 위치·이름 | 잘못 놓인 파일 | 중간 | `HistoryPage/`로 이동 + 개명 검토 |
| 4 | 테스트 전용 코드가 출시 빌드에 포함 | 빌드 구성 | 중간 | **선행 조사 필요** |
| 5 | Domain 프로토콜 4개의 `@MainActor` | 동시성 | **높음** | 계획 문서 후 진행 |
| — | 저장소 손상 복구 무고지 | **새 동작** | — | **이번 범위 제외** |

### 왜 6번을 뺐나

*"저장소가 고장 나면 사용자에게 알린다"*는 **없던 동작이 생긴다** — 무엇을 언제 몇 번 띄울지,
백업 파일 접근을 줄지가 전부 새 결정이다. 정비 조건("새 동작이 없다")을 위반하므로
**작은 기능 이상으로 따로 간다.** 발생 빈도가 매우 낮아 급하지 않다. 백로그에 그대로 둔다.

### 순서 근거

**1·2를 함께 먼저** — 둘이 이어져 있다. `cameraStateStore` 기본값이 있었기에 죽은 `ContentView`가
컴파일된 채 남아 있을 수 있었다. 기본값을 지우면 `ContentView`가 컴파일 에러가 나므로 같이 처리한다.

**5는 마지막** — MVP12에서 실기기 크래시(`18fa11a`)를 낸 영역이다. 앞의 것들이 그린인 상태에서
단독으로 건드려야 원인 추적이 된다.

---

## Task 1: 죽은 코드와 주입 구멍 (#1 + #2)

**Files:**
- Delete: `Trace/App/ContentView.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (init 기본값 제거)

- [ ] `ContentView.swift`를 삭제하고 Xcode 프로젝트에서도 제외한다.
- [ ] `CoursePlannerPage.init`의 `cameraStateStore: CameraStateStore = CameraStateStore()`에서
      기본값을 제거한다. 호출부는 `RootView` 하나뿐이므로 파급이 없어야 한다 — 실측으로 확인한다.
- [ ] 빌드·테스트·린트 통과 확인.

## Task 2: `RunHistoryViewModel` 위치와 이름 (#3)

**Files:**
- Move: `Trace/Pages/RunPage/RunHistoryViewModel.swift` → `Trace/Pages/HistoryPage/`

- [ ] 파일을 `HistoryPage/`로 옮긴다(사용처는 `HistoryPage`와 `RootView`뿐, `RunPage`는 안 쓴다).
- [ ] 개명(`RunHistoryStore` 등)을 할지 결정한다 — 이름은 ViewModel인데 실제 역할은
      공유 데이터 창고다. **개명은 참조가 여러 곳이라 이동과 분리해서 판단한다.**
- [ ] 빌드·테스트·린트 통과 확인.

## Task 3: 테스트 전용 코드의 출시 빌드 포함 (#4) — 선행 조사

**Files:**
- Investigate: `Trace/App/DependencyContainer.swift`, `Trace/App/UITestingRunLocationStream.swift`

- [ ] **먼저 UI 테스트가 어느 빌드 구성에서 도는지 확인한다.** Release에서 돈다면
      `#if DEBUG`로 감싸는 순간 UI 테스트가 깨진다 — 이 확인 없이 착수하지 않는다.
- [ ] 확인 결과에 따라 처분을 정한다. Debug 전용이면 `#if DEBUG` 적용, 아니면 **이 Task는 접고**
      백로그로 되돌린다(무리해서 고치지 않는다).

## Task 4: Domain 프로토콜의 `@MainActor` (#5) — 위험 갈래

> **이 Task만 `superpowers:writing-plans`로 상세 계획을 쓴다.** 정비 경로의 "위험 갈래에만
> 상세 계획" 규칙에 해당한다. 아래는 착수 전 확인 사항이고, Task 분해는 계획 문서에서 한다.

**Files:**
- `Trace/Domain/*/Protocol/` 4개 — `LocationServiceProtocol` · `CoursePlanningServiceProtocol` ·
  `VoiceAnnouncerProtocol` · `RunLocationStreamProtocol`

- [ ] 상세 계획 문서를 쓴다.
- [ ] 프로토콜에서 `@MainActor`를 떼고 구현체 4곳에만 남긴다.
- [ ] 호출부가 이미 `await`을 쓰고 있는지 실측한다 — 파급이 작을 것으로 보이나 확인 전엔 모른다.
- [ ] **시뮬레이터 스모크 필수.** MVP12 크래시가 컴파일 경고 없이 런타임에만 드러났다
      (`ios-swift.md` "위험 신호 셋" 참고). 저장 코스 불러오기·지도 렌더링·달리기 시작을 직접 본다.

---

## 마친 뒤

- [ ] `/trace-study`로 `docs/study/0-app-architecture.html`에 "정비에서 이렇게 바꿨다"를 덧쓴다.
      노트의 "왜 이렇게 됐나"와 백로그 언급이 지금 상태와 어긋나므로 반드시 갱신한다.
- [ ] 처리된 백로그 항목을 닫는다.
- [ ] `ce-compound` 판단 — 재사용 가능한 교훈이 있으면 기록한다.
