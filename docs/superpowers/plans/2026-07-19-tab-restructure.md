# MVP16 tab-restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 시스템 TabView를 루트 커스텀 탭바로 교체하고(러닝 플로우 중 숨김), 코스 탭의 커스텀 시트·플로팅 버튼을 새 탭바와 연동한다.

**Architecture:** 루트는 `VStack { ZStack(두 페이지, opacity 전환) ; TraceTabBar }` — 페이지를 switch로 갈아끼우면 `@State` ViewModel이 파괴되므로 ZStack+opacity로 두 페이지를 살려둔다. 탭바 숨김은 앱 레벨 `RunSession.state`(idle 외 전부 숨김 = 요약 화면 포함)로 판정한다. 플로팅 버튼은 순수 정책 타입(`FabLayoutPolicy`)으로 분리해 디텐트별 위치·투명도·노출을 계산한다.

**Tech Stack:** SwiftUI (iOS 17+), Swift 6, XCTest. 외부 의존성 추가 없음.

**Specs:** `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md`(§1–2) + `2026-07-19-mvp16-ui-direction-design.md`(§1–2) + 참고 캡처 `docs/refs/naver-map-sheet-*.png`

## Global Constraints

- Swift 6 언어 모드, 격리 기본값은 클래식(기본 nonisolated) + UI 타입에 명시 `@MainActor` (`project-decisions.md`)
- 코스 탭에 시스템 `.sheet` 사용 금지 — 기존 커스텀 시트(`SheetDetent`) 유지 (킥오프 §2.4). 단 기존 `courseListSheet`·`RunHistorySheet` 등 모달 시트는 이 사이클 범위 밖 — 건드리지 않는다
- 색·폰트는 `DesignToken`만 사용 (직접 Color/Font 리터럴 금지)
- ViewModel은 MapKit을 import하지 않는다 (아키텍처 규칙)
- 탭 전환 트랜지션 없음(즉시 전환) — ui-direction §1
- 검증 명령 (모든 태스크 공통, 시뮬레이터는 iPhone 17 Pro / iOS 26.5 = `D887D0A4-074C-4AFB-8D08-D87329D0EFD4` 고정, 세션당 하나만):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build`
  - 테스트: 같은 명령에 `-parallel-testing-enabled NO test` (병렬 금지 필수)
  - 린트: `swiftlint`
  - 각각 통과 후 `touch .git/trace-verify-build.ok` / `trace-verify-test.ok` / `trace-verify-lint.ok` (pre-commit 훅 요건)
- 커밋: `scripts/trace-commit.sh -m "<tag>: 한국어 제목\n\n- 본문 3~4줄" -- <paths>` — 경로 명시 스테이징, `git add -A` 금지

---

### Task 1: AppTab + 탭바 숨김 정책 + TraceTabBar 컴포넌트

**Files:**
- Create: `Trace/App/AppTab.swift`
- Create: `Trace/DesignSystem/Component/TraceTabBar.swift`
- Test: `TraceTests/AppTabTests.swift`

**Interfaces:**
- Consumes: `RunSession.State` (기존 — `Trace/Application/RunTracking/RunSession.swift:17`, case idle/acquiring/tracking/paused/summary), `DesignToken.Color.{accent,ink2,surface}`, `DesignToken.Typography.chip`
- Produces: `enum AppTab: String, CaseIterable, Identifiable { case course, run }` — `title: String`, `systemImage: String`, `static func isTabBarHidden(runState: RunSession.State) -> Bool`; `struct TraceTabBar: View` — `init(selection: Binding<AppTab>)`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// TraceTests/AppTabTests.swift
import XCTest
@testable import Trace

final class AppTabTests: XCTestCase {
    func test_탭은_코스_러닝_순서로_두_개다() {
        XCTAssertEqual(AppTab.allCases, [.course, .run])
        XCTAssertEqual(AppTab.course.title, "코스")
        XCTAssertEqual(AppTab.run.title, "러닝")
        XCTAssertEqual(AppTab.course.systemImage, "map")
        XCTAssertEqual(AppTab.run.systemImage, "figure.run")
    }

    // 킥오프 §2.2: 러닝 시작~요약 화면을 닫을 때까지 탭바 숨김 — idle에서만 보인다.
    func test_탭바는_idle에서만_보인다() {
        XCTAssertFalse(AppTab.isTabBarHidden(runState: .idle))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .acquiring))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .tracking))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .paused))
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .summary))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: 위 Global Constraints의 테스트 명령에 `-only-testing:TraceTests/AppTabTests` 추가
Expected: FAIL — `cannot find 'AppTab' in scope` (컴파일 실패도 실패로 간주)

- [ ] **Step 3: AppTab 구현**

```swift
// Trace/App/AppTab.swift
import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case course
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course: return "코스"
        case .run: return "러닝"
        }
    }

    var systemImage: String {
        switch self {
        case .course: return "map"
        case .run: return "figure.run"
        }
    }

    // 킥오프 §2.2: 러닝 플로우(시작~요약 닫기 전) 동안 앱 내 탭 전환 진입점 자체를 제거한다.
    // summary도 숨김 — 요약 화면을 닫아 idle로 돌아와야 탭바가 복귀한다.
    static func isTabBarHidden(runState: RunSession.State) -> Bool {
        runState != .idle
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Step 2와 동일
Expected: PASS (2 tests)

- [ ] **Step 5: TraceTabBar 뷰 구현**

```swift
// Trace/DesignSystem/Component/TraceTabBar.swift
import SwiftUI

// 루트 커스텀 탭바 — 시스템 탭바는 iOS 26에서 글래스로 렌더되어 불투명 클래식 모양이
// 안 나오므로 직접 만든다 (킥오프 §2.4). 풀폭 불투명 + 아이콘·한글 라벨 (ui-direction §1).
struct TraceTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab // 트랜지션 없음(즉시 전환)이 확정 기본값 — ui-direction §1
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 22, weight: .medium))
                        Text(tab.title)
                            .font(DesignToken.Typography.chip)
                    }
                    .foregroundStyle(
                        selection == tab ? DesignToken.Color.accent : DesignToken.Color.ink2
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                .accessibilityIdentifier("root.tab.\(tab.rawValue)")
            }
        }
        .background {
            // 위쪽 헤어라인 + 불투명 Surface. 홈 인디케이터 영역까지 배경 확장 —
            // 커스텀 시트 배경(ignoresSafeArea bottom)과 같은 패턴.
            DesignToken.Color.surface
                .overlay(alignment: .top) {
                    DesignToken.Color.ink2.opacity(0.2)
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityIdentifier("root.tabBar")
    }
}
```

- [ ] **Step 6: 빌드 확인 (뷰는 단위 테스트 없음 — 로직이 없다)**

Run: Global Constraints의 빌드 명령
Expected: BUILD SUCCEEDED

- [ ] **Step 7: 커밋**

```bash
# 빌드/테스트/린트 3종 통과 후 스탬프 갱신하고:
scripts/trace-commit.sh -m "feat: AppTab·TraceTabBar 컴포넌트 추가

- 커스텀 탭바(풀폭 불투명, 아이콘+한글 라벨, 민트 선택 표시) 컴포넌트 신설
- 탭바 숨김 정책(idle 외 러닝 플로우 전체 숨김, 요약 포함)을 AppTab에 순수 함수로 분리
- 아직 루트에 연결 안 함 — 다음 태스크에서 TabView 교체" -- Trace/App/AppTab.swift Trace/DesignSystem/Component/TraceTabBar.swift TraceTests/AppTabTests.swift
```

---

### Task 2: 루트 교체 — TabView → RootView (페이지 상태 보존 + 탭바 숨김)

**Files:**
- Create: `Trace/App/RootView.swift`
- Modify: `Trace/App/TraceApp.swift:33-54` (body의 TabView 블록 교체)

**Interfaces:**
- Consumes: Task 1의 `AppTab`, `TraceTabBar(selection:)`; `DependencyContainer`(기존 — `container.runSession.state` 관찰, `RunSession`은 `@Observable` 앱 레벨 단일 인스턴스)
- Produces: `struct RootView: View` — `init(container: DependencyContainer)`. 이후 태스크는 루트 구조를 전제로만 사용(직접 호출 없음)

- [ ] **Step 1: RootView 구현**

**핵심 제약: 페이지를 `switch`로 갈아끼우지 않는다.** `CoursePlannerPage`/`RunPage`는 `@State`로 ViewModel을 소유하므로 뷰가 파괴되면 작업 중 코스·화면 상태가 사라진다. ZStack + opacity로 둘 다 살려두고 보이는 쪽만 히트테스트를 허용한다(시스템 TabView의 상태 보존 동작 재현). 참고: `docs/refs/mvp16-tab-experiment/Test/Option1.swift`는 switch 방식이라 이 제약을 어긴다 — 모양만 참고할 것.

```swift
// Trace/App/RootView.swift
import SwiftUI

struct RootView: View {
    private let container: DependencyContainer
    @State private var selectedTab: AppTab = .course // 냉시작 기본 탭 = 코스 (ui-direction §1)

    init(container: DependencyContainer) {
        self.container = container
    }

    var body: some View {
        VStack(spacing: 0) {
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

            // 러닝 플로우(시작~요약 닫기 전) 동안 탭바 자체를 제거 — 킥오프 §2.2.
            // RunSession은 @Observable이라 state 변화가 body를 다시 평가한다.
            if !AppTab.isTabBarHidden(runState: container.runSession.state) {
                TraceTabBar(selection: $selectedTab)
            }
        }
    }
}
```

- [ ] **Step 2: TraceApp body 교체**

`Trace/App/TraceApp.swift`의 `WindowGroup` 내용(35-52행: `TabView { ... }.tint(...)`)을 다음으로 교체. `.badge("●")`는 이식하지 않는다 — 트래킹 중 탭 전환이 사라져 죽은 기능(ui-direction §1).

```swift
        WindowGroup {
            RootView(container: container)
                .tint(DesignToken.Color.accent)
        }
```

- [ ] **Step 3: 전체 테스트 실행**

Run: Global Constraints의 테스트 명령 (전체 스위트)
Expected: PASS — 기존 335개 + Task 1의 2개 전부 그린. UI 테스트가 시스템 탭바를 참조하지 않음은 확인됨(2026-07-19, TraceUITests는 템플릿 수준)

- [ ] **Step 4: 시뮬레이터 스모크 확인**

XcodeBuildMCP로: `build_run_sim` → `screenshot`(코스 탭 + 탭바 보임) → `tap`(root.tab.run) → `screenshot`(러닝 탭 전환) → `tap`(root.tab.course) → 코스 탭에 **작업 중이던 상태가 유지되는지**(탭 전환으로 ViewModel이 파괴되지 않는지) 확인. 러닝 시작→탭바 사라짐→종료·요약 닫기→탭바 복귀는 GPS 필요라 실기기 QA(Task 5)로.
Expected: 두 탭 전환 정상, 탭바 렌더가 `docs/refs/` 캡처의 문법(불투명·아이콘+라벨·민트 선택)과 일치

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 루트를 시스템 TabView에서 커스텀 탭바로 교체

- RootView 신설: ZStack+opacity로 두 페이지 상태 보존(switch 교체 금지), VStack 하단에 TraceTabBar
- 러닝 플로우(idle 외) 동안 탭바 제거, 요약 화면 닫기 전까지 유지 — 킥오프 §2.2
- 시스템 탭 badge(●)는 죽은 기능이라 이식 안 함 — ui-direction §1" -- Trace/App/RootView.swift Trace/App/TraceApp.swift
```

---

### Task 3: 코스 탭 시트-탭바 정합 검증·보완 (detent 포함)

**Files:**
- Modify(필요시): `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift:32-36` (배경 `ignoresSafeArea`), `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift:65-106` (레이아웃 측정)

**Interfaces:**
- Consumes: Task 2의 루트 구조 (코스 페이지의 아래 경계가 이제 화면 하단이 아니라 탭바 상단)
- Produces: 시트가 탭바 위에 정확히 얹히는 검증된 레이아웃 (코드 변경은 검증 결과에 따라 0일 수 있음 — 그 경우 이 태스크는 확인 기록만 남긴다)

- [ ] **Step 1: 세 디텐트 렌더 검증**

XcodeBuildMCP로 코스 탭에서: 시트 collapsed 스크린샷 → 그래버 드래그(또는 헤더 탭)로 medium → 스크린샷 → 드래그로 full → 스크린샷. `docs/refs/naver-map-sheet-{collapsed,medium,full}.png`와 구조 비교.
확인 항목:
- 시트 하단이 탭바 상단에 정확히 붙는가 (틈·겹침 없음)
- collapsed에서 시트(그래버+헤더)와 탭바가 이중 바닥처럼 보이지 않는가
- full에서 시트 상단이 상태바를 침범하지 않는가 (기존 `maxSheetHeight` 로직: `mapHeight - topSafeAreaInset - sheetTopMargin`)
- 탭바가 세 디텐트 모두에서 항상 보이는가 (네이버 문법 — ui-direction §1)

- [ ] **Step 2: 어긋남이 있으면 보정**

예상 보정 지점 (검증 결과에 따라 해당 건만):
- 시트 배경의 `.ignoresSafeArea(edges: .bottom)`(BottomSheetComponent 34행)은 루트 VStack 안에서 하단 safe area가 탭바에 소비되므로 no-op이 된다 — 시트 아래 띠가 생기면 이 라인 제거가 아니라 탭바 쪽 배경(TraceTabBar가 이미 홈 인디케이터 영역을 채움)과의 경계를 확인한다.
- `mapHeight` 측정(CoursePlannerPage 219-224행)은 페이지 프레임 기준이라 탭바만큼 자동으로 줄어든다 — `panelMaxListHeight = height * 0.4` 비율은 그대로 유효(비율 기반 detent의 "검증" 항목, 킥오프 §3 정정 반영).
- full 디텐트 상한이 어긋나면 `sheetTopMargin`(40pt) 재확인 — 기존 ratchet-up 로직(`topSafeAreaInset`)은 건드리지 않는다 (`docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`).

- [ ] **Step 3: 전체 테스트 + 스크린샷 재확인**

Run: Global Constraints의 테스트 명령
Expected: PASS. 세 디텐트 스크린샷에서 Step 1 확인 항목 전부 충족

- [ ] **Step 4: 커밋** (코드 변경이 있을 때만 — 없으면 Task 4 커밋에 검증 노트만 포함)

```bash
scripts/trace-commit.sh -m "fix: 코스 탭 시트-탭바 경계 정합 보정

- 커스텀 시트가 루트 탭바 위에 정확히 얹히도록 <실제 보정 내용 기입>
- 세 디텐트(collapsed/medium/full) 시뮬레이터 렌더 검증 완료
- 비율 기반 detent(panelMaxListHeight = 지도 높이 0.4)는 탭바 도입 후에도 유효 확인" -- <변경 파일>
```

---

### Task 4: 플로팅 버튼 시트 연동 (노출 규칙 + 이동·페이드)

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/FabLayoutPolicy.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift:227-296` (fabStack·editingFabGroup)
- Test: `TraceTests/FabLayoutPolicyTests.swift`

**Interfaces:**
- Consumes: `SheetDetent`(기존 — CoursePlannerPage.swift:8), fabStack의 기존 측정값 `grabberTotalHeight`·`sheetHeaderHeight`·`panelMaxListHeight`
- Produces: `enum FabLayoutPolicy` — `static func opacity(for: SheetDetent) -> Double`, `static func showsEditingGroup(hasCourse: Bool, canUndo: Bool, canRedo: Bool) -> Bool`, `static func bottomPadding(detent: SheetDetent, collapsedSheetHeight: CGFloat, mediumListHeight: CGFloat) -> CGFloat`

**동작 변경 요약 (방향 스펙 §2 "플로팅 버튼"이 2026-07-13 결정을 대체):**
- 기존: collapsed에서만 4버튼 전부 노출, medium/full에서 전부 숨김
- 변경: ① 경로 없음 → 현위치만 (undo/redo/clear는 되돌릴 이력도 없을 때만 숨김 — clear 직후 undo 가능 상태를 위해 `canUndo||canRedo`도 노출 조건) ② 시트가 오르면 버튼도 시트 위로 같이 이동 ③ collapsed 1.0 → medium 0.55 → full 0 (페이드아웃, full에서 소멸·히트테스트 차단)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// TraceTests/FabLayoutPolicyTests.swift
import XCTest
@testable import Trace

final class FabLayoutPolicyTests: XCTestCase {
    func test_투명도는_디텐트가_오를수록_줄어_풀에서_사라진다() {
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .collapsed), 1.0)
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .medium), 0.55)
        XCTAssertEqual(FabLayoutPolicy.opacity(for: .full), 0.0)
    }

    // 방향 스펙 §2: 경로 없음 → 현위치만. 단 clear 직후처럼 경로는 없어도
    // 되돌릴 이력이 있으면 편집 그룹을 유지한다 (undo 가능성 보존).
    func test_편집그룹은_경로나_되돌릴_이력이_있을_때만_보인다() {
        XCTAssertFalse(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: false, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: true, canUndo: false, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: true, canRedo: false))
        XCTAssertTrue(FabLayoutPolicy.showsEditingGroup(hasCourse: false, canUndo: false, canRedo: true))
    }

    func test_버튼은_현재_시트_상단_위_16pt에_앵커된다() {
        // collapsed: 시트 = 그래버+헤더(예: 25+140)
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .collapsed, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 16
        )
        // medium: 시트 = collapsed + 리스트 높이
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .medium, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 300 + 16
        )
        // full: 숨김 상태(opacity 0) — 페이드 중 점프가 없도록 medium 위치를 유지한다
        XCTAssertEqual(
            FabLayoutPolicy.bottomPadding(detent: .full, collapsedSheetHeight: 165, mediumListHeight: 300),
            165 + 300 + 16
        )
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: 테스트 명령에 `-only-testing:TraceTests/FabLayoutPolicyTests`
Expected: FAIL — `cannot find 'FabLayoutPolicy' in scope`

- [ ] **Step 3: FabLayoutPolicy 구현**

```swift
// Trace/Pages/CoursePlannerPage/FabLayoutPolicy.swift
import Foundation

// 플로팅 버튼(undo/redo/clear/현위치)의 시트 연동 정책 — 방향 스펙 §2.
// 시트가 오르면 같이 오르고, 커질수록 페이드아웃, 풀 시트에서 소멸.
// (2026-07-13의 "collapsed 외 전부 숨김" 결정을 MVP16 방향 스펙이 대체한다.)
enum FabLayoutPolicy {
    static func opacity(for detent: SheetDetent) -> Double {
        switch detent {
        case .collapsed: return 1.0
        case .medium: return 0.55
        case .full: return 0.0
        }
    }

    static func showsEditingGroup(hasCourse: Bool, canUndo: Bool, canRedo: Bool) -> Bool {
        hasCourse || canUndo || canRedo
    }

    static func bottomPadding(
        detent: SheetDetent, collapsedSheetHeight: CGFloat, mediumListHeight: CGFloat
    ) -> CGFloat {
        switch detent {
        case .collapsed:
            return collapsedSheetHeight + 16
        case .medium, .full:
            // full은 opacity 0으로 숨김 — 페이드 아웃 중 위치 점프가 없도록 medium 앵커 유지
            return collapsedSheetHeight + mediumListHeight + 16
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Step 2와 동일
Expected: PASS (3 tests)

- [ ] **Step 5: fabStack에 정책 적용**

`CoursePlannerPage.swift`의 `fabStack`(227-253행)을 다음으로 교체 — 기존 긴 주석 블록은 정책 변경 경위를 한 줄로 압축해 대체한다. `editingFabGroup`·`recenterButton` 본문(255-296행)은 그대로 둔다.

```swift
    private var fabStack: some View {
        // 시트 연동 정책은 FabLayoutPolicy 참조 — 방향 스펙 §2가 기존 "collapsed 외 숨김"
        // (2026-07-13)을 대체: 시트 위로 이동 + 단계별 페이드 + 풀에서 소멸, 경로 없으면 현위치만.
        VStack(spacing: 12) {
            if FabLayoutPolicy.showsEditingGroup(
                hasCourse: viewModel.course != nil,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo
            ) {
                editingFabGroup
            }
            recenterButton
        }
        .frame(width: DesignToken.Size.fab)
        .padding(.trailing, DesignToken.Size.screenMargin)
        .padding(.bottom, FabLayoutPolicy.bottomPadding(
            detent: sheetDetent,
            collapsedSheetHeight: grabberTotalHeight + sheetHeaderHeight,
            mediumListHeight: panelMaxListHeight
        ))
        .opacity(FabLayoutPolicy.opacity(for: sheetDetent))
        .animation(.easeInOut(duration: 0.2), value: sheetDetent)
        .allowsHitTesting(sheetDetent != .full)
    }
```

- [ ] **Step 6: 전체 테스트 + 시뮬레이터 확인**

Run: 전체 테스트 명령 → PASS 확인 후, XcodeBuildMCP로 코스 탭에서:
- 경로 없음: 현위치 버튼만 보이는지
- 지도 탭 2회로 경로 생성: undo/redo/clear 등장하는지
- 시트 medium: 버튼들이 시트 위로 올라가고 반투명해지는지 · full: 사라지는지
Expected: 전부 충족 (0.55 값의 시인성은 실기기 QA에서 튜닝 여지 — Task 5 체크리스트에 포함)

- [ ] **Step 7: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 플로팅 버튼 시트 연동 — 이동·페이드·노출 규칙

- FabLayoutPolicy 신설: 디텐트별 투명도(1/0.55/0)·앵커 위치·편집그룹 노출 순수 정책
- 경로 없으면 현위치만, clear 직후 undo 이력 있으면 편집그룹 유지
- 시트가 오르면 버튼도 시트 상단 위 16pt로 이동, 풀 디텐트에서 소멸(히트테스트 차단)" -- Trace/Pages/CoursePlannerPage/FabLayoutPolicy.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift TraceTests/FabLayoutPolicyTests.swift
```

---

### Task 5: 최종 검증 + 실기기 QA 체크리스트

**Files:**
- Create: `docs/qa/2026-07-19-tab-restructure-device-checklist.md`

**Interfaces:**
- Consumes: Task 1–4의 전체 결과물
- Produces: 실기기 QA용 시나리오 카드 체크리스트 (형식은 `docs/agent-rules/testing.md`의 시나리오 카드 템플릿 — 평이한 언어, 세션 단위 묶음)

- [ ] **Step 1: 전체 검증 3종 실행**

Run: 빌드 → 전체 테스트(`-parallel-testing-enabled NO`) → `swiftlint`, 각 통과 후 스탬프 갱신
Expected: BUILD SUCCEEDED / TEST SUCCEEDED (335+5개) / lint 신규 위반 0

- [ ] **Step 2: QA 체크리스트 작성**

`docs/agent-rules/testing.md`의 시나리오 카드 형식으로 작성. 필수 시나리오:
1. **탭 전환 기본** — 코스↔러닝 왕복, 코스 작업 상태(그리던 경로·시트 디텐트) 유지 확인
2. **러닝 플로우 탭바 숨김** — 시작(카운트다운)→탭바 사라짐→트래킹→종료 홀드→요약 화면에도 탭바 없음→요약 닫기→대기 화면+탭바 복귀
3. **카운트다운 중 탭 전환 엣지** — 카운트다운 3초 동안 탭바가 아직 보인다(세션 idle) — 이때 코스 탭으로 전환 후 복귀 시 카운트다운·시작이 정상인지. 문제 발견 시 별도 수정 결정 (알려진 미세 엣지 — 세션 상태는 카운트다운 종료 후에야 바뀜)
4. **시트 3디텐트 + 탭바** — collapsed/medium/full 전환하며 시트가 항상 탭바 위에 정확히 얹히는지, 탭바 상시 노출(네이버 캡처와 비교)
5. **플로팅 버튼 연동** — 경로 없음(현위치만)/경로 생성(4버튼)/clear 직후(undo 이력 유지)/medium(이동+반투명, 버튼 동작함)/full(소멸) + 0.55 시인성 체감
6. **다크/라이트 모드** — 탭바·시트 경계가 두 테마 모두 자연스러운지
7. **회귀 확인** — 저장·불러오기 시트, 그리기 모드, 잠금화면 Live Activity(러닝 중)가 탭바 교체와 무관하게 정상인지

- [ ] **Step 3: 커밋**

```bash
scripts/trace-commit.sh -m "docs: tab-restructure 실기기 QA 체크리스트

- 탭 전환 상태 보존·러닝 플로우 탭바 숨김/복귀·시트 정합·플로팅 버튼 연동 7개 시나리오
- 카운트다운 중 탭 전환 엣지 케이스를 알려진 확인 항목으로 명시
- 시나리오 카드 형식(testing.md 템플릿)" -- docs/qa/2026-07-19-tab-restructure-device-checklist.md
```

---

## Self-Review 기록 (플랜 작성 시점)

1. **스펙 커버리지:** 킥오프 §2.1(2탭)·§2.2(숨김 규칙, Task 1·2)·§2.4(커스텀 크롬, Task 1–3) / ui-direction §1(탭바 형태·냉시작·badge 제거, Task 1·2)·§2(시트 3층 구조·플로팅 버튼·detent 검증, Task 3·4) — 전부 태스크에 매핑됨. 러닝 탭 지도 제거·기록 페이지는 run-fullscreen 마일스톤(범위 밖).
2. **플레이스홀더:** Task 3 Step 4의 "<실제 보정 내용 기입>"은 검증 결과 의존이라 의도된 빈칸 — 코드 변경이 없으면 커밋 자체가 생략된다.
3. **타입 일관성:** `AppTab.isTabBarHidden(runState:)`·`FabLayoutPolicy` 시그니처가 태스크 간 동일. `RunSession.State` 케이스명은 실제 코드(RunSession.swift:17-23)에서 검증함.
