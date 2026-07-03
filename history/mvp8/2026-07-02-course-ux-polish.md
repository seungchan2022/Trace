# 코스 편집 UX 다듬기 (MVP8 마일스톤 1) Implementation Plan

> **완료(소급 확인, 2026-07-03)** — Task 1~4 전부 구현·리뷰·실기기 QA 완료. 근거 커밋:
> `02d9d07`(Task1) · `2c155b9`+`33abab0`(Task2) · `3aebf20`(Task3) · `d653e9d`(Task4 QA 체크리스트).
> 실행 중 체크박스 갱신을 누락해 아래 `- [ ]`는 그대로 남아있음(내용은 전부 완료됨, 개별 복원하지 않음).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 구간 패널에 최대 높이(지도 높이 40%) + 스크롤 + 채팅 앱 방식 자동 스크롤을 넣고, 그리기 모드 핀치 줌을 MKMapView 내장 줌으로 복원한다.

**Architecture:** 스크롤 정책 판정은 `SegmentPanelLogic`(순수 함수, TDD)으로 분리하고, 뷰(`CoursePlannerPage+SegmentPanelComponent`)는 그 판정을 소비만 한다. 핀치 복원은 `MapViewRepresentable`에서 커스텀 핀치 코드 삭제 + `isZoomEnabled` 토글 제거. 도메인/Application/ViewModel 변경 없음.

**Tech Stack:** SwiftUI (iOS 17+, `ScrollViewReader`/`scrollPosition(id:)`/`onGeometryChange`), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-02-course-ux-polish-design.md`

## Global Constraints

- Minimum iOS 17.0, Swift 6 스타일, `@Observable` (ObservableObject 금지)
- SwiftLint: force unwrap/cast/try 금지 (`!` 사용 시 lint 에러)
- 시뮬레이터: 세션당 UDID 1개 고정, iOS 26+ 런타임만 (`docs/agent-rules/testing.md`)
- 커밋 전 3종 통과 + 스탬프 필수: build/test/lint → `.git/trace-verify-{build,test,lint}.ok`
- 커밋: `scripts/trace-commit.sh -m "..." -- <paths>` 사용, 브랜치 `feature/course-ux-polish`
- 검증 명령 (아래 모든 Task에서 동일, `$SIM_UDID`는 세션 시작 시 1회 고정):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test && touch .git/trace-verify-test.ok
swiftlint && touch .git/trace-verify-lint.ok
```

---

### Task 1: SegmentPanelLogic — 스크롤 정책 순수 함수

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/SegmentPanelLogic.swift`
- Test: `TraceTests/SegmentPanelLogicTests.swift`

**Interfaces:**
- Consumes: 없음 (순수 함수)
- Produces: `SegmentPanelLogic.latestIndex(colorKeys: [Int]) -> Int?`, `SegmentPanelLogic.shouldAutoScroll(anchorIndex: Int?, previousLatestIndex: Int?, tolerance: Int) -> Bool` — Task 2가 소비

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SegmentPanelLogicTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class SegmentPanelLogicTests: XCTestCase {
    // MARK: - latestIndex (최신 = 생성 순번 최대, 배열 위치와 무관)

    func testLatestIndexIsNilForEmptyKeys() {
        XCTAssertNil(SegmentPanelLogic.latestIndex(colorKeys: []))
    }

    func testLatestIndexIsLastRowWhenOnlyAppended() {
        XCTAssertEqual(SegmentPanelLogic.latestIndex(colorKeys: [0, 1, 2]), 2)
    }

    func testLatestIndexIsFirstRowWhenPrepended() {
        // 코스 시작점에 붙은 구간은 prepend되어 배열 맨 앞에 온다 (CourseEditSession.prepend)
        XCTAssertEqual(SegmentPanelLogic.latestIndex(colorKeys: [2, 0, 1]), 0)
    }

    // MARK: - shouldAutoScroll (채팅 앱 방식: 최신 근처를 보고 있을 때만 따라간다)

    func testAutoScrollsWhenAnchorUnknown() {
        // 스크롤 정보가 없으면(목록이 짧아 스크롤 자체가 없을 때 등) 항상 따라간다
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: nil, previousLatestIndex: 5, tolerance: 3))
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 2, previousLatestIndex: nil, tolerance: 3))
    }

    func testAutoScrollsWhenViewingNearLatest() {
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 9, previousLatestIndex: 11, tolerance: 3))
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 11, previousLatestIndex: 11, tolerance: 3))
    }

    func testDoesNotAutoScrollWhenBrowsingOldSegments() {
        XCTAssertFalse(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 2, previousLatestIndex: 11, tolerance: 3))
    }

    func testToleranceBoundaryIsInclusive() {
        XCTAssertTrue(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 8, previousLatestIndex: 11, tolerance: 3))
        XCTAssertFalse(SegmentPanelLogic.shouldAutoScroll(anchorIndex: 7, previousLatestIndex: 11, tolerance: 3))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: Global Constraints의 test 명령 (또는 `-only-testing:TraceTests/SegmentPanelLogicTests` 추가)
Expected: FAIL — `cannot find 'SegmentPanelLogic' in scope` (컴파일 에러도 실패로 간주)

- [ ] **Step 3: 최소 구현**

`Trace/Pages/CoursePlannerPage/SegmentPanelLogic.swift` 생성:

```swift
import Foundation

// 구간 패널의 스크롤 정책 판정. 뷰에서 분리한 순수 함수 — 스펙의 "판정은 순수 함수로 분리해
// 유닛 테스트한다" 요구사항 (2026-07-02-course-ux-polish-design.md).
enum SegmentPanelLogic {
    /// 가장 최근에 attach된 구간(생성 순번 최대)의 배열 인덱스.
    /// prepend 시 배열 맨 앞이 최신일 수 있으므로 "마지막 행"이 아니라 colorKey 최대값으로 찾는다.
    static func latestIndex(colorKeys: [Int]) -> Int? {
        guard let maxKey = colorKeys.max() else { return nil }
        return colorKeys.firstIndex(of: maxKey)
    }

    /// 채팅 앱 방식 자동 스크롤: 사용자가 직전 최신 구간 근처를 보고 있을 때만 새 구간을 따라간다.
    /// - anchorIndex: 뷰포트에 보이는 행(스크롤 앵커)의 배열 인덱스. nil이면 스크롤 정보 없음 → 따라간다.
    /// - previousLatestIndex: 새 구간이 추가되기 전 최신 구간의 배열 인덱스.
    /// - tolerance: "근처"로 인정할 행 간격. 패널 뷰포트가 최대 6행 내외라 3이 기본.
    static func shouldAutoScroll(anchorIndex: Int?, previousLatestIndex: Int?, tolerance: Int = 3) -> Bool {
        guard let anchorIndex, let previousLatestIndex else { return true }
        return abs(anchorIndex - previousLatestIndex) <= tolerance
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Global Constraints의 test 명령
Expected: PASS (기존 테스트 포함 전체 green)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 구간 패널 스크롤 정책 순수 함수 추가

- 최신 구간 인덱스는 colorKey 최대값 기준 (prepend에도 안정)
- 채팅 앱 방식 자동 스크롤 판정(shouldAutoScroll) 추가
- 뷰에서 분리해 유닛 테스트로 커버" -- Trace/Pages/CoursePlannerPage/SegmentPanelLogic.swift TraceTests/SegmentPanelLogicTests.swift
```

---

### Task 2: 구간 패널 — 최대 높이 + 스크롤 + 자동 스크롤 연결

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (@State 3개 + 지도 높이 측정)
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift` (전면 개편)

**Interfaces:**
- Consumes: `SegmentPanelLogic.latestIndex`, `SegmentPanelLogic.shouldAutoScroll` (Task 1), `viewModel.segmentColorKeys: [Int]`, `viewModel.course?.segments: [CourseSegment]`, `viewModel.selectSegment(at: Int)` (기존)
- Produces: 뷰 전용 — 후속 Task가 의존하는 인터페이스 없음

- [ ] **Step 1: CoursePlannerPage에 상태와 지도 높이 측정 추가**

`CoursePlannerPage.swift`의 기존 `@State var isSegmentPanelExpanded = false` 아래에 추가:

```swift
    @State var panelContentHeight: CGFloat = 0
    @State var panelMaxListHeight: CGFloat = 300
    @State var panelAnchorColorKey: Int?
```

같은 파일 `mapView`의 `.overlay(alignment: .topTrailing) { segmentPanel }` 바로 위에 추가
(지도 뷰의 실제 가용 높이 × 0.4 — 스펙 결정: UIScreen이 아니라 지도 뷰 기준):

```swift
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelMaxListHeight = height * 0.4
        }
```

- [ ] **Step 2: SegmentPanelComponent 전면 개편**

`CoursePlannerPage+SegmentPanelComponent.swift` 전체를 다음으로 교체:

```swift
import SwiftUI

extension CoursePlannerPage {
    var segmentPanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if isSegmentPanelExpanded {
                expandedSegmentList
            } else {
                collapsedSegmentChip
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    private var collapsedSegmentChip: some View {
        Button {
            isSegmentPanelExpanded = true
        } label: {
            Text(viewModel.distanceText ?? "0.00 km")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")
    }

    // 행 identity는 colorKey(생성 순번) — prepend로 인덱스가 밀려도 행 정체성과
    // scrollTo 대상이 안정적으로 유지된다 (MVP7 colorKey와 같은 원리).
    private struct PanelRow: Identifiable {
        let index: Int
        let colorKey: Int
        let segment: CourseSegment
        var id: Int { colorKey }
    }

    private var panelRows: [PanelRow] {
        let segments = viewModel.course?.segments ?? []
        let keys = viewModel.segmentColorKeys
        return segments.enumerated().map { index, segment in
            PanelRow(index: index, colorKey: index < keys.count ? keys[index] : index, segment: segment)
        }
    }

    private var expandedSegmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("구간")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    isSegmentPanelExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityIdentifier("coursePlanner.segmentPanel.collapse")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(panelRows) { row in
                            segmentRow(row)
                        }
                    }
                    .scrollTargetLayout()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        panelContentHeight = height
                    }
                }
                // ScrollView는 greedy — 내용이 적으면 내용 높이만큼, 많으면 지도 높이 40% 상한
                .frame(height: min(panelContentHeight, panelMaxListHeight))
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
        .padding(12)
        .frame(minWidth: 220)
    }

    private func segmentRow(_ row: PanelRow) -> some View {
        Button {
            viewModel.selectSegment(at: row.index)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                    .frame(width: 10, height: 10)
                Text("\(row.index + 1)")
                    .font(.caption.weight(.semibold))
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
    }

    // 새 구간 추가 시: 직전 최신 구간 근처를 보고 있을 때만 최신으로 스크롤 (채팅 앱 방식)
    private func autoScrollIfNearLatest(_ proxy: ScrollViewProxy, previousMaxKey: Int?) {
        let keys = viewModel.segmentColorKeys
        guard let maxKey = keys.max() else { return }
        let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
        let previousLatestIndex = previousMaxKey.flatMap { keys.firstIndex(of: $0) }
        guard SegmentPanelLogic.shouldAutoScroll(
            anchorIndex: anchorIndex, previousLatestIndex: previousLatestIndex
        ) else { return }
        withAnimation {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    // 재펼침 시: 보던 위치 복원, 없으면(첫 펼침/해당 행 삭제됨) 최신 구간으로
    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        let keys = viewModel.segmentColorKeys
        if let anchor = panelAnchorColorKey, keys.contains(anchor) {
            proxy.scrollTo(anchor, anchor: .center)
        } else if let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    private func cumulativeDistanceMeters(upTo index: Int) -> Double {
        guard let segments = viewModel.course?.segments, index < segments.count else { return 0 }
        return segments.prefix(through: index).reduce(0) { $0 + $1.distanceMeters }
    }
}
```

주의: 기존 `colorKey(at:)` 함수는 `PanelRow`로 흡수되어 삭제된다. 행 표시 내용(색 원, 순번, 거리, 누적)은 기존과 동일.

- [ ] **Step 3: 빌드 + 전체 테스트 + lint**

Run: Global Constraints의 3종 명령
Expected: 모두 PASS (이 Task는 뷰 레이아웃 변경이라 신규 유닛 테스트 없음 — 기존 테스트가 회귀 가드, 스펙의 테스트 절 참조)

- [ ] **Step 4: 시뮬레이터 스모크 확인**

XcodeBuildMCP로 앱 실행 → 탭으로 구간 3개 추가 → 패널 펼침 → 목록 표시·행 탭 시 하이라이트 동작 확인 (스크롤 체감·40% 상한은 실기기 QA 항목).

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 구간 패널 최대 높이 + 스크롤 + 채팅 앱 방식 자동 스크롤

- 지도 높이 40% 상한, 내용이 적으면 내용 높이만큼 (onGeometryChange 측정)
- 행 identity를 colorKey로 전환해 prepend에도 스크롤 대상 안정
- 최신 근처를 볼 때만 자동 스크롤, 재펼침 시 보던 위치 복원" -- Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift
```

---

### Task 3: 핀치 줌 네이티브 복원

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (삭제 위주)

**Interfaces:**
- Consumes: 없음
- Produces: 없음 (동작 변경: 그리기 모드에서 MKMapView 내장 핀치 줌 활성)

- [ ] **Step 1: 커스텀 핀치 코드 삭제**

`MapViewRepresentable.swift`에서 다음을 **삭제**:

1. `makeUIView`의 핀치 GR 등록 블록 전체:

```swift
        let pinchGR = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGR.isEnabled = false
        mapView.addGestureRecognizer(pinchGR)
        context.coordinator.pinchGestureRecognizer = pinchGR
```

2. `updateUIView` 모드 전환 블록의 두 줄:

```swift
            uiView.isZoomEnabled = !isDrawingMode
```

```swift
            context.coordinator.pinchGestureRecognizer?.isEnabled = isDrawingMode
```

(`isScrollEnabled`/`isPitchEnabled`/`isRotateEnabled` 토글과 2손가락 pan은 유지 — 스펙의 "유지하는 것")

3. Coordinator의 핀치 관련 전부:

```swift
        weak var pinchGestureRecognizer: UIPinchGestureRecognizer?
```

```swift
        private var pinchStartSpan: MKCoordinateSpan?
        private var pinchStartScale: CGFloat = 1.0
```

`// MARK: Pinch` 주석과 `handlePinch(_:)` 메서드 전체 (`@objc func handlePinch` ~ 닫는 중괄호).

- [ ] **Step 2: 빌드 + 전체 테스트 + lint**

Run: Global Constraints의 3종 명령
Expected: 모두 PASS. 삭제한 심볼 참조가 남아 있으면 빌드가 잡아준다 (제스처는 유닛 테스트 불가 — 스펙의 테스트 절).

- [ ] **Step 3: 시뮬레이터 스모크 확인**

XcodeBuildMCP로 앱 실행 → 그리기 모드 진입 → (시뮬레이터 핀치는 Option+드래그) 줌 동작 확인, 1손가락 그리기 정상 동작 확인. 두 손가락 사이 앵커 체감은 실기기 QA 항목.

- [ ] **Step 4: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 그리기 모드 핀치 줌을 MKMapView 내장 줌으로 복원

- 커스텀 UIPinchGestureRecognizer/handlePinch 삭제, isZoomEnabled 토글 제거
- drawGR.maximumNumberOfTouches = 1이라 2손가락 핀치와 충돌 없음
- 내장 줌은 두 손가락 사이 지점 앵커라 수제(중앙 고정)보다 체감 개선" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
```

---

### Task 4: 실기기 QA 체크리스트 작성 (MVP8 공통, 마일스톤 2 완료 후 제출)

**Files:**
- Create: `docs/qa/2026-XX-XX-mvp8-course-ux-device-checklist.md` (마일스톤 2 완료 시점의 날짜로)

- [ ] **Step 1: 이 마일스톤 몫의 QA 항목을 기록해 둔다**

스펙의 실기기 QA 절 그대로: 구간 10개 이상에서 패널 40% 상한+내부 스크롤 / 새 구간 추가 시 최신 구간 추적(prepend 포함) / 옛 구간을 보는 중엔 위치 유지 / 재펼침 위치 복원 / 그리기 중 두 손가락 핀치 앵커 체감 / 더블탭 줌과 그리기 간섭 여부 / 두 손가락 탭 줌아웃과 커스텀 pan 간섭 여부.

**추가 항목 (2026-07-02 브랜치 전체 리뷰에서 발견, plan-mandated 이슈로 사용자가 QA-우선 확인 결정):**
- **화면이 커서 40% 상한 안에 짧은 행이 7~8개 이상 보이는 기기(예: Pro Max급)에서, 최신 구간을 보고 있는 상태로 구간을 연속으로 여러 개 추가했을 때 매번 계속 최신을 따라가는지** (한 번만 따라가고 멈추지 않는지). 원인 가설: `autoScrollIfNearLatest`의 `scrollTo(maxKey, anchor: .bottom)`과 위치 추적용 `scrollPosition(id:anchor: .center)`의 앵커 기준이 달라, `tolerance: 3`(뷰포트 최대 6행 내외 가정) 전제가 큰 화면에서 깨지면 `shouldAutoScroll`이 조기에 `false`를 반환할 수 있음. 재현되면 `CoursePlannerPage+SegmentPanelComponent.swift`의 `scrollPosition`/`scrollTo` 앵커를 통일하는 수정이 필요 — 코드만으론 확신할 수 없어 QA 결과를 보고 판단하기로 함.

체크리스트 파일 자체는 마일스톤 2 완료 후 MVP8 전체 항목을 묶어 한 번에 작성·제출한다 (`docs/agent-rules/testing.md` 템플릿).

---

## Self-Review 결과

- 스펙 커버리지: 패널 상한(40%·onGeometryChange) → Task 2, 자동 스크롤 B 정책+순수 함수 → Task 1·2, 재펼침 복원 → Task 2, 핀치 복원 → Task 3, 실기기 QA → Task 4. 누락 없음.
- 타입 일관성: `SegmentPanelLogic` 시그니처가 Task 1 정의와 Task 2 호출에서 동일. `PanelRow.id = colorKey`와 `proxy.scrollTo(maxKey)` 대상 일치.
- 남은 리스크: `scrollPosition(id:anchor:)` 바인딩의 앵커 갱신 타이밍은 기기에서만 체감 확인 가능 → Task 4 QA 항목으로 커버.
