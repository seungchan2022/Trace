# sheet-drag 구현 플랜 (MVP17 마일스톤 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**사이클 무게:** 경량 — 설계와 리뷰가 이미 끝났고(`2026-07-26-sheet-drag-design.md`, `ce-doc-review` 6인 반영 완료), 범위는 순수 타입 하나 추가와 기존 시트 뷰 한 곳 배선이다. 새 레이어·외부 의존성·열린 제품 결정이 없다. 최종 브랜치 리뷰는 생략하되 **태스크별 코드리뷰는 유지**한다 — Task 2 리뷰는 제스처 소유권과 히트테스트에 초점을 맞춘다(이 파일에서 실제로 났던 회귀 유형).

**Goal:** 코스 탭 바텀시트의 구간 리스트가 스크롤 끝에 붙어 있는 동안의 드래그를 시트로 넘겨, 리스트 위에서도 시트를 한 단계씩 접고 펼 수 있게 한다.

**Architecture:** `ScrollView`에 드래그 제스처를 동시 인식으로 얹어 스크롤 소유권을 뺏지 않는다. 리스트 콘텐츠의 스크롤 좌표계 프레임에서 오프셋과 콘텐츠 높이를 읽어 `(맨 위인가, 맨 아래인가)` 두 Bool만 상태로 올리고, 드래그가 진행되는 동안 그 값의 교집합을 취해 "내내 끝에 붙어 있었는가"를 판정한다. 이동 폭 계산은 새로 만들지 않고 그래버·헤더가 쓰는 40pt 문턱 + `steppedUp`/`steppedDown`을 그대로 재사용한다.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest

**설계:** [`2026-07-26-sheet-drag-design.md`](../specs/2026-07-26-sheet-drag-design.md)

## Global Constraints

- 최소 iOS 17.0, 아이폰 세로 전용. `onScrollGeometryChange`(iOS 18+)는 쓸 수 없다.
- MVVM + `@Observable` 유지. 순수 판정 타입에는 `@MainActor`를 붙이지 않는다.
- **한 번의 드래그는 아무리 길어도 한 단계만 움직인다.** 거리 비례(두 단계) 이동은 이번 범위 밖이다(2026-07-26 사용자 확정).
- **그래버·헤더 드래그의 동작을 바꾸지 않는다.** 40pt 문턱 판정을 공용 헬퍼로 뽑는 것은 허용하되(중복 방지), 동작은 그대로여야 한다.
- **헤더 탭은 기본↔중간만 오간다.** 풀은 드래그로만 도달한다(2026-07-12 사용자 확정).
- 스크롤 오프셋 같은 연속 값을 페이지 `@State`에 흘리지 않는다. 값이 실제로 뒤집힐 때만 `body`가 무효화되어야 한다 — 매 프레임 무효화는 `MapViewRepresentable.updateUIView`까지 다시 돌린다.
- 시트 높이 계산식(`SheetHeightBudget`, `expandedListHeight`, `sheetTopMargin`)은 건드리지 않는다.
- 시뮬레이터는 iOS 26.x `iPhone 17 Pro` UDID `FAE97799-97D7-4B5F-8960-5B796686C702` 하나만 사용한다. 실패해도 다른 시뮬레이터로 바꾸지 않는다.
- 테스트는 raw bash `xcodebuild ... -parallel-testing-enabled NO test`로만 실행한다.
- 각 태스크는 빌드·전체 테스트·SwiftLint·커밋 전 코드리뷰가 통과한 뒤 즉시 경로 명시 커밋한다. `git add -A`를 쓰지 않고, push는 하지 않는다.
- 사용자의 GPX 관련 Xcode 설정 변경(`Trace.xcodeproj/project.pbxproj`, `Trace.xcodeproj/xcshareddata/xcschemes/Trace.xcscheme`)은 이 사이클의 어떤 커밋에도 포함하지 않는다.

## 검증 명령

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

## File Structure

| 파일 | 책임 | 태스크 |
|---|---|---|
| `Trace/Pages/CoursePlannerPage/ScrollEdgeState.swift` | 신설 — 리스트가 스크롤 끝에 붙었는지 판정하는 순수 계산 + 드래그 구간 교집합 | 1 |
| `TraceTests/ScrollEdgeStateTests.swift` | 신설 — 위 판정의 경계값·바운스·짧은 콘텐츠·구간 교집합 테스트 | 1 |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` | 리스트 끝 접촉 상태 2개 추가 | 2 |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` | 스크롤 좌표계·끝 측정·인계 제스처 배선, 문턱 판정 공용 헬퍼 추출 | 2 |
| `TraceUITests/TraceUITests.swift` | 리스트 드래그로 시트가 접히는지 + 구간 행 버튼 회귀 | 2 |
| `docs/qa/2026-07-26-sheet-drag-device-checklist.md` | 실기기 확인 시나리오 1세션 7항목 | 3, 4 |
| `docs/roadmap.md` | 마일스톤 진행·완료 상태 | 3, 4 |

---

## Task 1: 스크롤 끝 판정을 순수 계산으로 만든다

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/ScrollEdgeState.swift`
- Test: `TraceTests/ScrollEdgeStateTests.swift`

**Interfaces:**
- Consumes: 없음 (이 마일스톤의 첫 태스크)
- Produces:
  - `struct ScrollEdgeState: Equatable { let isAtTop: Bool; let isAtBottom: Bool }`
  - `static let ScrollEdgeState.defaultTolerance: CGFloat` (값 8)
  - `static func ScrollEdgeState.make(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, tolerance: CGFloat = defaultTolerance) -> ScrollEdgeState`
  - `func ScrollEdgeState.intersected(with other: ScrollEdgeState) -> ScrollEdgeState`

**배경 — 왜 순수 타입으로 빼는가**

이 판정이 틀리면 스크롤만 하려던 손동작이 시트를 움직인다. 그리고 이 파일의 계산은 **경고 하나 없이 조용히 틀렸던 이력**이 있다(2026-07-21, 시트 예산에서 62pt가 소리 없이 사라짐). 같은 이유로 `SheetHeightBudget`·`FabLayoutPolicy`·`SegmentPanelLogic`이 이미 뷰 밖에 나와 테스트로 못박혀 있다. 이 타입도 같은 자리에 둔다.

`intersected(with:)`가 필요한 이유는 판정이 **순간이 아니라 구간**이기 때문이다. `DragGesture(minimumDistance:)`에는 터치다운 콜백이 없어 "드래그 시작 순간"을 읽을 수 없고, 종료 순간만 보면 리스트 중간에서 쓸어 끝에 도달한 손동작이 시트를 움직인다. 시작 근처만 보면 "맨 위에서 위로 쓸었다가 아래로 되돌리는" 손동작에서 똑같이 틀린다. 드래그 내내의 교집합을 취하면 세 경우가 모두 걸러진다.

- [ ] **Step 1: 실패하는 테스트를 먼저 쓴다**

`TraceTests/ScrollEdgeStateTests.swift`를 만든다.

```swift
import XCTest
@testable import Trace

final class ScrollEdgeStateTests: XCTestCase {
    // 기준 상황: 뷰포트 289pt(중간 단계 리스트 높이 ≈ pageHeight 722 × 0.4),
    // 콘텐츠 500pt → 아래로 211pt까지 스크롤 가능.
    private let viewport: CGFloat = 289
    private let content: CGFloat = 500

    func test_맨_위에_있으면_위쪽_끝으로만_판정한다() {
        let edge = ScrollEdgeState.make(scrollOffset: 0, contentHeight: content, viewportHeight: viewport)
        XCTAssertTrue(edge.isAtTop)
        XCTAssertFalse(edge.isAtBottom)
    }

    func test_맨_아래에_있으면_아래쪽_끝으로만_판정한다() {
        let edge = ScrollEdgeState.make(scrollOffset: 211, contentHeight: content, viewportHeight: viewport)
        XCTAssertFalse(edge.isAtTop)
        XCTAssertTrue(edge.isAtBottom)
    }

    func test_중간에서는_어느_끝도_아니다() {
        let edge = ScrollEdgeState.make(scrollOffset: 100, contentHeight: content, viewportHeight: viewport)
        XCTAssertFalse(edge.isAtTop)
        XCTAssertFalse(edge.isAtBottom)
    }

    // 허용 오차 경계. 오차가 없으면 구간 5개 안팎(스크롤 여유 20pt 남짓)에서
    // 화면상 정지해 보이는 구간을 먼저 스크롤해야만 인계가 걸린다 — "아무 반응 없음"으로 읽힌다.
    func test_남은_여유가_오차_이내면_끝으로_인정한다() {
        XCTAssertTrue(
            ScrollEdgeState.make(scrollOffset: 7, contentHeight: content, viewportHeight: viewport).isAtTop
        )
        XCTAssertTrue(
            ScrollEdgeState.make(scrollOffset: 204, contentHeight: content, viewportHeight: viewport).isAtBottom
        )
    }

    func test_남은_여유가_오차를_넘으면_끝이_아니다() {
        XCTAssertFalse(
            ScrollEdgeState.make(scrollOffset: 9, contentHeight: content, viewportHeight: viewport).isAtTop
        )
        XCTAssertFalse(
            ScrollEdgeState.make(scrollOffset: 202, contentHeight: content, viewportHeight: viewport).isAtBottom
        )
    }

    // 바운스로 오프셋이 경계 바깥(음수)으로 나가도 끝이다.
    // 바운스는 인계를 시도하는 동작 그 자체라, 여기서 벗어난 것으로 처리하면 규칙이 자기를 부정한다.
    func test_맨_위_바운스_중_음수_오프셋도_위쪽_끝이다() {
        XCTAssertTrue(
            ScrollEdgeState.make(scrollOffset: -40, contentHeight: content, viewportHeight: viewport).isAtTop
        )
    }

    // 구간이 1~2개면 스크롤할 것이 없다 → 리스트 전체가 그래버처럼 동작한다.
    // 예외 처리가 아니라 같은 식에서 그대로 나온다.
    func test_콘텐츠가_뷰포트보다_짧으면_양끝이_동시에_참이다() {
        let edge = ScrollEdgeState.make(scrollOffset: 0, contentHeight: 120, viewportHeight: viewport)
        XCTAssertTrue(edge.isAtTop)
        XCTAssertTrue(edge.isAtBottom)
    }

    // 드래그 도중 한 번이라도 끝에서 벗어나면 그 끝은 죽는다 — 방향 반전 손동작을 거르는 장치.
    func test_드래그_도중_끝에서_벗어나면_인계_자격을_잃는다() {
        let atTop = ScrollEdgeState(isAtTop: true, isAtBottom: false)
        let scrolledAway = ScrollEdgeState(isAtTop: false, isAtBottom: false)
        XCTAssertEqual(
            atTop.intersected(with: scrolledAway),
            ScrollEdgeState(isAtTop: false, isAtBottom: false)
        )
    }

    func test_끝에_계속_붙어_있으면_인계_자격이_유지된다() {
        let atTop = ScrollEdgeState(isAtTop: true, isAtBottom: false)
        XCTAssertEqual(atTop.intersected(with: atTop), atTop)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=FAE97799-97D7-4B5F-8960-5B796686C702" \
  -parallel-testing-enabled NO test 2>&1 | tail -30
```
Expected: 컴파일 실패 — `cannot find 'ScrollEdgeState' in scope`

- [ ] **Step 3: 최소 구현을 작성한다**

`Trace/Pages/CoursePlannerPage/ScrollEdgeState.swift`를 만든다.

```swift
import Foundation

// 구간 리스트가 스크롤 끝에 붙어 있는지의 판정. 뷰에서 분리한 순수 계산.
//
// 이 판정이 틀리면 스크롤만 하려던 손동작이 시트를 움직인다. 그리고 이 화면의 계산은
// 경고 하나 없이 조용히 틀렸던 이력이 있어(2026-07-21, 시트 예산에서 62pt가 소리 없이
// 사라짐) 뷰 안의 식으로 두지 않는다 — SheetHeightBudget·SegmentPanelLogic과 같은 자리.
struct ScrollEdgeState: Equatable {
    let isAtTop: Bool
    let isAtBottom: Bool

    /// 끝으로 인정할 여유. 구간 5개 안팎이면(행 ≈54pt + 간격 8pt) 중간 단계 리스트 높이
    /// ≈289pt를 근소하게 넘어 스크롤 여유가 20pt 남짓뿐이다. 오차가 없으면 사용자는
    /// 화면상 정지해 보이는 구간을 먼저 스크롤해 끝에 닿게 한 뒤 손을 떼고 다시 끌어야 한다.
    static let defaultTolerance: CGFloat = 8

    /// - Parameters:
    ///   - scrollOffset: 맨 위에서 아래로 스크롤한 거리. 맨 위 바운스 중에는 음수가 된다.
    ///   - contentHeight: 리스트 콘텐츠 전체 높이.
    ///   - viewportHeight: 리스트가 보이는 높이(`expandedListHeight`).
    static func make(
        scrollOffset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        tolerance: CGFloat = defaultTolerance
    ) -> ScrollEdgeState {
        let remainingBelow = contentHeight - viewportHeight - scrollOffset
        return ScrollEdgeState(
            isAtTop: scrollOffset <= tolerance,
            isAtBottom: remainingBelow <= tolerance
        )
    }

    /// 드래그가 진행되는 동안의 누적 판정 — 한 번이라도 그 끝에서 벗어나면 자격을 잃는다.
    ///
    /// 순간 스냅샷으로 판정할 수 없는 이유가 셋이다. ① `DragGesture(minimumDistance:)`에는
    /// 터치다운 콜백이 없어 "시작 순간"을 읽을 방법 자체가 없다. ② 종료 순간만 보면 리스트
    /// 중간에서 아래로 쓸어 맨 위에 도달한 손동작이 시트까지 내린다. ③ 시작 근처만 보면
    /// 맨 위에서 위로 쓸었다가 아래로 되돌리는 손동작에서 똑같이 틀린다.
    func intersected(with other: ScrollEdgeState) -> ScrollEdgeState {
        ScrollEdgeState(
            isAtTop: isAtTop && other.isAtTop,
            isAtBottom: isAtBottom && other.isAtBottom
        )
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=FAE97799-97D7-4B5F-8960-5B796686C702" \
  -parallel-testing-enabled NO test 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — `ScrollEdgeStateTests` 9개 포함 전체 통과

- [ ] **Step 5: SwiftLint를 통과시킨다**

Run: `swiftlint`
Expected: 새 파일에서 발생한 경고 0건. (앱 코드에 남아 있는 기존 경고 44건은 `lint-cleanup` 마일스톤 소유이므로 이번에 건드리지 않는다.)

- [ ] **Step 6: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점: 경계 부등호(`<=` vs `<`)가 테스트와 일치하는가, 음수 오프셋 처리가 의도대로인가, `intersected`가 교집합이 맞는가.

```bash
git add Trace/Pages/CoursePlannerPage/ScrollEdgeState.swift TraceTests/ScrollEdgeStateTests.swift docs/superpowers/plans/2026-07-26-sheet-drag.md
git commit -m "feat: 구간 리스트 스크롤 끝 판정 순수 타입 추가

리스트가 스크롤 끝에 붙어 있는지를 오프셋·콘텐츠 높이·뷰포트 높이로 판정하는 순수 계산을 뷰 밖으로 뺐다. 허용 오차 8pt를 두어 스크롤 여유가 20pt 남짓인 구간 5개 안팎에서 인계가 걸리지 않는 사각지대를 없앤다.
드래그 구간 교집합(intersected)을 함께 둔다. DragGesture에 터치다운 콜백이 없어 시작 순간을 읽을 수 없고, 종료 순간만 보면 중간에서 쓸어 끝에 도달한 손동작이, 시작 근처만 보면 방향 반전 손동작이 각각 시트를 잘못 움직인다.
바운스 음수 오프셋과 콘텐츠가 뷰포트보다 짧은 경우를 포함해 경계값 9개를 테스트로 못박았다. 이 화면의 계산은 경고 없이 조용히 틀렸던 이력이 있다."
```

---

## Task 2: 리스트 드래그를 시트로 넘긴다

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (상태 2개 추가, `@State var panelWasNearLatestAtCollapse` 선언 바로 뒤)
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` (`sheetDragGesture`, `expandedSheetBody`)
- Test: `TraceUITests/TraceUITests.swift`

**Interfaces:**
- Consumes: Task 1의 `ScrollEdgeState.make(scrollOffset:contentHeight:viewportHeight:tolerance:)`와 `intersected(with:)`
- Produces: 없음 (마지막 코드 태스크)

**배경 — 왜 동시 인식인가**

`ScrollView`는 자기 팬 제스처를 이미 갖고 있어서, 시트 드래그를 그대로 얹으면 둘이 충돌한다. 더 중요한 건 **제스처로 뷰를 감싸면 그 안의 버튼이 전부 먹통이 된 회귀 이력**이다(2026-07-12 — `sheetHeader`를 감쌌더니 `저장`·`전체 왕복`이 반응하지 않았고, 배경 레이어에 거는 방식으로 우회했다). 구간 행에는 버튼이 둘씩 있으므로 같은 함정이 그대로 있다.

`simultaneousGesture`는 소유권을 뺏지 않고 옆에서 관찰만 하므로 그 경로를 타지 않는다. 최소 이동 거리 8pt라 탭에는 애초에 발동하지 않는다.

리스트에는 그래버·헤더가 쓰는 배경 레이어 우회를 쓸 수 없다 — 배경은 스크롤 콘텐츠 뒤에 있어 터치가 닿지 않는다. 그래서 이 태스크만 다른 메커니즘을 쓴다.

- [ ] **Step 1: 실패하는 UI 테스트를 먼저 쓴다**

`TraceUITests/TraceUITests.swift`의 `testRunTabShowsGoalSetupAndDistanceInput` 뒤, `private extension XCUIElement` 앞에 두 테스트를 추가한다.

```swift
    // 구간 1개면 리스트 콘텐츠가 뷰포트보다 짧아 양끝이 동시에 참이다 —
    // 리스트 아무 데나 잡고 아래로 끌면 시트가 한 단계 접힌다.
    @MainActor
    func testDraggingSegmentListDownCollapsesSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        // 초기 단계는 기본(접힘)이라 리스트가 렌더되지 않는다. 헤더를 눌러 중간으로 올린다.
        app.buttons["coursePlanner.segmentPanel.collapsed"].tap()

        let row = app.buttons["coursePlanner.segmentPanel.item.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)))

        // 기본 단계에서는 expandedSheetBody 자체가 사라진다.
        let disappeared = NSPredicate(format: "exists == false")
        expectation(for: disappeared, evaluatedWith: row)
        waitForExpectations(timeout: 5)
    }

    // 회귀 1순위: 리스트에 제스처를 얹어도 구간 행 버튼이 탭을 그대로 받아야 한다.
    // 2026-07-12에 sheetHeader를 제스처로 감쌌다가 안쪽 버튼이 전부 먹통이 된 이력이 있다.
    @MainActor
    func testSegmentRowButtonsStayTappableWithListDragGesture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        app.buttons["coursePlanner.segmentPanel.collapsed"].tap()

        let row = app.buttons["coursePlanner.segmentPanel.item.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(app.buttons["coursePlanner.segmentPanel.roundTrip.0"].exists)

        // 탭이 드래그로 해석되면 시트 단계가 바뀌어 행이 사라진다. 탭 뒤에도 남아 있어야 한다.
        row.tap()
        XCTAssertTrue(row.exists)
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=FAE97799-97D7-4B5F-8960-5B796686C702" \
  -parallel-testing-enabled NO test 2>&1 | tail -40
```
Expected: `testDraggingSegmentListDownCollapsesSheet` 실패 — 리스트 드래그가 시트를 움직이지 않아 행이 계속 존재한다. `testSegmentRowButtonsStayTappableWithListDragGesture`는 이 시점에 이미 통과한다(회귀 감시용이므로 정상이다).

- [ ] **Step 3: 페이지에 리스트 끝 접촉 상태를 추가한다**

`Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`에서 `@State var panelWasNearLatestAtCollapse = true` 바로 아래에 추가한다.

```swift
    // 리스트가 스크롤 끝에 붙어 있는가 — 시트 인계 판정의 입력.
    // 오프셋 같은 연속 값을 그대로 상태에 흘리면 스크롤하는 매 프레임 이 페이지의 body가
    // 재평가되고, 그때마다 MapViewRepresentable.updateUIView가 전 구간을 도는 스냅샷을
    // 다시 만든다. Bool 두 개만 올려 값이 실제로 뒤집힐 때만 무효화되게 한다.
    @State var listScrollEdge = ScrollEdgeState(isAtTop: true, isAtBottom: true)
    // 드래그가 시작된 뒤 지금까지 유지된 끝 접촉. 드래그당 한 번 래치하고 콜백마다 교집합을 취한다.
    @State var listDragEdge: ScrollEdgeState?
```

- [ ] **Step 4: 문턱 판정을 공용 헬퍼로 뽑는다 (동작 변경 없음)**

`CoursePlannerPage+BottomSheetComponent.swift`의 `sheetDragGesture`를 아래로 교체한다. 문턱(40pt)과 한 단계 이동은 그대로이고, 판정만 리스트와 공유할 수 있게 함수로 나온다.

```swift
    // 그래버·헤더·리스트가 공유하는 단일 이동 규칙 — 40pt를 넘게 끌면 그 방향으로 한 단계.
    // 한 번의 드래그는 아무리 길어도 한 단계만 움직인다(2026-07-26 사용자 확정: 시트는
    // 기본↔중간↔풀을 한 칸씩 지나간다). 진입점은 늘리되 규칙은 하나로 둔다.
    private func detentAfterDrag(translationHeight: CGFloat) -> SheetDetent? {
        let threshold: CGFloat = 40
        guard abs(translationHeight) > threshold else { return nil }
        return translationHeight < 0 ? sheetDetent.steppedUp : sheetDetent.steppedDown
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                // 탭 토글도 경로 유무와 무관하게 기본↔중간을 오가므로, 드래그도 똑같이 경로
                // 유무와 무관하게 단계를 이동한다 — 둘의 동작이 다르면 안 된다는 사용자 확인
                // (2026-07-12: "빈 경로일 때 버튼을 누르면 시트가 올라가는데 드래그로는 안돼").
                guard let nextDetent = detentAfterDrag(translationHeight: value.translation.height) else { return }
                // Gesture의 onEnded는 Button 액션과 달리 SwiftUI가 안전하게 지연 디스패치하지
                // 않는다 — 여기서 곧바로 @State를 쓰면 "Modifying state during view update"
                // 경고가 발생한다(2026-07-12 실기기 콘솔 로그로 재현·확정, 탭 토글에서는 없음).
                // 다음 런루프로 한 틱 미뤄 현재 진행 중인 뷰 업데이트 트랜잭션 밖에서 쓰게 한다.
                DispatchQueue.main.async {
                    setSheetDetent(nextDetent)
                }
            }
    }
```

기존 `sheetDragGesture` 위에 붙어 있던 "그래버만으로는 좁다"는 주석 블록(41~46행)은 그대로 둔다.

- [ ] **Step 5: 리스트 인계 제스처를 추가한다**

같은 파일의 `sheetDragGesture` 아래에 추가한다.

```swift
    // 리스트가 스크롤 끝에 붙어 있는 동안의 드래그를 시트로 넘기는 게이트.
    //
    // 동시 인식(simultaneous)이라 ScrollView의 스크롤 소유권을 뺏지 않는다. 그래버·헤더에서
    // 쓴 "배경 레이어에 걸기" 우회는 여기서 못 쓴다 — 배경은 스크롤 콘텐츠 뒤에 있어 터치가
    // 닿지 않는다. 최소 이동 거리 8pt라 탭에는 발동하지 않으므로, 제스처로 뷰를 감쌌다가
    // 안쪽 버튼이 전부 먹통이 됐던 2026-07-12 회귀의 경로는 타지 않는다.
    private var listHandoffGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                // 드래그 내내 유지된 끝 접촉만 인계 자격이 있다(ScrollEdgeState.intersected 주석 참고).
                listDragEdge = listDragEdge?.intersected(with: listScrollEdge) ?? listScrollEdge
            }
            .onEnded { value in
                let maintainedEdge = listDragEdge
                listDragEdge = nil
                guard let maintainedEdge,
                      let nextDetent = detentAfterDrag(translationHeight: value.translation.height)
                else { return }
                // 그 끝을 벗어나는 방향으로 끌었을 때만 넘긴다. 맨 위에서 아래로 = 축소,
                // 맨 아래에서 위로 = 확대. 반대 방향은 갈 곳이 남아 있으므로 그냥 스크롤이다.
                let goingUp = value.translation.height < 0
                guard goingUp ? maintainedEdge.isAtBottom : maintainedEdge.isAtTop else { return }
                DispatchQueue.main.async {
                    setSheetDetent(nextDetent)
                }
            }
    }
```

- [ ] **Step 6: 스크롤 좌표계와 끝 측정을 배선한다**

같은 파일의 `expandedSheetBody`를 아래로 교체한다. `LazyVStack`에 측정을, `ScrollView`에 좌표계와 제스처를 건다.

```swift
    // 스크롤 오프셋을 읽기 위한 좌표계 이름. onScrollGeometryChange는 iOS 18+라 쓸 수 없다
    // (배포 타깃 17.0). 이름 붙인 좌표계 + onGeometryChange는 이 저장소가 이미 쓰는 조합이다.
    private static let listCoordinateSpace = "coursePlanner.segmentPanel.scroll"

    private var expandedSheetBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(panelRows) { row in
                            segmentRow(row)
                        }
                    }
                    .scrollTargetLayout()
                    // 콘텐츠의 스크롤 좌표계 프레임 하나에서 오프셋(-minY)과 콘텐츠 높이를 같이 읽는다.
                    // 파생값이 Bool 두 개라, 스크롤하는 동안에도 그 쌍이 실제로 바뀔 때만 action이 돈다.
                    .onGeometryChange(for: ScrollEdgeState.self) { geometry in
                        let contentFrame = geometry.frame(in: .named(Self.listCoordinateSpace))
                        return ScrollEdgeState.make(
                            scrollOffset: -contentFrame.minY,
                            contentHeight: contentFrame.height,
                            viewportHeight: expandedListHeight
                        )
                    } action: { edge in
                        listScrollEdge = edge
                    }
                }
                // 고정 높이 — 자기 콘텐츠를 측정해서 자기 프레임에 다시 먹이는 순환(측정→적용→재측정)이
                // 없다. 이 순환이 구간 선택처럼 콘텐츠가 미세하게 바뀔 때마다 레이아웃이 잠깐
                // 움찔거리는 원인 중 하나였다(2026-07-12, 사용자 확인).
                .frame(height: expandedListHeight)
                .coordinateSpace(.named(Self.listCoordinateSpace))
                .simultaneousGesture(listHandoffGesture)
                // 콘텐츠 여백만 12pt로 주고 스크롤 인디케이터는 기본 여백(에지에 붙게) 유지 —
                // .padding()으로 ScrollView 전체를 감싸면 인디케이터까지 같이 밀려 보인다 (실기기 QA 발견).
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .scrollPosition(id: $panelAnchorColorKey, anchor: .center)
                .onAppear {
                    restoreScrollPosition(proxy)
                }
                .onChange(of: viewModel.segmentColorKeys.max()) { oldMax, newMax in
                    // 증가(새 구간)일 때만 — undo/clear로 줄어들 때는 보던 위치 유지 (스펙)
                    guard let newMax, newMax > (oldMax ?? Int.min) else { return }
                    autoScrollIfNearLatest(proxy, previousMaxKey: oldMax)
                }
            }
        }
        .frame(minWidth: 220)
    }
```

- [ ] **Step 7: 빌드하고 전체 테스트를 통과시킨다**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=FAE97799-97D7-4B5F-8960-5B796686C702" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=FAE97799-97D7-4B5F-8960-5B796686C702" \
  -parallel-testing-enabled NO test 2>&1 | tail -40
```
Expected: `** BUILD SUCCEEDED **`, 이어서 `** TEST SUCCEEDED **` — Task 1의 단위 테스트와 새 UI 테스트 2개를 포함해 전부 통과.

`.coordinateSpace(.named(_:))`나 `geometry.frame(in: .named(_:))`에서 가용성 오류가 나면, 그 자리에서 다른 API로 갈아타지 말고 **먼저 오류 메시지를 그대로 보고**한다. 이 조합은 iOS 17.0 기준으로 선택한 것이며, 대체 경로(`GeometryReader` 배경 + `PreferenceKey`)는 상태 갱신 빈도가 달라져 Global Constraint(연속 값을 상태에 흘리지 않는다)를 다시 검토해야 한다.

- [ ] **Step 8: 시뮬레이터에서 눈으로 확인한다**

앱을 실행해 코스 탭에서 지도를 두 번 탭해 구간을 만들고, 헤더를 눌러 시트를 중간으로 올린 뒤 확인한다.

1. 리스트를 아래로 쓸면 시트가 기본으로 접힌다.
2. 시트를 중간으로 되돌리고 리스트를 위로 쓸면 풀로 커진다.
3. 구간 행을 탭하면 선택 테두리가 생기고 시트 단계는 그대로다.

구간을 6개 이상 만들어 리스트가 실제로 스크롤되는 상태에서도 확인한다: 리스트 중간에서 끌면 시트가 움직이지 않고, 맨 위까지 스크롤한 뒤 손을 떼고 다시 끌어야 접힌다.

**시뮬레이터로 확인 불가능한 것을 스모크 통과로 뭉뚱그리지 않는다.** 바운스 감각과 인계가 손에 자연스럽게 잡히는지는 합성 제스처로 판정할 수 없다 — `draw-gesture`가 롱프레스-드래그 합성 한계를 INCONCLUSIVE로 명시한 선례를 따르고, Task 3의 실기기 QA로 넘긴다. XcodeBuildMCP의 `drag`는 이 환경에서 즉시 실패하므로(`docs/solutions/workflow-issues/xcodebuildmcp-cannot-synthesize-long-press-drag.md`) 합성이 필요하면 `swipe`만 쓴다.

- [ ] **Step 9: SwiftLint를 통과시킨다**

Run: `swiftlint`
Expected: 이번 변경으로 늘어난 경고 0건.

- [ ] **Step 10: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점(이 파일의 실제 회귀 이력에 맞춘다):
- `simultaneousGesture`가 구간 행 버튼의 탭을 가로채지 않는가
- `listDragEdge` 래치가 드래그마다 정확히 한 번 시작되고 끝날 때 비워지는가
- `onGeometryChange`의 파생값이 Bool 쌍이라 스크롤 중 상태 쓰기가 억제되는가
- `detentAfterDrag` 추출로 그래버·헤더 드래그의 동작이 바뀌지 않았는가

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift \
  Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift \
  TraceUITests/TraceUITests.swift docs/superpowers/plans/2026-07-26-sheet-drag.md
git commit -m "feat: 구간 리스트에서도 시트를 접고 펼 수 있게 한다

리스트가 스크롤 끝에 붙어 있는 동안의 드래그를 시트로 넘긴다. 맨 위에서 아래로 당기면 축소, 맨 아래에서 위로 밀면 확대이고, 구간이 짧아 스크롤할 것이 없으면 리스트 전체가 그래버처럼 동작한다.
제스처는 동시 인식으로 얹어 ScrollView의 소유권을 뺏지 않는다. 그래버·헤더가 쓰는 배경 레이어 우회는 스크롤 콘텐츠 뒤라 터치가 닿지 않아 쓸 수 없었고, 최소 이동 거리 8pt라 탭에는 발동하지 않는다.
스크롤 오프셋은 상태로 올리지 않고 끝 접촉 Bool 두 개만 올려, 스크롤 중 매 프레임 body가 무효화되며 MapViewRepresentable까지 다시 도는 일을 막았다. 40pt 문턱 판정은 공용 헬퍼로 뽑되 동작은 그대로다."
```

---

## Task 3: 실기기 QA 체크리스트를 만들고 사용자에게 제시한다

**Files:**
- Create: `docs/qa/2026-07-26-sheet-drag-device-checklist.md`
- Modify: `docs/roadmap.md` (MVP17 `sheet-drag` 항목에 진행 상태와 체크리스트 링크 추가)

**Interfaces:**
- Consumes: Task 2까지의 동작
- Produces: 사용자가 채워 돌려줄 체크리스트

체크리스트는 파일로 만든다. 항목 7개가 모두 같은 준비 상태(코스 탭, 구간이 있는 화면)에서 이어지므로 **한 세션 카드 안에 번호 붙은 체크포인트**로 묶는다(`testing.md` "세션 단위로 묶기").

- [ ] **Step 1: 체크리스트를 작성한다**

`docs/qa/2026-07-26-sheet-drag-device-checklist.md`를 만든다.

```markdown
# 시트 콘텐츠 드래그 실기기 체크리스트 (2026-07-26)

대상: MVP17 마일스톤 3 `sheet-drag` — 코스 탭 바텀시트의 구간 리스트에서도 시트를 접고 펴는 동작.
설계: `docs/superpowers/specs/2026-07-26-sheet-drag-design.md`

## 빌드/설치
- [ ] 기기 연결, 자동 서명 팀 확인, Xcode Run 성공

## 핵심 기능 (손으로 수행)

### 시나리오 1: 리스트 위에서 시트가 의도대로 움직이는가

**준비:** 코스 탭에서 지도를 여러 번 탭해 **구간을 6개 이상** 만든다(리스트가 실제로 스크롤되는 상태여야 한다). 시트 헤더를 눌러 중간 단계로 올린다.

**수행 및 확인:**

1. **맨 위에서 아래로 당기기** — 리스트를 맨 위까지 올린 뒤 손가락으로 아래로 당긴다.
   → 시트가 한 단계 작아진다.
   **결과:** ☐ 통과 ☐ 실패

2. **맨 아래에서 위로 밀기** — 시트를 중간으로 되돌리고 리스트를 맨 아래까지 내린 뒤 위로 민다.
   → 시트가 풀(가장 큰 상태)로 커진다.
   **결과:** ☐ 통과 ☐ 실패

3. **구간이 적을 때** — 지도 초기화 후 구간을 1~2개만 만든다. 시트를 중간으로 올리고 리스트 아무 데나 잡고 위·아래로 끈다.
   → 양쪽 다 시트가 움직인다(스크롤할 것이 없으므로 리스트 전체가 손잡이처럼 동작).
   → **중간 단계와 풀 단계에서 각각** 해본다. 두 단계에서 보이는 리스트 높이가 달라 반응이 갈릴 수 있다.
   **결과:** ☐ 통과 ☐ 실패

4. **버튼이 그대로 눌리는가 (가장 중요)** — 구간 행을 탭한다. 이어서 행 오른쪽의 왕복 버튼(↺)을 탭한다.
   → 행 탭: 선택 테두리가 생기고 지도가 그 구간으로 맞춰진다. 시트 크기는 그대로다.
   → 왕복 버튼: 눌리는 구간이면 왕복이 추가된다(비활성이면 흐리게 보이는 것이 정상).
   **결과:** ☐ 통과 ☐ 실패

5. **한 칸씩 움직이는가** — 시트를 풀로 올린 뒤 리스트를 아래로 **아주 길게** 당긴다.
   → 중간에서 멈춘다(기본까지 한 번에 내려가지 않는다). 손을 떼고 다시 당기면 기본으로 간다.
   → 이 "두 번 당기기"가 답답하게 느껴지는지 메모에 적어주세요.
   **결과:** ☐ 통과 ☐ 실패

6. **리스트 중간에서는 안 움직여야 한다** — 구간 6개 이상 상태에서, 리스트를 중간쯤 스크롤한 위치에서 위아래로 끈다.
   → 리스트만 스크롤되고 시트 크기는 변하지 않는다.
   **결과:** ☐ 통과 ☐ 실패

7. **끝에 닿아도 그 손동작에서는 안 넘어간다** — 리스트 중간에서 시작해 **손을 떼지 않고** 맨 위(또는 맨 아래)까지 스크롤한 뒤 계속 같은 방향으로 끈다.
   → 그 손동작에서는 시트가 움직이지 않는다. 손을 떼고 다시 끌면 그때 움직인다.
   → 이 "떼고 다시 끌기"가 거슬리는지 메모에 적어주세요.
   **결과:** ☐ 통과 ☐ 실패

**메모:**

## 이번 QA의 통과 조건이 아닌 것

- VoiceOver 동작 (이번 MVP의 통과 기준에서 제외)
- 배터리·GPS 정확도 (이 화면과 무관)
- 러닝·기록 탭 (해당 시트가 없음)
```

- [ ] **Step 2: 5번과 7번이 이연 항목의 트리거임을 로드맵에 연결한다**

`docs/roadmap.md`의 MVP17 `sheet-drag` 항목을 아래로 교체한다.

```markdown
- [~] **sheet-drag** — 코스 탭 구간 리스트가 스크롤 끝에 붙어 있는 동안의 드래그를 시트로 넘긴다. 위·아래 같은 규칙이며 한 번의 드래그는 한 단계만 움직인다. 설계: [`2026-07-26-sheet-drag-design.md`](superpowers/specs/2026-07-26-sheet-drag-design.md) · 구현 플랜: [`2026-07-26-sheet-drag.md`](superpowers/plans/2026-07-26-sheet-drag.md) · 실기기 QA: [`2026-07-26-sheet-drag-device-checklist.md`](qa/2026-07-26-sheet-drag-device-checklist.md) — 체크포인트 5·7은 각각 "거리 비례 이동"·"한 손동작 내 인계" 이연 항목의 트리거 판정을 겸한다
```

- [ ] **Step 3: 사용자에게 체크리스트를 제시한다**

대화에서 파일 경로와 함께 수행 순서를 안내한다. **이 단계에서 마일스톤을 완료로 표시하지 않는다.** 체크포인트 5·7은 통과/실패와 별개로 "답답한가 / 거슬리는가"라는 감각 판정을 함께 요청한다 — 그 답이 이연 항목의 트리거다.

- [ ] **Step 4: 문서를 검토하고 커밋한다**

```bash
git add docs/qa/2026-07-26-sheet-drag-device-checklist.md docs/roadmap.md docs/superpowers/plans/2026-07-26-sheet-drag.md
git commit -m "docs: 시트 콘텐츠 드래그 실기기 QA 체크리스트 추가

구간 리스트 인계를 손으로 확인할 7개 체크포인트를 한 세션 카드로 묶었다. 모두 같은 준비 상태(코스 탭, 구간이 있는 화면)에서 이어지므로 카드를 쪼개지 않았다.
4번(구간 행 버튼이 그대로 눌리는가)이 회귀 1순위다. 이 파일에서 제스처를 잘못 붙여 시트 안 버튼이 전부 먹통이 된 이력이 있고, 자동 테스트로는 손가락 감각까지 잡히지 않는다.
5번과 7번은 통과 판정과 별개로 감각 판정을 겸한다 — 각각 거리 비례 이동과 한 손동작 내 인계라는 이연 항목의 트리거다. 로드맵에서 그 연결을 명시했다."
```

---

## Task 4: QA 결과를 수용하고 마일스톤을 닫는다

**Files:**
- Modify: `docs/qa/2026-07-26-sheet-drag-device-checklist.md` (결과 기록)
- Modify: `docs/roadmap.md` (마일스톤 완료 표시)
- Modify: `docs/backlog.md` (트리거 판정 결과 반영)
- Modify: `docs/superpowers/plans/2026-07-26-sheet-drag.md` (체크박스 갱신)

**Interfaces:**
- Consumes: 사용자가 채운 체크리스트
- Produces: 완료된 마일스톤

- [ ] **Step 1: 결과를 항목별로 분류한다**

`testing.md`의 Real-Device Verification 기준으로 가른다. **진짜 고장**(스펙대로 안 동작해 이 마일스톤의 통과를 막음)이면 같은 브랜치에서 `superpowers:systematic-debugging`으로 바로 고친다. **의도 불일치·개선**이면 `docs/backlog.md`에 기록하고 다음 마일스톤 후보로 미룬다.

분류를 확정하기 전에 `advisor`로 검토하고, 결론을 대화에서 한 줄로 먼저 선언한다(예: "진짜 고장 → 지금 고침", "의도 불일치/개선 → 백로그 등록").

- [ ] **Step 2: 체크포인트 5·7의 감각 판정을 이연 항목에 반영한다**

- 5번에서 "한 칸씩이라 답답하다"가 나오면 → `docs/backlog.md`에 **거리 비례 이동**을 트리거 충족으로 기록한다.
- 7번에서 "떼고 다시 끌기가 거슬린다"가 나오면 → **한 손동작 내 인계**(`UIScrollView` 래핑)를 트리거 충족으로 기록한다.
- 둘 다 아니면 두 항목을 트리거 미충족으로 남긴다. 새 런을 한 것처럼 추정하지 말고 **사용자가 실제로 답한 내용만** 적는다.

- [ ] **Step 3: 수용된 경우에만 마일스톤을 완료로 바꾼다**

`docs/roadmap.md`의 `sheet-drag`를 `[~]`에서 `[x]`로 바꾸고, 통과 사실과 제외 범위를 한 줄로 남긴다. MVP17의 나머지 마일스톤(`lint-cleanup`) 상태는 건드리지 않는다. 이 플랜 파일의 체크박스도 같은 턴에 갱신한다.

- [ ] **Step 4: 문서 변경을 검토하고 커밋한다**

```bash
git add docs/qa/2026-07-26-sheet-drag-device-checklist.md docs/roadmap.md docs/backlog.md docs/superpowers/plans/2026-07-26-sheet-drag.md
git commit -m "docs: 시트 콘텐츠 드래그 실기기 QA 결과 수용

사용자 실기기 확인 결과를 체크리스트에 항목별로 기록하고 마일스톤을 닫았다. 새 확인을 한 것처럼 추정하지 않고 사용자가 답한 내용과 제외 범위만 적었다.
체크포인트 5·7의 감각 판정을 거리 비례 이동과 한 손동작 내 인계 이연 항목의 트리거 충족 여부로 백로그에 반영했다.
MVP17의 나머지 마일스톤(lint-cleanup) 상태는 건드리지 않았다."
```

---

## 플랜 자체 검토 (2026-07-26)

- [x] 스펙의 인계 조건 표·허용 오차·구간 판정이 Task 1의 테스트 케이스로 1:1 대응된다.
- [x] "그래버·헤더 동작 변경 없음" 제약과 실제 변경(문턱 판정 추출)의 관계를 Task 2 Step 4에 명시하고, 리뷰 초점에도 넣었다.
- [x] "연속 값을 상태에 흘리지 않는다" 제약이 코드(파생값을 Bool 쌍으로)와 리뷰 초점 양쪽에 걸려 있다.
- [x] 스펙의 QA 7항목이 체크리스트 체크포인트 7개와 번호까지 일치한다.
- [x] 시뮬레이터로 확인 불가능한 것(바운스 감각)을 Task 2 Step 8에서 명시적으로 실기기로 이관했다.
- [x] Task 1이 만든 타입 이름·시그니처가 Task 2에서 쓰는 것과 일치한다(`ScrollEdgeState.make`, `intersected(with:)`, `listScrollEdge`, `listDragEdge`).
- [x] 이연 항목 두 개(거리 비례, 한 손동작 내 인계)의 트리거가 QA 체크포인트 5·7 → Task 4 Step 2로 이어져 판정될 경로가 있다.
