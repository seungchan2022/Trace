# 가로모드 시트 펼침 레이아웃 붕괴 수정 Implementation Plan

> **구현 완료·병합됨(소급 확인, 2026-07-21)** — Task 1~4 전부 구현·태스크별 리뷰 통과했고, 커밋은 이미 `main`에 병합됐다(`631ed10`~`22c3b23`, 브랜치 `feature/mvp16-landscape-sheet-overflow`는 삭제됨). 개별 Step 체크박스는 실행 중 갱신되지 않았으나(SDD 세션이 Task 단위 리뷰로 추적함), `docs/agent-rules/workflow.md`의 소급 정리 절차에 따라 체크박스는 그대로 두고 이 노트로 완료를 대신한다.
> **⚠️ 단, 이 플랜은 "완료"지 "해결"이 아니다** — 원버그(가로 시트 붕괴)는 고쳐졌지만 같은 수정에서 파생된 회귀 2건(다크모드 가로 좌우 검은 여백, 세로 풀시트 topBar 미커버)이 **미해결 상태로 `main`에 남아 있다.** 아래 "세션 마무리 메모"와 `docs/backlog.md`의 해당 항목을 반드시 함께 읽을 것. 재작업은 시트 구조 재설계 방향을 정한 뒤 `main`에서 새 브랜치로 시작한다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 가로모드에서 코스 탭 바텀시트를 medium/full로 펼치면 탭바가 화면 아래로, 시트가 화면 위로 뚫리는 레이아웃 붕괴를 3중 방어(구조 클램프 → 예산 클램프 → ratchet 분리)로 수정한다.

**Architecture:** ① `RootView`의 코스/러닝 영역을 `GeometryReader`로 감싸 자식이 아무리 부풀어도 VStack 배정량을 초과 보고하지 못하게 하고(탭바 보호), ② 시트 높이 예산(`maxSheetHeight`)을 "페이지가 실제 배정받은 높이"로 min-클램프해 시트가 위로 뚫릴 수 없게 하고(예산 클램프), ③ `topSafeAreaInset` ratchet을 세로/가로 size class별로 분리해 가로에서 세로 값(62pt)이 눌러앉는 stale 문제를 없앤다.

**Tech Stack:** SwiftUI (iOS 17+), Swift 6(클래식 격리), XCTest, XcodeBuildMCP(시뮬레이터 검증)

**실행 브랜치:** `feature/landscape-sheet-overflow` (main에서 새로 생성)

## Global Constraints

- Swift 6 언어 모드, 격리 기본값은 클래식(기본 nonisolated + UI 타입만 명시 `@MainActor`) — 새 순수 타입에는 어노테이션을 붙이지 않는다 (`docs/agent-rules/project-decisions.md`).
- 실제 필요 없는 곳에 어노테이션/코드를 남기지 않는다.
- 시뮬레이터는 **하나만** 사용: iPhone 17 Pro / iOS 26.5 (UUID `D887D0A4-074C-4AFB-8D08-D87329D0EFD4`). 실패해도 다른 시뮬레이터로 전환하지 않는다.
- **금지 1:** `bottomSheet` 전체에 `.frame(maxHeight:)`를 걸지 않는다 — 시트가 화면 위쪽 절반을 덮는 보이지 않는 히트테스트 영역이 되어 지도 탭이 전부 흡수되는 회귀가 실측된 바 있다 (`docs/solutions/ui-bugs/frame-maxheight-inflates-zstack-child-and-swallows-taps.md`). 오버슈트 방어는 반드시 리스트 높이(`expandedListHeight`) 계산 안쪽에서만.
- **금지 2:** `sheetTopMargin`(11pt)을 낮추지 않는다 — 피드백 루프 잔여분 11pt의 측정 기반 안전선이다.
- **금지 3:** Task 순서를 바꾸지 않는다. 특히 **Task 3(ratchet 분리)을 Task 1·2보다 먼저 하면 가로 full에서 시트가 실제로 화면 위로 뚫린다**(조사 리포트 실측 C: ratchet만 끄면 시트 top이 y=-56). 이 영역은 과거 2회 버그 이력(다이내믹 아일랜드 침범, 이번 가로 붕괴)이 있는 곳이다 — 순서가 곧 안전장치다.
- **세로 회귀 0:** 매 Task의 검증에서 세로 모드 값이 아래 "세로 known-good 실측값"과 일치해야 한다.
- Git: push 금지, `git add`는 명시적 경로만, `main` 직접 커밋 금지. 커밋 메시지는 최근 이력과 같은 `fix:`/`test:`/`docs:` + 한글 요약 형식.
- 새 Swift 파일은 pbxproj 수정 불필요 — 프로젝트가 PBXFileSystemSynchronizedRootGroup(폴더 동기화) 방식이라 `Trace/`·`TraceTests/` 아래 파일은 자동 포함된다.

---

## 배경 — 조사 리포트 요약 (2026-07-20 실측, 원문: `.git/sdd/task-landscape-layout-report.md`)

> 원문 리포트가 사라졌어도 이 섹션만으로 구현에 충분하도록 핵심을 전부 옮겨 놓았다.

### 증상과 재현

실기기 QA(2026-07-20)에서 발견: 세로에서 가로로 돌린 뒤 코스 탭 시트를 그래버로 한 단계씩 올리면 — 탭바가 화면 아래로 밀려 나가고(모든 경우 재현), 특정 조건에서 시트가 화면 위로 뚫린다. 세로 모드는 어떤 경우에도 정상(회전 왕복 후에도 클린).

### 레이아웃 구조

```
RootView.body:
  VStack(spacing: 0) {
      ZStack { CoursePlannerPage(opacity/hitTest) ; RunPage(opacity/hitTest) }   // "course area"
      if !tabBarHidden { TraceTabBar }
  }

CoursePlannerPage.body:
  ZStack(alignment: .bottom) {
      mapView.ignoresSafeArea()                  // mapHeight = proxy.size.height (자유 갱신)
      VStack { topBar; Spacer; fabStack }        // 크롬
      bottomSheet                                // grabber(25) + header(실측 ~97) + expandedSheetBody
  }
  .onGeometryChange(safeAreaInsets.top) { ratchet-up only → topSafeAreaInset }

파생값 (CoursePlannerPage+BottomSheetComponent.swift):
  panelMaxListHeight = mapHeight * 0.4
  maxSheetHeight     = mapHeight - topSafeAreaInset - sheetTopMargin(11)
  expandedListHeight(.medium) = panelMaxListHeight
  expandedListHeight(.full)   = max(panelMaxListHeight, maxSheetHeight - 25 - sheetHeaderHeight)
```

### 실측값 (iPhone 17 Pro / iOS 26.5 시뮬레이터)

물리 화면(레이아웃 좌표): **세로 ≈ 874**(safe 62..840), **가로 ≈ 402**(safe 0..382, top inset 0, 하단 home indicator ~20).

**A. 세로 known-good (이 값들과 비교해 회귀를 판정한다):**

| 상태 | topSafeAreaInset | raw | mapHeight | course ZStack(y) | TraceTabBar(y) | 시트 top(y) |
|---|---|---|---|---|---|---|
| 세로 collapsed | 62 | 62 | 784 | 62..784 (h=722) | 784..840 (h=56) | — |
| 세로 full | 62 | 62 | 784 | 62..784 (h=722) | 784..840 (h=56) | 73 (h=711) |

**B. 가로 버그 재현 (수정 전 현재 코드):**

| 상태 | top | raw | mapHeight | course ZStack(y) | TraceTabBar(y) |
|---|---|---|---|---|---|
| 가로 collapsed (회전 직후) | **62 stuck** | **0** | 335 | 0..335 ✅ | 335..382 ✅ |
| 가로 medium | 62 | 0 | **396** | **-30..365** | **365..412 ⬅ 아래로 뚫림** |
| 가로 full | 62 | 0 | **396** | **-30..365** | **365..412 ⬅ 아래로 뚫림** |

**C. "ratchet만 고침" 시뮬레이션 (가로 full, ratchet 임시 비활성):** mapHeight 458, 시트 **-56..391 ⬅ 위로 뚫림**, 탭바 391..438(더 나빠짐). **→ ratchet 단독 수정은 금지(Global Constraint 3의 근거).**

### 원인 (실측으로 확정된 것과 가설 구분)

- **원인 B(진짜 근본, 확정):** 가로에서 시트를 펼치면 course ZStack이 VStack 배정량(335)을 초과한 높이(medium/full 396)를 보고하고, VStack이 오버사이즈 자식을 **중앙 정렬로 오버플로**시켜 코스/지도는 위로(-30), 탭바는 아래로(+30) 동시에 밀린다. 두 증상은 단일 오버플로의 양면. 세로는 mapHeight가 커서(784) 시트가 배정량을 못 넘으므로 안전.
- **원인 A(확정, 그러나 보호막):** `topSafeAreaInset` ratchet("이 화면은 회전이 없다" 전제, `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`)이 가로에서 세로 값 62에 stale — 하지만 이 stale 값이 `maxSheetHeight`를 *더 작게* 만들어 가로 full 시트를 짧게 눌러주는 보호막 역할을 하고 있다. **A만 고치면 위 C처럼 시트가 진짜로 위로 뚫린다.**
- **미확정 가설:** ZStack을 396으로 부풀리는 1차 트리거는 `mapView.ignoresSafeArea()` 높이의 역전파로 보이나(시트 280 < ZStack 396이므로 시트 자체는 아님), 단정할 실측 근거는 없다. 그래서 수정은 메커니즘 추정에 기대지 않고 **어떤 오작동에도 견디는 구조적 차단**을 우선한다.

### 참고 파일

- `Trace/App/RootView.swift` — outer `VStack { ZStack(course); TraceTabBar }` (오버플로 발생 지점)
- `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` — ratchet(102-106행), mapHeight 측정(219-224행), 상태 선언(30-34행)
- `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` — sheetTopMargin(253행), maxSheetHeight(265-267행), expandedListHeight(274-285행)
- `Trace/DesignSystem/Component/TraceTabBar.swift` — 가로 47pt / 세로 56pt (verticalSizeClass 기반, 수정 불필요)

### 수정 설계 — 3중 방어, 각각 실패 방향이 안전

1. **Task 1 (구조 클램프):** course 영역이 배정량을 초과 보고하는 것 자체를 차단 → 탭바는 어떤 내부 오작동에도 절대 안 밀림.
2. **Task 2 (예산 클램프):** 시트 예산을 "실제 배정 높이"로 min-클램프 → 시트는 어떤 측정 오작동에도 위로 못 뚫음. 세로 값은 수식상 완전 동일(회귀 0).
3. **Task 3 (ratchet 분리):** size class별 latch로 가로에서 진짜 안전영역(0)을 쓰게 함 → 가로 full이 제 높이(예산 전부)에 도달. 잘못돼도 "시트가 짧아지는" 안전한 방향으로만 실패.

---

## 검증 공통 절차 (모든 Task에서 재사용)

**빌드/실행:** XcodeBuildMCP 세션 기본값 확인(`session_show_defaults`) 후 `build_run_sim`. 기본값이 비어 있으면 project `Trace.xcodeproj` / scheme `Trace` / simulator UUID `D887D0A4-074C-4AFB-8D08-D87329D0EFD4`로 설정.

**전체 테스트:** XcodeBuildMCP `test_sim` (같은 세션 기본값). 결과의 테스트 수와 green 여부를 기록한다.

**회전:** MCP에는 orientation 제어가 없다. `osascript`로 Simulator.app에 단축키를 보낸다 (검증된 방식):

```bash
# 가로(landscape left, ⌘→)
osascript -e 'tell application "Simulator" to activate' -e 'tell application "System Events" to key code 124 using command down'
# 세로 복귀 (⌘←)
osascript -e 'tell application "Simulator" to activate' -e 'tell application "System Events" to key code 123 using command down'
```

**프레임 측정:** `snapshot_ui`의 접근성 프레임을 쓴다(임시 계측 코드 불필요). 확인 대상 식별자:
- 탭바: `root.tabBar` (탭 아이템은 `root.tab.course` / `root.tab.run`)
- 시트 패널: `coursePlanner.segmentPanel`, 그래버: `coursePlanner.segmentPanel.grabber`
- 시트 헤더 탭 토글(=medium 진입 버튼): `coursePlanner.segmentPanel.collapsed`

**detent 구동 제약:** 시뮬레이터 MCP 백엔드는 터치 move 이벤트를 못 만들어(`FBSimulatorHIDEvent does not support touch move events`) 그래버 드래그가 불가능하다. **medium은 헤더 탭**(`coursePlanner.segmentPanel.collapsed` tap)으로 진입하고, **full은 `CoursePlannerPage.swift`의 `@State var sheetDetent: SheetDetent = .collapsed`를 임시로 `.full`로 바꿔** 도달한다(검증 후 반드시 원복하고 `git diff`로 확인).

**스크린샷:** 가로 상태의 `screenshot`은 세로 픽셀 방향으로 나온다 — `sips -r -90 <파일>`로 돌려서 본다.

**가로 통과 기준(고정):** 탭바 프레임 y+height ≤ 402(온스크린), 시트/그래버 top y ≥ 0, course 영역이 0..335를 벗어나지 않음. **세로 통과 기준:** 위 "A. 세로 known-good" 표와 일치.

---

### Task 1: RootView 구조 클램프 — 탭바가 절대 밀려나지 않게

**Files:**
- Modify: `Trace/App/RootView.swift`

**Interfaces:**
- Consumes: 없음 (기존 `AppTab.isTabBarHidden(runState:)`, `TraceTabBar(selection:)` 그대로)
- Produces: course 영역이 항상 "배정량과 정확히 같은 크기"를 보고하는 구조. 이후 Task들은 이 보장 위에서 동작한다.

**핵심 원리:** `GeometryReader`는 자식이 얼마나 크든 **항상 제안받은 크기를 자기 크기로 보고**한다. course ZStack을 그 안에 넣고 명시 프레임을 걸면, 내부가 어떤 측정 오작동으로 부풀어도 VStack 관점의 크기는 불변 → 탭바가 밀릴 수 없다. `alignment: .top`이라 잔여 내부 오버플로는 전부 아래쪽(불투명 탭바 뒤)으로 향하고, topBar 쪽은 움직이지 않는다. `.clipped()`는 걸지 않는다 — 세로에서 지도가 `ignoresSafeArea()`로 상태바 밑까지 그려지는 의도된 확장을 자르면 안 된다.

- [ ] **Step 1: RootView body 수정**

`Trace/App/RootView.swift`의 `body`를 다음으로 교체한다 (변경점: `GeometryReader` 래핑 + ZStack에 명시 프레임, 나머지는 그대로):

```swift
    var body: some View {
        VStack(spacing: 0) {
            // GeometryReader는 자식 크기와 무관하게 항상 제안받은 크기를 보고하므로,
            // 자식(코스 ZStack)이 어떤 측정 오작동으로 부풀어도 VStack 배정량을 절대
            // 초과하지 않는다 — 가로에서 시트를 펼치면 코스 ZStack이 배정량(335)을 초과한
            // 높이(396)를 보고해 VStack이 중앙 오버플로로 탭바를 화면 아래로 밀어내던
            // 버그의 구조적 차단막(2026-07-20 실측). alignment .top: 잔여 내부 오버플로가
            // 위(topBar/상태바)가 아니라 아래(불투명 탭바 뒤)로만 향하게 한다.
            // .clipped()는 걸지 않는다 — 지도의 ignoresSafeArea 확장(상태바 밑 풀블리드)은
            // 의도된 동작이라 잘리면 안 된다.
            GeometryReader { proxy in
                ZStack {
                    CoursePlannerPage(
                        coursePlanningService: container.coursePlanningService,
                        locationService: container.locationService,
                        cameraStateStore: container.cameraStateStore,
                        courseRepository: container.courseRepository
                    )
                    .opacity(selectedTab == .course ? 1 : 0)
                    .allowsHitTesting(selectedTab == .course)
                    .accessibilityHidden(selectedTab != .course)

                    RunPage(
                        session: container.runSession,
                        recordRepository: container.runRecordRepository,
                        announcer: container.voiceAnnouncer
                    )
                    .opacity(selectedTab == .run ? 1 : 0)
                    .allowsHitTesting(selectedTab == .run)
                    .accessibilityHidden(selectedTab != .run)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }

            // 러닝 플로우(시작~요약 닫기 전) 동안 탭바 자체를 제거 — 킥오프 §2.2.
            // RunSession은 @Observable이라 state 변화가 body를 다시 평가한다.
            if !AppTab.isTabBarHidden(runState: container.runSession.state) {
                TraceTabBar(selection: $selectedTab)
            }
        }
        // 카운트다운(아직 idle)이 끝나 트래킹이 실제로 시작되는 순간, 사용자가 다른 탭에
        // 가 있었다면 탭바가 사라지기 전에 러닝 탭으로 데려온다 — 킥오프 §2.2의 "러닝 중
        // 탭 전환 진입점 제거"는 항상 러닝 화면을 보고 있다는 전제인데, 카운트다운 중(아직
        // idle이라 탭 전환 가능)에 다른 탭으로 이동해뒀다가 트래킹이 시작되면 탭바 없이
        // 그 탭에 갇히는 문제가 실기기 QA에서 발견됐다(2026-07-20).
        .onChange(of: container.runSession.state) { _, newState in
            if AppTab.isTabBarHidden(runState: newState) {
                selectedTab = .run
            }
        }
    }
```

- [ ] **Step 2: 빌드 + 세로 회귀 확인**

`build_run_sim` 성공 후, 세로 상태에서 `snapshot_ui`:
- `root.tabBar` 프레임 = y 784..840 (known-good과 동일)
- 지도 두 번 탭으로 경로 생성 → 헤더 탭으로 medium → 탭바 그대로 784..840, 시트 정상

Expected: 세로에서 시각적/프레임 변화 전혀 없음 (배정량 == 콘텐츠 크기일 땐 alignment 무의미).

- [ ] **Step 3: 가로에서 탭바 보호 확인**

osascript로 가로 회전 → collapsed에서 `snapshot_ui`: `root.tabBar` y+height ≤ 402 확인 → 헤더 탭으로 medium → 다시 `snapshot_ui`: **`root.tabBar` y+height ≤ 402 (수정 전엔 412까지 뚫렸다)**.

Expected: 탭바 온스크린. **주의:** 이 시점엔 시트 아래쪽이 탭바 뒤로 가라앉아 보일 수 있다(내부 오버플로가 아직 남아 있으면 .top 정렬이 아래로 흘려보냄) — 이는 Task 2·3이 마저 고친다. Task 1의 통과 기준은 오직 "탭바 온스크린 + 세로 회귀 0"이다.

- [ ] **Step 4: 세로 복귀 확인**

osascript로 세로 복귀 → `snapshot_ui`: `root.tabBar` 784..840 재확인.

- [ ] **Step 5: Commit**

```bash
git add Trace/App/RootView.swift
git commit -m "fix: 가로모드 시트 펼침 시 탭바가 화면 밖으로 밀리던 구조적 오버플로 차단"
```

---

### Task 2: 시트 예산 클램프 — 시트가 배정 높이를 절대 못 넘게

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift`

**Interfaces:**
- Consumes: Task 1의 구조 보장(배정량 고정 제안)
- Produces: `CoursePlannerPage`에 `@State var pageHeight: CGFloat`(BottomSheetComponent 확장이 읽으므로 internal). `maxSheetHeight`가 `min(mapHeight - topSafeAreaInset, pageHeight) - sheetTopMargin`으로 변경. `budgetListHeight` private 파생값 신설.

**핵심 원리:** `mapHeight`는 `ignoresSafeArea()` 확장을 포함해 배정량보다 크게 측정되고(세로 +62), 가로에서는 원인 미확정 팽창(335→396)까지 실측됐다 — 예산 앵커로 부적합하다. `Color.clear`는 ZStack 안에서 형제 크기와 무관하게 **항상 제안 크기(=배정 높이)를 그대로 보고**하므로 안정적인 앵커다. 수식 등가성(세로 회귀 0의 근거): 세로에서 `min(784-62, 722) - 11 = 711` — 기존 `784-62-11 = 711`과 동일. 가로(stale ratchet)에서도 `min(396-62, 335) - 11 = 323` — 기존 323과 동일해 Task 2 단독으로는 동작 변화가 없고, Task 3이 ratchet을 고친 뒤에도 `min(팽창값-0, 335) - 11 = 324`로 **어떤 mapHeight 팽창에도 예산이 335를 넘을 수 없게 된다.**

- [ ] **Step 1: pageHeight 측정 추가 (CoursePlannerPage.swift)**

상태 선언부(33행 `@State var topSafeAreaInset: CGFloat = 0` 근처)에 추가:

```swift
    @State var pageHeight: CGFloat = 750
```

`body`의 `ZStack(alignment: .bottom) {` 첫 자식(mapView 위)에 추가:

```swift
            // 페이지가 실제로 배정받은 높이(제안 크기)의 안정 앵커 — mapView 측정값(mapHeight)은
            // ignoresSafeArea 확장을 포함해 배정량보다 클 수 있고(세로 +62), 가로에서는 원인
            // 미확정 팽창(335→396)이 실측됐다(2026-07-20). Color.clear는 형제 크기와 무관하게
            // 항상 제안 크기를 그대로 보고하므로 시트 예산(maxSheetHeight)의 min-클램프 기준이 된다.
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    pageHeight = height
                }
```

- [ ] **Step 2: 예산 수식 교체 (CoursePlannerPage+BottomSheetComponent.swift)**

`maxSheetHeight`(265-267행)를 교체 — 기존 주석은 유지하고 계산식과 설명만 갱신:

```swift
    // 풀 시트가 다이내믹 아일랜드/상태 바 바로 아래에서 멈추도록 하는 상한 — 시스템 시트의
    // large detent와 같은 발상. expandedListHeight의 리스트 높이 계산에만 쓴다.
    //
    // 한 번은 이 값을 bottomSheet 자체에도 .frame(maxHeight:, alignment: .top)으로 강제해
    // 오버슈트를 물리적으로 막으려 했으나, ZStack이 자식에게 화면 전체 높이를 제안하는 상황에서
    // maxHeight만 있고 exact height가 없는 프레임은 제안받은 크기(여기선 화면 높이)까지 그대로
    // 차지해버려 시트 전체가 화면 위쪽 절반을 덮는 보이지 않는 히트테스트 영역이 되었다 — collapsed/
    // medium 단계에서 지도 탭이 그 영역에 흡수되어 경로 생성 자체가 안 되는 회귀였다(2026-07-12,
    // XCUITest 접근성 트리 덤프로 확인 후 되돌림). 오버슈트 방어는 다시 시도하더라도 bottomSheet
    // 전체가 아니라 expandedSheetBody의 리스트 높이 안쪽에서만 해야 한다.
    //
    // pageHeight로 min-클램프: mapHeight는 ignoresSafeArea 확장/가로 팽창 때문에 배정량을
    // 초과할 수 있어(2026-07-20 실측 335→396) 단독으로는 예산 앵커로 부적합하다. 세로에서는
    // min(784-62, 722)=722로 기존 수식과 완전 동치(회귀 없음), 가로에서는 어떤 팽창에도
    // 예산이 배정 높이를 못 넘는다.
    private var maxSheetHeight: CGFloat {
        min(mapHeight - topSafeAreaInset, pageHeight) - sheetTopMargin
    }
```

`expandedListHeight`(274-285행)를 교체 — medium에도 예산 상한을 걸고, full은 예산을 그대로 쓴다:

```swift
    // 예산 안에서의 리스트 높이 상한 — full은 이 값을 그대로 쓰고, medium은 이 값을 넘지
    // 않는 범위에서 지도 높이 40%를 쓴다. 어느 단계도 예산(maxSheetHeight)을 넘을 수 없다.
    // max(0, ...)은 초기 측정 전 기본값 조합에서 음수 프레임 경고를 막는 가드.
    private var budgetListHeight: CGFloat {
        max(0, maxSheetHeight - grabberTotalHeight - sheetHeaderHeight)
    }

    // presentationDetents처럼 단계별 고정 높이 — 콘텐츠 양은 높이에 전혀 영향을 주지 않는다.
    // 구간이 적으면 그냥 빈 공간이 남고, 많으면 스크롤된다. 이전엔 min(실측 콘텐츠 높이, 상한)으로
    // 짜여 있어 구간이 늘어날 때마다 시트가 실측 높이만큼 점점 커지는 문제가 있었다(2026-07-12,
    // 사용자 확인 — "추가할 때마다 늘어나면 안 된다"). collapsed는 expandedSheetBody 자체가
    // 렌더되지 않아 이 값이 쓰이지 않는다.
    private var expandedListHeight: CGFloat {
        switch sheetDetent {
        case .collapsed: return 0
        case .medium: return min(panelMaxListHeight, budgetListHeight)
        case .full: return budgetListHeight
        }
    }
```

수식 등가성 확인(구현자 스스로 검산할 것): 세로 full 기존 `max(313, 711-25-97=589) = 589` ↔ 신규 `budgetListHeight = 711-122 = 589` 동일. 세로 medium 기존 `313` ↔ 신규 `min(313, 589) = 313` 동일.

- [ ] **Step 3: 빌드 + 세로 회귀 확인**

`build_run_sim` → 세로에서 경로 생성 → medium 헤더 탭 → `snapshot_ui`로 `coursePlanner.segmentPanel` 프레임이 Task 1 종료 시점과 동일한지 확인(리스트 높이 313 기준). 탭바 784..840.

- [ ] **Step 4: 가로에서 시트 격리 확인**

가로 회전 → 헤더 탭 medium → `snapshot_ui`: `coursePlanner.segmentPanel.grabber` top y ≥ 0, 패널 bottom이 `root.tabBar` top(=course 영역 bottom)과 일치하고 탭바 온스크린 유지. 세로 복귀 후 재확인.

- [ ] **Step 5: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift
git commit -m "fix: 바텀시트 높이 예산을 페이지 배정 높이로 클램프해 가로 시트 위 뚫림 차단"
```

---

### Task 3: topSafeAreaInset ratchet을 size class별로 분리 (TDD)

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/SafeAreaInsetLatch.swift`
- Create: `TraceTests/SafeAreaInsetLatchTests.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: Task 2까지의 예산 클램프(이게 있어야 이 수정이 안전하다 — Global Constraint 3)
- Produces: `struct SafeAreaInsetLatch` — `mutating func update(_ newValue: CGFloat, isVerticallyCompact: Bool)`, `func value(isVerticallyCompact: Bool) -> CGFloat`. `CoursePlannerPage.topSafeAreaInset`은 `@State` 저장 프로퍼티에서 **computed var**(internal, BottomSheetComponent가 기존 이름 그대로 읽음)로 바뀐다.

**핵심 원리:** 기존 ratchet(작아지는 값 무시)은 피드백 루프를 끊는 올바른 장치지만 "이 화면은 회전이 없다"는 전제가 가로 지원으로 깨졌다. 전제를 버리는 대신 **ratchet을 세로/가로 각각 독립으로** 유지한다 — 각 orientation의 진짜 안전영역은 여전히 고정값이므로 키 안에서는 ratchet이 계속 유효하고, 회전 타이밍에 environment와 geometry 콜백 순서가 어긋나 값이 잘못된 키에 latch되는 최악의 경우에도 "시트가 짧아지는"(뚫림이 아닌) 방향으로만 실패한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SafeAreaInsetLatchTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class SafeAreaInsetLatchTests: XCTestCase {
    func test_같은_사이즈클래스에서는_큰_값만_래치되고_작아지는_값은_무시된다() {
        var latch = SafeAreaInsetLatch()
        latch.update(62, isVerticallyCompact: false)
        latch.update(40, isVerticallyCompact: false) // 피드백 루프가 만드는 축소 보고 — 무시돼야 함
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 62)
        latch.update(66, isVerticallyCompact: false)
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 66)
    }

    func test_사이즈클래스가_다르면_서로_다른_값을_독립적으로_유지한다() {
        var latch = SafeAreaInsetLatch()
        latch.update(62, isVerticallyCompact: false) // 세로에서 62 latch
        latch.update(0, isVerticallyCompact: true)   // 가로의 진짜 값 0
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 62) // 세로 값 유지
        XCTAssertEqual(latch.value(isVerticallyCompact: true), 0)   // 가로는 0 (기존 단일 ratchet은 여기서 62를 반환하는 게 버그였다)
    }

    func test_측정_전_기본값은_0이다() {
        let latch = SafeAreaInsetLatch()
        XCTAssertEqual(latch.value(isVerticallyCompact: false), 0)
        XCTAssertEqual(latch.value(isVerticallyCompact: true), 0)
    }
}
```

- [ ] **Step 2: 테스트가 컴파일 실패(타입 없음)로 실패하는 것 확인**

XcodeBuildMCP `test_sim` 실행. Expected: `SafeAreaInsetLatch` 미정의로 빌드 실패.

- [ ] **Step 3: 구현**

`Trace/Pages/CoursePlannerPage/SafeAreaInsetLatch.swift` 생성:

```swift
import CoreGraphics

/// topSafeAreaInset ratchet(한 번 잡은 값보다 작은 값 무시 — 시트가 커질수록 시스템이 top
/// safe area를 더 작게 보고하는 피드백 루프 차단, docs/solutions/ui-bugs/
/// safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md)을 세로/가로 size class별로
/// 분리해 유지한다. 단일 ratchet은 "이 화면은 회전이 없다"는 전제 위의 장치였는데 가로 지원으로
/// 전제가 깨져, 세로 값(62)이 가로(진짜 0)에도 눌러앉는 stale 문제가 실측됐다(2026-07-20,
/// .git/sdd/task-landscape-layout-report.md). 각 키 안에서는 여전히 단조 증가만 허용하므로
/// 피드백 루프 차단은 그대로 유효하고, 회전 타이밍에 값이 잘못된 키에 latch되는 최악의
/// 경우에도 "시트가 짧아지는"(위로 뚫리는 게 아닌) 안전한 방향으로만 실패한다.
struct SafeAreaInsetLatch {
    private var values: [Bool: CGFloat] = [:]

    mutating func update(_ newValue: CGFloat, isVerticallyCompact: Bool) {
        if newValue > values[isVerticallyCompact, default: 0] {
            values[isVerticallyCompact] = newValue
        }
    }

    func value(isVerticallyCompact: Bool) -> CGFloat {
        values[isVerticallyCompact, default: 0]
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

`test_sim` 실행. Expected: 신규 3개 포함 전체 green.

- [ ] **Step 5: CoursePlannerPage 연결**

`Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`에서:

(1) 33행 `@State var topSafeAreaInset: CGFloat = 0`을 다음으로 교체:

```swift
    @State private var safeAreaLatch = SafeAreaInsetLatch()
    // BottomSheetComponent 확장(별도 파일)이 기존 이름 그대로 읽는다 — private 금지.
    var topSafeAreaInset: CGFloat {
        safeAreaLatch.value(isVerticallyCompact: verticalSizeClass == .compact)
    }
```

(2) `@Environment(\.scenePhase) private var scenePhase` 근처에 추가:

```swift
    @Environment(\.verticalSizeClass) private var verticalSizeClass
```

(3) 97-106행의 onGeometryChange 블록(주석 포함)을 다음으로 교체:

```swift
        // 시트가 커질수록 이 값 자체가 시스템에 의해 더 작게 보고되는 피드백 루프가 있었다
        // (2026-07-12, XCUITest로 실측: medium 62pt → full 40pt). 한 번 잡은 값보다 작은 값은
        // 무시(ratchet)해 루프를 끊되, 가로 지원(2026-07-19) 이후로는 세로/가로의 진짜 안전영역이
        // 다르므로(세로 62 / 가로 0) size class별로 독립 latch한다 — 단일 ratchet은 가로에서
        // 세로 값이 눌러앉아 가로 full 시트가 62pt 짧아지는 stale 문제가 있었다(2026-07-20 실측).
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { newValue in
            safeAreaLatch.update(newValue, isVerticallyCompact: verticalSizeClass == .compact)
        }
```

- [ ] **Step 6: 빌드 + 전체 테스트 + 시뮬레이터 확인**

`test_sim` 전체 green 확인 후 `build_run_sim`:
- 세로: known-good 값 유지(시트 full은 Task 4에서 확인, 여기선 collapsed/medium + 탭바 784..840)
- 가로 medium: 시트·탭바 격리 유지 + 세로 복귀 후 재확인 (가로 full의 "예산 전부 사용"은 Task 4에서 detent 강제로 확인)

- [ ] **Step 7: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/SafeAreaInsetLatch.swift TraceTests/SafeAreaInsetLatchTests.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "fix: topSafeAreaInset ratchet을 size class별 latch로 분리해 가로 stale 값 제거"
```

---

### Task 4: 통합 검증(6조합) + 문서 갱신

**Files:**
- Modify: `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`
- Modify: `docs/backlog.md`
- Create: `docs/qa/2026-07-20-landscape-sheet-device-checklist.md`
- (일시 수정 후 원복: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`의 `sheetDetent` 초기값)

**Interfaces:**
- Consumes: Task 1~3 완료 상태
- Produces: 세로/가로 × collapsed/medium/full 6조합 실측 결과 기록, 갱신된 교훈 문서, done 처리된 backlog 항목, 실기기 QA 체크리스트

- [ ] **Step 1: full 디텐트 임시 강제**

`CoursePlannerPage.swift`의 `@State var sheetDetent: SheetDetent = .collapsed`를 `.full`로 임시 변경 후 `build_run_sim`. (시뮬레이터가 드래그를 못 만들어 full은 이 방법뿐 — 검증 후 Step 3에서 반드시 원복.)

- [ ] **Step 2: 6조합 실측**

경로를 하나 생성한 뒤(지도 두 번 탭) 아래 표를 전부 채운다. medium/collapsed는 헤더 탭 토글, 회전은 osascript, 측정은 `snapshot_ui`:

| # | 조합 | 통과 기준 |
|---|---|---|
| 1 | 세로 collapsed | 탭바 784..840 |
| 2 | 세로 medium | 탭바 784..840, 시트 온스크린 |
| 3 | 세로 full | 탭바 784..840, **시트 top ≈ 73**(known-good, 상태바 62 아래) |
| 4 | 가로 collapsed | 탭바 y+h ≤ 402 |
| 5 | 가로 medium | 탭바 y+h ≤ 402, 그래버 top ≥ 0 |
| 6 | 가로 full | 탭바 y+h ≤ 402, **시트 top ≈ 11**(= 배정 335 − 예산 324, 0 이상이면서 42(구 stale 값)보다 작아야 ratchet 분리가 실제로 동작한 것) |

추가: 세로→가로→세로 회전 왕복을 3회 반복한 뒤 조합 1·3을 재확인(잘못된 키 latch로 인한 오염 없는지 — SafeAreaInsetLatch의 environment 캡처 타이밍 리스크 검증). 각 조합 스크린샷을 찍어 두되 가로는 `sips -r -90`로 돌려 확인.

- [ ] **Step 3: 임시 강제 원복 + 최종 테스트**

`sheetDetent` 초기값을 `.collapsed`로 원복 → `git diff`로 잔여 변경이 없음을 확인 → `test_sim` 전체 green 확인(테스트 수 기록).

- [ ] **Step 4: 교훈 문서 갱신**

`docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`의 Solution 섹션 끝(54행 "수정 후 실측: ..." 문단 뒤)에 추가:

```markdown
### 2026-07-20 갱신: "회전이 없다" 전제가 깨진 뒤의 형태

가로모드 지원(MVP16 tab-restructure)으로 "이 화면은 기기 회전이 없다"는 전제가 깨졌다 —
세로에서 latch된 62pt가 가로(진짜 top inset 0)에서도 유지되는 stale 문제가 실측됐다
(`.git/sdd/task-landscape-layout-report.md`). 단, 이 stale 값은 가로에서 시트를 *짧게* 누르는
보호막이기도 해서, **ratchet만 단독으로 고치면 가로 full에서 시트가 실제로 화면 위로 뚫린다**
(실측: 시트 top y=-56). 수정은 반드시 ① RootView 구조 클램프(GeometryReader) ② 시트 예산
min-클램프(pageHeight) ③ ratchet의 size class별 분리(`SafeAreaInsetLatch`) 순서로 진행해야
한다. 상세: `docs/superpowers/plans/2026-07-20-landscape-sheet-overflow.md`.
```

- [ ] **Step 5: backlog 항목 done 처리**

`docs/backlog.md`의 "MVP16 tab-restructure (2026-07-19) 풀시트-topBar 완전 밀착 보류" 섹션에서 **가로모드 레이아웃 붕괴 항목**(세 번째)의 끝 `` `planned` ``를 다음으로 교체:

```
*resolved(구현 완료일):* 3중 방어로 수정 — ① RootView GeometryReader 구조 클램프 ② 시트 예산 pageHeight min-클램프 ③ SafeAreaInsetLatch(size class별 ratchet). 6조합 실측 통과. 플랜: `docs/superpowers/plans/2026-07-20-landscape-sheet-overflow.md`. `done`
```

(구현 완료일은 실제 날짜로 기입.)

- [ ] **Step 6: 실기기 QA 체크리스트 작성**

`docs/qa/2026-07-20-landscape-sheet-device-checklist.md` 생성:

```markdown
# 가로모드 시트 레이아웃 실기기 체크리스트 (2026-07-20)

## 빌드/설치
- [ ] 기기 연결, Xcode Run 성공

## 한 세션으로 이어서 확인 (코스 탭, 경로 하나 그린 상태에서 시작)

### 시나리오 1: 가로에서 시트 3단계 — 붕괴가 사라졌는지
**수행:**
1. 기기를 가로로 돌린다
2. 시트 헤더를 탭해 중간 높이로 올린다
3. 그래버를 위로 드래그해 최대 높이까지 올린다
4. 다시 아래로 드래그해 접는다

**확인할 것:** 어느 단계에서도 하단 탭바가 화면 밖으로 밀려나지 않는지, 시트가 화면 위 경계를 뚫고 올라가지 않는지, 시트를 최대로 올렸을 때 위쪽에 아주 약간의 여백만 남기고 멈추는지 (이전 버그: 탭바가 아래로 사라지고 시트가 위로 뚫렸음)

**결과:** ☐ 통과 ☐ 실패
**메모:**

### 시나리오 2: 회전을 오가도 세로가 멀쩡한지
**수행:**
1. 가로에서 시트를 최대로 올린 채 세로로 돌린다
2. 시트를 접었다 펼쳤다 해본다
3. 가로↔세로를 세 번 더 오간다

**확인할 것:** 세로로 돌아올 때마다 시트 최대 높이가 예전과 똑같은지(화면 맨 위 시간 표시를 가리지 않고 그 바로 아래에서 멈춤), 탭바가 항상 제자리인지

**결과:** ☐ 통과 ☐ 실패
**메모:**

### 시나리오 3: 다이내믹 아일랜드 침범 회귀 확인 (과거 버그 자리)
**수행:**
1. 세로에서 시트를 최대 높이로 올린다
2. 구간을 여러 개 추가하며 시트 상단 가장자리를 관찰한다

**확인할 것:** 시트 상단이 상태바/다이내믹 아일랜드를 덮지 않는지 (이 자리의 과거 버그 — 이번 수정으로 재발하면 안 됨)

**결과:** ☐ 통과 ☐ 실패
**메모:**

### 시나리오 4: 가로에서 일반 조작 회귀 확인
**수행:**
1. 가로 상태에서 지도 탭으로 경로를 추가한다
2. 시트 medium에서 구간 리스트를 스크롤하고 구간을 선택한다
3. 저장 버튼을 눌러 저장 알럿까지 띄워본다(저장은 취소해도 됨)

**확인할 것:** 지도 탭·리스트 스크롤·버튼이 전부 정상 반응하는지 (예산 클램프가 히트테스트를 깨뜨리지 않았는지 — 과거 이 자리에서 maxHeight 방어가 지도 탭을 전부 삼킨 회귀가 있었음)

**결과:** ☐ 통과 ☐ 실패
**메모:**
```

- [ ] **Step 7: Commit**

```bash
git add docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md docs/backlog.md docs/qa/2026-07-20-landscape-sheet-device-checklist.md
git commit -m "docs: 가로모드 시트 붕괴 수정 — 교훈 문서 갱신 + backlog done + 실기기 체크리스트"
```

---

## 완료 후

1. `superpowers:requesting-code-review`로 브랜치 리뷰(경량 사이클 — 태스크별 리뷰를 통과했으면 최종 브랜치 리뷰는 생략 가능, 열린 결정이 없는 버그픽스임).
2. `superpowers:finishing-a-development-branch` — main에 rebase + `--ff-only` 통합, 브랜치 즉시 삭제. **push는 사용자가 직접.**
3. 사용자에게 실기기 QA(`docs/qa/2026-07-20-landscape-sheet-device-checklist.md`) 안내.
4. 새로 얻은 교훈이 있으면 `ce-compound`.

## 명시적으로 하지 않는 것 (YAGNI)

- "panelMaxListHeight를 mapHeight에서 분리" — 조사 리포트가 보류 판정(1차 트리거라는 실측 근거 없음). 예산 클램프(Task 2)가 결과를 이미 막는다.
- 가로 전용 레이아웃 최적화(시트 폭 제한, 사이드 배치 등) — 별도 UX 결정 필요, 이번 범위는 "붕괴 제거"만.
- 풀시트 topBar 3pt 틈(별도 backlog 항목) — 이번 수정과 무관, 건드리지 않는다.

---

## 세션 마무리 메모 (2026-07-20, 실행 후 기록)

Task 1~3(구조 클램프·예산 클램프·ratchet 분리)은 실기기로 검증 완료 — 가로+경로 있음 상태의 시트 붕괴, 가로 collapsed→medium 전환 시 탭바 밀림 모두 사라진 것을 사용자가 실기기에서 확인했다.

그런데 이 수정 자체가 새 회귀를 냈고(탭바 옆 검은 여백, 세로 풀시트 topBar 미커버), 그걸 잡으러 들어가면서 위 YAGNI가 명시적으로 범위 밖이라 못박아둔 "가로 전용 레이아웃 최적화(시트를 화면 끝까지 늘리기)" 쪽으로 실제로 들어가 버렸다. 이번 세션에서 시도한 것:

- `bottomSheet`를 ZStack 형제에서 `.overlay(alignment: .bottom)`로 분리 — mapView/크롬 VStack의 내부 크기 팽창이 시트 정렬 기준을 더 이상 오염시키지 않는다.
- `CoursePlannerPage` 루트에 `.ignoresSafeArea(edges: .horizontal)` 추가 — 가로에서 좌우 세이프에어리어 제약을 걷어내 지도/시트/탭바가 화면 끝까지 가도록 시도.
- 크롬 VStack에 `.frame(height: pageHeight, alignment: .top)` — 가로 collapsed→medium 전환 시 topBar가 위로 밀리는 것 방지(실기기 확인 완료).

시뮬레이터 픽셀 샘플링으로는 좌우 검은 여백이 사라진 것처럼 보였으나, **실기기 재확인 결과 검은 여백과 풀시트 topBar 미커버 둘 다 여전히 재현됨.** 게다가 사용자가 "시트를 가로에서 화면 끝까지 늘리는" 접근 자체에 의문을 제기함 — 다이내믹 아일랜드 겹침, FAB(플로팅 버튼) 배치를 이 방향에서 어떻게 처리할지 등 새 UX 질문이 이 방식에서 파생되기 때문. 즉 원래 이 플랜의 YAGNI 경계("가로 전용 레이아웃 최적화는 범위 밖")가 맞았던 것으로 보인다.

**결론:** 여기서부터는 패치가 아니라 시트/탭바 구조 자체를 다시 설계할지 결정하는 문제 — 다음 세션(다른 모델과의 브레인스토밍 가능)에서 다시 다룬다. 상세는 `docs/backlog.md`("가로모드에서 코스 탭 시트를 펼치면..." 항목, `in-progress`)와 `docs/qa/2026-07-20-landscape-sheet-device-checklist.md`(시나리오 5·6)에 기록.

**브랜치 상태:** ~~`feature/mvp16-landscape-sheet-overflow`, 병합하지 않고 유지~~ → **정정(2026-07-21):** 실제로는 이후 `main`에 병합됐고 브랜치는 삭제됐다(문서 맨 위 소급 노트 참고). 이 문단이 오래 stale로 남아 다음 세션이 "미병합 브랜치가 어딘가 있다"고 오인할 뻔했다.
