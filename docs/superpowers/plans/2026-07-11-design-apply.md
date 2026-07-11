# MVP12 design-apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the confirmed Trace design system (`docs/superpowers/specs/2026-07-10-design-direction-design.md`) to `CoursePlannerPage` and its sheets — tokens, top bar, FAB stack, bottom sheet, segment rows, map pins/polylines, course list, save/round-trip/redo — without changing any domain, persistence, or ViewModel behavior. Scope is **P1 only** (2026-07-11 kickoff decision, see Task 10 Step 4 for the recorded decision and deferred P2 backlog entries).

**Architecture:** Presentation-only refactor. A new `Trace/DesignSystem/` layer (tokens + shared components) is consumed by `Trace/Pages/CoursePlannerPage/*`. The existing `CoursePlannerPageViewModel` and everything under `Domain/`, `Application/`, `Infrastructure/` is untouched — every task's diff should be confined to `Trace/DesignSystem/`, `Trace/Pages/CoursePlannerPage/`, and `Trace/Assets.xcassets/`.

**Tech Stack:** SwiftUI, MapKit (`MKMapView`/`MKOverlayRenderer` via `MapViewRepresentable`), Asset Catalog dynamic colors (Any/Dark), XCTest/XCUITest, XcodeBuildMCP for simulator build/run/screenshot.

## Global Constraints

- **Keyboard-avoidance fix must stay at `body` top level.** `CoursePlannerPage.swift` currently applies `.ignoresSafeArea(.keyboard)` as the outermost modifier on `body` (after the save alert, before nothing else) — this is the MVP11 fix for the save-alert map-zoom-out bug (`docs/solutions/design-patterns/swiftui-keyboard-avoidance-shrinks-representable.md`). Every task that rewrites `body` must keep this modifier as the outermost one, applied after all `safeAreaInset`/`sheet`/`alert` modifiers, never nested inside an inset. Verify per task: open the save alert (tap "저장" flow), keyboard appears, map must **not** zoom out.
- **Domain/persistence/ViewModel are out of scope.** No task may add a public property or method to `CoursePlannerPageViewModel`, `PlannedCourse`, `CourseSegment`, `CourseRepositoryProtocol`, or any `Domain/`/`Application/`/`Infrastructure/` type. New view-only state (sheet expansion, pill visibility timers, etc.) is `@State` in the View layer only.
- **Preserve existing accessibility identifiers** when relocating a control (e.g. `coursePlanner.saveCourse`, `coursePlanner.undo`, `coursePlanner.redo`, `coursePlanner.clear`, `coursePlanner.courseList`, `coursePlanner.wholeCourseRoundTrip`, `coursePlanner.segmentPanel.*`, `coursePlanner.map`). Only `coursePlanner.map` is exercised by the current `TraceUITests`, but keeping the rest costs nothing and avoids future breakage.
- **`TraceTests` (2824 lines) must stay green, unmodified**, on every task — it is the proof that the ViewModel/domain layer is untouched.
- **Regression surface for every task's manual check** (from spec §6, restated so each task can self-verify a slice of it): tap/draw mode switching, undo/redo/clear, save → list → load → delete, per-segment round trip, whole-course round trip, error display, no map zoom-out during save alert.
- Minimum iOS version iOS 17+, Swift 6 language mode (`project-decisions.md`), SwiftUI by default, no new third-party dependencies.
- Baseline verification per `docs/agent-rules/testing.md`: fixed `$SIM_UDID` (iOS 26.5 simulator, chosen once at session start, never switched), `-parallel-testing-enabled NO` for tests, stamp files (`.git/trace-verify-{build,test,lint}.ok`) touched only after the corresponding command actually passes in the working tree.

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `Trace/Assets.xcassets/DesignSystem/*.colorset` | Create (19 sets) | Dynamic Any/Dark color tokens |
| `Trace/Assets.xcassets/AccentColor.colorset/Contents.json` | Modify | Repurposed as the `accent` token (teal/mint) |
| `Trace/DesignSystem/Tokens.swift` | Create | SwiftUI `Color` constants, typography, corner/size constants |
| `Trace/DesignSystem/Component/GlassIconButtonStyle.swift` | Create | Glass/accent circular button style (top bar, FAB) |
| `Trace/DesignSystem/Component/StatusChip.swift` | Create | Sheet header status chip (calculating/error/start-set/route) |
| `Trace/DesignSystem/Component/HintPill.swift` | Create | Top hint/error pill with 2.6s auto-dismiss |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` | Modify | Body shell: top bar inset, FAB overlay, bottom sheet inset, map pins colors |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift` | Modify | Becomes top bar (logo + tap/draw segment control + course list entry) |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift` | Delete | Superseded by `+BottomSheetComponent.swift` |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` | Create | Merged bottom sheet: grabber, distance headline, subtitle, status chip, save + whole-round-trip buttons, segment list |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+CourseListComponent.swift` | Modify | Restyled list sheet |
| `Trace/Pages/CoursePlannerPage/SegmentPalette.swift` | Modify | `color(at:)` resolves `Seg0`...`Seg5` dynamic assets |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` | Modify | Pin/polyline colors from tokens + 2-pass casing renderer |
| `docs/agent-rules/project-decisions.md` | Modify | Record `Trace/DesignSystem/` folder decision + P1-only scope decision |
| `docs/backlog.md` | Modify | Add 6 deferred P2 items |
| `docs/qa/2026-07-11-design-apply-device-checklist.md` | Create | Real-device QA checklist |

---

### Task 1: Design tokens (Asset Catalog + Tokens.swift)

**Files:**
- Create: `Trace/Assets.xcassets/DesignSystem/` (19 colorsets: `Ink`, `Ink2`, `Surface`, `Surface2`, `Border`, `Glass`, `GlassBorder`, `AccentInk`, `Danger`, `LocBlue`, `Grabber`, `MarkerFill`, `Seg0`...`Seg5`)
- Modify: `Trace/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Trace/DesignSystem/Tokens.swift`

**Interfaces:**
- Produces: `DesignToken.Color.{ink,ink2,surface,surface2,border,glass,glassBorder,accent,accentInk,danger,locBlue,grabber,markerFill}` (SwiftUI `Color`), `DesignToken.Corner.{chrome,sheetTop,row}`, `DesignToken.Size.{fab,topBarButton,screenMargin,sheetPadding}`, `DesignToken.Typography.{distanceHeadline,distanceUnit,segmentRowDistance,segmentRowTitle,segmentRowSubtitle,sectionLabel,chip,chipError,subtitle}` — every later task consumes these.

- [ ] **Step 1: Generate the 19 colorsets with a script**

Run from the repo root:

```bash
mkdir -p Trace/Assets.xcassets/DesignSystem
cd Trace/Assets.xcassets/DesignSystem

make_color() {
  local name=$1 lr=$2 lg=$3 lb=$4 la=$5 dr=$6 dg=$7 db=$8 da=$9
  mkdir -p "$name.colorset"
  cat > "$name.colorset/Contents.json" <<JSON
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "$la",
          "blue" : "0x$lb",
          "green" : "0x$lg",
          "red" : "0x$lr"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        { "appearance" : "luminosity", "value" : "dark" }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "$da",
          "blue" : "0x$db",
          "green" : "0x$dg",
          "red" : "0x$dr"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
}

make_color Ink         0C 1A 22 "1.000"  EA F2 FB "1.000"
make_color Ink2        5B 6B 78 "1.000"  65 77 8E "1.000"
make_color Surface     FF FF FF "0.740"  0A 11 1E "1.000"
make_color Surface2    06 B6 A4 "0.090"  14 1F 2F "1.000"
make_color Border      0C 1A 22 "0.090"  FF FF FF "0.070"
make_color Glass       FF FF FF "0.660"  0A 11 1E "0.720"
make_color GlassBorder FF FF FF "0.700"  00 E5 B0 "0.180"
make_color AccentInk   FF FF FF "1.000"  04 12 0E "1.000"
make_color Danger      F4 3F 5E "1.000"  FF 3B 6B "1.000"
make_color LocBlue     02 84 C7 "1.000"  38 BD F8 "1.000"
make_color Grabber     0C 1A 22 "0.200"  00 E5 B0 "0.400"
make_color MarkerFill  FF FF FF "1.000"  0A 14 20 "1.000"
make_color Seg0        06 B6 A4 "1.000"  00 E5 B0 "1.000"
make_color Seg1        0E 94 88 "1.000"  2F E0 C6 "1.000"
make_color Seg2        02 84 C7 "1.000"  38 BD F8 "1.000"
make_color Seg3        08 91 B2 "1.000"  5E EA D4 "1.000"
make_color Seg4        05 96 69 "1.000"  22 D3 EE "1.000"
make_color Seg5        0D 94 88 "1.000"  34 D3 99 "1.000"

cd -
```

Expected: `ls Trace/Assets.xcassets/DesignSystem` lists 19 `*.colorset` directories.

- [ ] **Step 2: Repurpose `AccentColor` as the `accent` token**

Replace `Trace/Assets.xcassets/AccentColor.colorset/Contents.json` with:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xA4",
          "green" : "0xB6",
          "red" : "0x06"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        { "appearance" : "luminosity", "value" : "dark" }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xB0",
          "green" : "0xE5",
          "red" : "0x00"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 3: Write `Trace/DesignSystem/Tokens.swift`**

```swift
import SwiftUI

enum DesignToken {
    enum Color {
        static let ink = SwiftUI.Color("Ink")
        static let ink2 = SwiftUI.Color("Ink2")
        static let surface = SwiftUI.Color("Surface")
        static let surface2 = SwiftUI.Color("Surface2")
        static let border = SwiftUI.Color("Border")
        static let glass = SwiftUI.Color("Glass")
        static let glassBorder = SwiftUI.Color("GlassBorder")
        static let accent = SwiftUI.Color("AccentColor")
        static let accentInk = SwiftUI.Color("AccentInk")
        static let danger = SwiftUI.Color("Danger")
        static let locBlue = SwiftUI.Color("LocBlue")
        static let grabber = SwiftUI.Color("Grabber")
        static let markerFill = SwiftUI.Color("MarkerFill")
    }

    enum Corner {
        static let chrome: CGFloat = 15
        static let sheetTop: CGFloat = 26
        static let row: CGFloat = 15
    }

    enum Size {
        static let fab: CGFloat = 44
        static let topBarButton: CGFloat = 42
        static let screenMargin: CGFloat = 14
        static let sheetPadding: CGFloat = 20
    }

    enum Typography {
        static let distanceHeadline = Font.system(size: 44, weight: .bold, design: .rounded)
        static let distanceUnit = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let segmentRowDistance = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let segmentRowTitle = Font.system(size: 15, weight: .semibold)
        static let segmentRowSubtitle = Font.system(size: 12.5, weight: .medium)
        static let sectionLabel = Font.system(size: 12, weight: .semibold)
        static let chip = Font.system(size: 13, weight: .semibold)
        static let chipError = Font.system(size: 13, weight: .bold)
        static let subtitle = Font.system(size: 13.5, weight: .medium)
    }
}
```

- [ ] **Step 4: BUILD**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Expected: build succeeds (no source references the new token yet, so this only proves the asset catalog and new file compile).

- [ ] **Step 5: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Assets.xcassets/DesignSystem Trace/Assets.xcassets/AccentColor.colorset/Contents.json Trace/DesignSystem/Tokens.swift
git commit -m "feat: design-apply 토큰(Asset Catalog 컬러 19종 + Tokens.swift) 추가"
```

Expected: TEST all green (unchanged suite), LINT clean.

---

### Task 2: Shared components (glass button style, status chip, hint pill)

**Files:**
- Create: `Trace/DesignSystem/Component/GlassIconButtonStyle.swift`
- Create: `Trace/DesignSystem/Component/StatusChip.swift`
- Create: `Trace/DesignSystem/Component/HintPill.swift`

**Interfaces:**
- Consumes: `DesignToken.Color.*`, `DesignToken.Typography.*` (Task 1)
- Produces: `ButtonStyle.glassIcon` / `.glassIcon(prominent:)`, `StatusChipKind` enum + `StatusChip(kind:)` view, `HintPill(text:isError:)` view with a `HintPill.autoDismissDelay: TimeInterval = 2.6` constant — Tasks 4–7 consume these exact names.

- [ ] **Step 1: `GlassIconButtonStyle.swift`**

```swift
import SwiftUI

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = DesignToken.Size.topBarButton
    var isProminent = false
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background {
                if isProminent {
                    Circle().fill(DesignToken.Color.accent)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(DesignToken.Color.glassBorder, lineWidth: 1))
                }
            }
            .foregroundStyle(isProminent ? DesignToken.Color.accentInk : DesignToken.Color.ink)
            .opacity(isDisabled ? 0.4 : (configuration.isPressed ? 0.7 : 1))
    }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { GlassIconButtonStyle() }

    static func glassIcon(prominent: Bool = false, disabled: Bool = false) -> GlassIconButtonStyle {
        GlassIconButtonStyle(isProminent: prominent, isDisabled: disabled)
    }
}
```

- [ ] **Step 2: `StatusChip.swift`**

```swift
import SwiftUI

enum StatusChipKind: Equatable {
    case calculating
    case error(String)
    case startSet
    case route(segmentLabel: String)
}

struct StatusChip: View {
    let kind: StatusChipKind

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .calculating:
                ProgressView().controlSize(.small)
                Text("계산 중")
            case .error(let message):
                Text(message)
            case .startSet:
                Circle().fill(DesignToken.Color.accent).frame(width: 6, height: 6)
                Text("출발 지정됨")
            case .route(let segmentLabel):
                Text(segmentLabel)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .font(isError ? DesignToken.Typography.chipError : DesignToken.Typography.chip)
        .foregroundStyle(isError ? .white : DesignToken.Color.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(isError ? DesignToken.Color.danger : DesignToken.Color.surface2))
    }

    private var isError: Bool {
        if case .error = kind { return true }
        return false
    }
}
```

- [ ] **Step 3: `HintPill.swift`**

```swift
import SwiftUI

struct HintPill: View {
    static let autoDismissDelay: TimeInterval = 2.6

    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(DesignToken.Typography.chip)
            .foregroundStyle(isError ? .white : DesignToken.Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if isError {
                    Capsule().fill(DesignToken.Color.danger)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }
}
```

- [ ] **Step 4: BUILD**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Expected: succeeds (components are not wired into any screen yet).

- [ ] **Step 5: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/DesignSystem/Component
git commit -m "feat: design-apply 공용 컴포넌트(GlassIconButtonStyle·StatusChip·HintPill) 추가"
```

---

### Task 3: Structural shell — top bar / FAB stack / merged bottom sheet (unstyled pass)

This is the highest-regression task: it moves button ownership and merges two separate structures (`statusPanel` bottom inset + `segmentPanel` top-trailing overlay) into one bottom-anchored sheet, **without changing visuals yet** (system colors/fonts are fine here — styling is Tasks 4–7). The goal is a single commit after which the app **builds and runs** with the new structure and all existing behavior intact.

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`
- Delete: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift`
- Create: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift`

**Interfaces:**
- Consumes: existing `CoursePlannerPageViewModel` API (`isDrawingMode`, `toggleDrawingMode()`, `canUndo`, `undo()`, `canRedo`, `redo()`, `clear()`, `canSaveCourse`, `isSavePromptPresented`, `presentCourseList()`, `insertWholeCourseRoundTrip()`, `canInsertWholeCourseRoundTrip`, `distanceText`, `isLoading`, `errorMessage`, `infoMessage`, `roundTripHintVisible`, `segmentColorKeys`, `course`, `selectedSegmentIndex`, `selectSegment(at:)`, `insertRoundTrip(afterColorKey:)`, `canInsertRoundTrip(afterColorKey:)`) — unchanged signatures.
- Produces: `CoursePlannerPage` gains `@State var isBottomSheetExpanded = false` (renamed from `isSegmentPanelExpanded` — same role, new name reflects the merged scope), keeps `panelContentHeight`, `panelMaxListHeight`, `panelAnchorColorKey`, `panelWasNearLatestAtCollapse` as-is. `var topBar: some View` (was `controls`), `var fabStack: some View` (new, replaces the bare recenter overlay), `var bottomSheet: some View` (was `segmentPanel` + `statusPanel` combined) — Tasks 4–7 style the insides of these three, not their plumbing.

- [ ] **Step 1: Rewrite `CoursePlannerPage+ControlsComponent.swift` as the top bar**

Only tap/draw toggle and course list entry remain here (logo badge is cosmetic and added in Task 4). Undo/redo/clear/save/whole-round-trip move out.

```swift
import SwiftUI

extension CoursePlannerPage {
    var topBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleDrawingMode() }
            } label: {
                Label(
                    viewModel.isDrawingMode ? "그리기" : "경로 찍기",
                    systemImage: viewModel.isDrawingMode ? "pencil.tip" : "mappin.and.ellipse"
                )
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            Spacer()

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityIdentifier("coursePlanner.courseList")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
```

- [ ] **Step 2: Delete `CoursePlannerPage+SegmentPanelComponent.swift`, create `CoursePlannerPage+BottomSheetComponent.swift`**

Move every function from the deleted file in unchanged (`PanelRow`, `panelRows`, `autoScrollIfNearLatest`, `restoreScrollPosition`, `cumulativeDistanceMeters`, `segmentRow`), and fold `statusPanel`'s content in as the sheet's always-visible header. Rename `isSegmentPanelExpanded` → `isBottomSheetExpanded` and `segmentPanel`/`collapsedSegmentChip`/`expandedSegmentList` → `bottomSheet`/`collapsedSheetHeader`/`expandedSheetBody` (structure identical, names reflect merged scope):

```swift
import SwiftUI

extension CoursePlannerPage {
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            if isBottomSheetExpanded {
                expandedSheetBody
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    // 기존 statusPanel 내용을 그대로 흡수 — 헤더는 항상 보이고, 탭하면 구간 리스트가 펼쳐진다.
    private var sheetHeader: some View {
        Button {
            isBottomSheetExpanded.toggle()
            // 펼침 시엔 expandedSheetBody의 ScrollViewReader.onAppear(restoreScrollPosition)가
            // 위치 복원을 전담하므로 여기선 접힘(collapse) 케이스만 기록한다.
            if !isBottomSheetExpanded {
                let keys = viewModel.segmentColorKeys
                let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
                let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
                panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                    anchorIndex: anchorIndex, previousLatestIndex: latestIndex
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isLoading {
                    Text("경로 계산 중")
                        .accessibilityIdentifier("coursePlanner.loading")
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("coursePlanner.error")
                } else if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("coursePlanner.info")
                } else if let distanceText = viewModel.distanceText {
                    HStack(spacing: 6) {
                        Text(distanceText)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("coursePlanner.distance")
                        if viewModel.roundTripHintVisible {
                            Text("· 출발핀을 탭하면 왕복 완성")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("coursePlanner.roundTripHint")
                        }
                    }
                } else {
                    Text(viewModel.isDrawingMode ? "경로를 그려주세요" : "지도에서 출발지를 선택하세요")
                        .accessibilityIdentifier("coursePlanner.prompt")
                }

                HStack(spacing: 12) {
                    Button { viewModel.isSavePromptPresented = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(!viewModel.canSaveCourse)
                    .accessibilityIdentifier("coursePlanner.saveCourse")

                    Button { viewModel.insertWholeCourseRoundTrip() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!viewModel.canInsertWholeCourseRoundTrip)
                    .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")
    }

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
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        panelContentHeight = height
                    }
                }
                .frame(height: min(panelContentHeight, panelMaxListHeight))
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .scrollPosition(id: $panelAnchorColorKey, anchor: .center)
                .onAppear { restoreScrollPosition(proxy) }
                .onChange(of: viewModel.segmentColorKeys.max()) { oldMax, newMax in
                    guard let newMax, newMax > (oldMax ?? Int.min) else { return }
                    autoScrollIfNearLatest(proxy, previousMaxKey: oldMax)
                }
            }
        }
        .frame(minWidth: 220)
    }

    private func segmentRow(_ row: PanelRow) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectSegment(at: row.index)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                        .frame(width: 10, height: 10)
                    Text("\(row.index + 1)")
                        .font(.caption.weight(.semibold))
                    if row.segment.isRoundTrip {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("왕복 구간")
                    }
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

            Button {
                viewModel.insertRoundTrip(afterColorKey: row.colorKey)
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInsertRoundTrip(afterColorKey: row.colorKey))
            .accessibilityIdentifier("coursePlanner.segmentPanel.roundTrip.\(row.index)")
        }
    }

    private func autoScrollIfNearLatest(_ proxy: ScrollViewProxy, previousMaxKey: Int?) {
        let keys = viewModel.segmentColorKeys
        guard let maxKey = keys.max() else { return }
        let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
        let previousLatestIndex = previousMaxKey.flatMap { keys.firstIndex(of: $0) }
        guard SegmentPanelLogic.shouldAutoScroll(
            anchorIndex: anchorIndex, previousLatestIndex: previousLatestIndex
        ) else { return }
        withAnimation { proxy.scrollTo(maxKey, anchor: .bottom) }
    }

    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        let keys = viewModel.segmentColorKeys
        if panelWasNearLatestAtCollapse, let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        } else if let anchor = panelAnchorColorKey, keys.contains(anchor) {
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

- [ ] **Step 3: Rewrite `CoursePlannerPage.swift` body/mapView to use the three new regions**

Rename the `@State` property, wire `topBar` into the top inset, move the bottom inset to `bottomSheet`, and fold undo/redo/clear into the existing bottom-trailing overlay (now `fabStack`) alongside recenter. Replace the whole `body`/`mapView`/`statusPanel` section with:

```swift
    @State private var cameraRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9784),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    @State private var currentStrokePoints: [CGPoint] = []
    @State var isBottomSheetExpanded = false
    @State var panelContentHeight: CGFloat = 0
    @State var panelMaxListHeight: CGFloat = 300
    @State var panelAnchorColorKey: Int?
    @State var panelWasNearLatestAtCollapse = true

    var body: some View {
        mapView
            .accessibilityIdentifier("coursePlanner.map")
            .safeAreaInset(edge: .top) {
                topBar
            }
            .safeAreaInset(edge: .bottom) {
                bottomSheet
            }
            .task {
                if let bounds = cameraStateStore.restore() {
                    cameraRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: bounds.latitude, longitude: bounds.longitude),
                        latitudinalMeters: bounds.latitudinalMeters,
                        longitudinalMeters: bounds.longitudinalMeters
                    )
                }
                await viewModel.bootstrapLocation()
                if let center = viewModel.initialCameraCoordinate {
                    cameraRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                }
            }
            .onChange(of: viewModel.selectedSegmentIndex) { _, newIndex in
                guard let newIndex,
                      let segments = viewModel.course?.segments,
                      newIndex < segments.count,
                      let region = regionFitting(segments[newIndex].coordinates) else { return }
                cameraRegion = region
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background { saveCameraPosition() }
            }
            .alert("위치 권한이 필요합니다", isPresented: $viewModel.showLocationDeniedAlert) {
                Button("설정으로 이동") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("닫기", role: .cancel) {}
            }
            .sheet(isPresented: $viewModel.isCourseListPresented) {
                courseListSheet
            }
            .alert("코스 이름", isPresented: $viewModel.isSavePromptPresented) {
                TextField("예: 한강 5km", text: $viewModel.courseNameInput)
                Button("저장") { Task { await viewModel.saveCurrentCourse() } }
                Button("취소", role: .cancel) { viewModel.courseNameInput = "" }
            } message: {
                Text("현재 코스를 저장합니다")
            }
            .alert(
                "지금 만들던 코스를 대체할까요?",
                isPresented: Binding(
                    get: { viewModel.pendingLoadCourse != nil },
                    set: { _ in }
                )
            ) {
                Button("대체", role: .destructive) { Task { await viewModel.confirmPendingLoad() } }
                Button("취소", role: .cancel) { viewModel.cancelPendingLoad() }
            } message: {
                Text("작업 중인 코스는 사라집니다")
            }
            // Global Constraint: keyboard-avoidance fix — 반드시 body 최상위, 다른 모든 모디파이어 뒤.
            .ignoresSafeArea(.keyboard)
    }

    private var mapView: some View {
        MapViewRepresentable(
            region: $cameraRegion,
            segments: viewModel.course?.segments ?? [],
            segmentColorKeys: viewModel.segmentColorKeys,
            pins: mapPins,
            selectedSegmentIndex: viewModel.selectedSegmentIndex,
            isDrawingMode: viewModel.isDrawingMode,
            waypoints: viewModel.waypointCoordinates.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            },
            onStrokeUpdate: { points in currentStrokePoints = points },
            onStrokeEnded: { stroke, startHit in Task { await viewModel.appendStroke(stroke, startPinHit: startHit) } },
            onMapTap: { coord, hitPin in Task { await viewModel.handleMapTap(at: coord, hitPin: hitPin) } },
            onPendingTap: { coord, hitPin in viewModel.pendingTapBegan(at: coord, hitPin: hitPin) },
            onPendingTapCancelled: { viewModel.pendingTapCancelled() }
        )
        .overlay {
            Canvas { context, _ in
                guard currentStrokePoints.count > 1 else { return }
                var path = Path()
                path.addLines(currentStrokePoints)
                context.stroke(path, with: .color(.orange), lineWidth: 4)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            fabStack
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelMaxListHeight = height * 0.4
        }
    }

    // Task 5에서 스타일링. 지금은 기존 되돌리기/앞으로/초기화/내 위치 버튼을 그대로 옮겨온 골격.
    private var fabStack: some View {
        VStack(spacing: 12) {
            Button { Task { await viewModel.undo() } } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("coursePlanner.undo")
            Button { viewModel.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!viewModel.canRedo)
                .accessibilityIdentifier("coursePlanner.redo")
            Button { viewModel.clear() } label: { Image(systemName: "xmark") }
                .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
                .accessibilityIdentifier("coursePlanner.clear")
            Button {
                Task {
                    if let location = await viewModel.recenterToCurrentLocation() {
                        cameraRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        )
                    }
                }
            } label: {
                Image(systemName: "location.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
```

Keep `mapPins`, `saveCameraPosition()`, `regionFitting(_:)` exactly as they are today (no change in this task).

- [ ] **Step 4: Remove the now-dead `statusPanel`** — delete the old `private var statusPanel` computed property from `CoursePlannerPage.swift` entirely (its content moved into `sheetHeader` in the new bottom sheet file).

- [ ] **Step 5: BUILD**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Expected: builds clean. If `isSegmentPanelExpanded` or `segmentPanel` are referenced anywhere else (grep first: `grep -rn "isSegmentPanelExpanded\|segmentPanel\b" Trace/`), update those call sites too — there should be none left outside the files touched above.

- [ ] **Step 6: Manual regression pass on simulator (this is the test cycle for a structural task — there is no new business logic to unit-test)**

Use XcodeBuildMCP: `build_run_sim`, then:
1. Tap twice on map → route appears in the new bottom sheet header (distance text). Tap the header → sheet expands to show segment rows. Tap again → collapses.
2. Add enough segments to require scrolling; while viewing an old segment, add a new one — panel should **not** auto-jump (verifies `panelWasNearLatestAtCollapse`/anchor logic survived the move).
3. Undo/redo/clear (now in `fabStack`, bottom-trailing over the map) all work identically to before.
4. Tap "저장" in the sheet header → name alert appears → keyboard shows → **map does not zoom out** (Global Constraint check).
5. Tap the course-list button (top bar) → list sheet opens, load/delete unchanged.

Expected: all five pass with no regressions.

- [ ] **Step 7: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift
git rm Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift
git commit -m "refactor: 탑바·FAB스택·바텀시트 구조로 재편(스타일 없음, 로직 보존)"
```

Expected: `TraceTests` full suite green — this is the proof the ViewModel/domain layer was untouched by the structural move.

---

### Task 4: Style the top bar

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`

**Interfaces:**
- Consumes: `DesignToken.*` (Task 1), `GlassIconButtonStyle` (Task 2), `viewModel.isDrawingMode`, `viewModel.toggleDrawingMode()`, `viewModel.presentCourseList()`.

- [ ] **Step 1: Replace `topBar` with the styled version** — logo badge, glass segmented tap/draw control, glass course-list button:

```swift
import SwiftUI

extension CoursePlannerPage {
    var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: DesignToken.Size.topBarButton, height: DesignToken.Size.topBarButton)
                .background(Circle().fill(DesignToken.Color.accent))

            Spacer()

            HStack(spacing: 4) {
                segmentToggleButton(title: "경로 찍기", systemImage: "mappin.and.ellipse", isActive: !viewModel.isDrawingMode)
                segmentToggleButton(title: "그리기", systemImage: "pencil.tip", isActive: viewModel.isDrawingMode)
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(DesignToken.Color.glassBorder, lineWidth: 1))
            )

            Spacer()

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(.glassIcon)
            .accessibilityIdentifier("coursePlanner.courseList")
        }
        .padding(.horizontal, DesignToken.Size.screenMargin)
        .padding(.top, 8)
    }

    private func segmentToggleButton(title: String, systemImage: String, isActive: Bool) -> some View {
        Button {
            // toggleDrawingMode()는 상태를 뒤집는 순수 토글이라, 이미 활성인 세그먼트를 다시
            // 탭하면 반대 모드로 넘어가 버린다 — 세그먼트 컨트롤은 활성 항목 재탭이 no-op이어야 한다.
            guard !isActive else { return }
            Task { await viewModel.toggleDrawingMode() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(DesignToken.Typography.chip)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isActive ? AnyShapeStyle(DesignToken.Color.accent) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(isActive ? DesignToken.Color.accentInk : DesignToken.Color.ink)
        }
        .accessibilityIdentifier("coursePlanner.drawToggle")
    }
}
```

Note: both segment buttons share the `coursePlanner.drawToggle` identifier by design (only one is meaningfully tappable to *change* mode at a time in the existing binary toggle model — this matches the pre-existing single-button behavior; do not split into two distinct ViewModel calls, `toggleDrawingMode()` remains the single entry point).

- [ ] **Step 2: BUILD, then screenshot check (light + dark)**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Use XcodeBuildMCP `build_run_sim` + `screenshot` once in light appearance and once with the simulator's appearance toggled to dark (Settings app or `xcrun simctl ui $SIM_UDID appearance dark`). Compare the top bar against spec §1.1/§2: accent circle logo, glass segmented control, glass folder button — both appearances should use the correct token colors (no hardcoded black/white leaking through).

- [ ] **Step 3: Manual regression** — tap/draw toggle still switches modes; **tapping the already-active segment (e.g. tapping "경로 찍기" while already in tap mode) must be a no-op, not flip into draw mode** — this is the idempotence check Step 1's `guard !isActive` exists for; course list button still opens the sheet; `coursePlanner.drawToggle` and `coursePlanner.courseList` identifiers still present (`grep -n "coursePlanner.drawToggle\|coursePlanner.courseList" Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`).

- [ ] **Step 4: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
git commit -m "style: 탑바에 디자인 토큰 적용(로고·세그먼트 필·코스목록 버튼)"
```

---

### Task 5: Style the FAB stack

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (`fabStack` only)

**Interfaces:**
- Consumes: `GlassIconButtonStyle` (Task 2), `DesignToken.Size.fab`, `isBottomSheetExpanded` (Task 3).

- [ ] **Step 1: Replace `fabStack`**

```swift
    private var fabStack: some View {
        VStack(spacing: 12) {
            Button { Task { await viewModel.undo() } } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.glassIcon(disabled: !viewModel.canUndo))
            .disabled(!viewModel.canUndo)
            .accessibilityIdentifier("coursePlanner.undo")

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.glassIcon(disabled: !viewModel.canRedo))
            .disabled(!viewModel.canRedo)
            .accessibilityIdentifier("coursePlanner.redo")

            Button { viewModel.clear() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glassIcon(disabled: viewModel.course == nil && viewModel.pendingTapStart == nil))
            .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
            .accessibilityIdentifier("coursePlanner.clear")

            Button {
                Task {
                    if let location = await viewModel.recenterToCurrentLocation() {
                        cameraRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        )
                    }
                }
            } label: {
                Image(systemName: "location.fill")
            }
            .buttonStyle(.glassIcon)
        }
        .frame(width: DesignToken.Size.fab)
        .padding(.trailing, DesignToken.Size.screenMargin)
        .padding(.bottom, 16)
        .opacity(isBottomSheetExpanded ? 0 : 1)
        .offset(x: isBottomSheetExpanded ? 24 : 0)
        .animation(.easeInOut(duration: 0.2), value: isBottomSheetExpanded)
        .allowsHitTesting(!isBottomSheetExpanded)
    }
```

- [ ] **Step 2: BUILD, then screenshot check** — FAB stack should render as 44×44 glass circles, redo dimmed to 40% opacity when `canRedo` is false, and the whole stack should fade + slide out when the bottom sheet is expanded.

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

- [ ] **Step 3: Manual regression** — undo/redo/clear/recenter still functionally work; expanding the bottom sheet hides the FAB stack and collapsing it brings it back; `coursePlanner.undo`/`.redo`/`.clear` identifiers intact.

- [ ] **Step 4: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "style: FAB 스택(되돌리기·앞으로·초기화·내 위치)에 유리 버튼 스타일 적용"
```

---

### Task 6: Style the bottom sheet header

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` (`sheetHeader` and the `bottomSheet` wrapper only)

**Interfaces:**
- Consumes: `DesignToken.*` (Task 1), `StatusChip`/`StatusChipKind` (Task 2), `HintPill` (Task 2).
- Produces: `sheetHeaderStatusChipKind: StatusChipKind?` computed helper — used only within this file.

- [ ] **Step 1: Replace `bottomSheet` and `sheetHeader`**

```swift
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DesignToken.Color.grabber)
                .frame(width: 38, height: 5)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)

            sheetHeader

            if isBottomSheetExpanded {
                expandedSheetBody
            }
        }
        .background {
            if isBottomSheetExpanded {
                RoundedRectangle(cornerRadius: DesignToken.Corner.sheetTop)
                    .fill(DesignToken.Color.surface)
            } else {
                RoundedRectangle(cornerRadius: DesignToken.Corner.sheetTop)
                    .fill(.regularMaterial)
            }
        }
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    private var sheetHeaderStatusChipKind: StatusChipKind? {
        if viewModel.isLoading { return .calculating }
        if let errorMessage = viewModel.errorMessage { return .error(errorMessage) }
        if viewModel.distanceText != nil {
            if let index = viewModel.selectedSegmentIndex {
                return .route(segmentLabel: "구간 \(index + 1)")
            }
            return .startSet
        }
        return nil
    }

    // SwiftUI는 Button 라벨 안에 또 다른 Button을 중첩하면 탭 판정이 불안정해진다(어느 쪽이
    // 반응할지 보장 안 됨). 그래서 "펼치기/접기" 탭 영역(거리·서브타이틀)과 "저장"/"전체 왕복"은
    // 하나의 Button label 안에 넣지 않고, 바깥 HStack의 형제(sibling)로 둔다.
    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                // 스펙 §1.4 시트 높이 전환(0.32s) — 펼침/접힘 모두 이 spring으로 애니메이션.
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isBottomSheetExpanded.toggle()
                }
                if !isBottomSheetExpanded {
                    let keys = viewModel.segmentColorKeys
                    let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
                    let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
                    panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                        anchorIndex: anchorIndex, previousLatestIndex: latestIndex
                    )
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let distanceText = viewModel.distanceText {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(distanceText)
                                .font(DesignToken.Typography.distanceHeadline)
                                .foregroundStyle(DesignToken.Color.ink)
                                .accessibilityIdentifier("coursePlanner.distance")
                            Text("km")
                                .font(DesignToken.Typography.distanceUnit)
                                .foregroundStyle(DesignToken.Color.ink2)
                        }
                    } else {
                        Text("0")
                            .font(DesignToken.Typography.distanceHeadline)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                    Text(subtitleText)
                        .font(DesignToken.Typography.subtitle)
                        .foregroundStyle(DesignToken.Color.ink2)
                        .accessibilityIdentifier(subtitleAccessibilityIdentifier)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if let kind = sheetHeaderStatusChipKind {
                    StatusChip(kind: kind)
                }
                HStack(spacing: 8) {
                    // "저장"은 텍스트+아이콘 캡슐이라 GlassIconButtonStyle(42×42 고정 프레임)에
                    // 억지로 끼우면 라벨이 잘린다 — 이 버튼만 인라인 Capsule 배경을 직접 사용한다.
                    Button { viewModel.isSavePromptPresented = true } label: {
                        Label("저장", systemImage: "bookmark.fill")
                            .font(DesignToken.Typography.chip)
                            .foregroundStyle(DesignToken.Color.accentInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DesignToken.Color.accent))
                    }
                    .disabled(!viewModel.canSaveCourse)
                    .opacity(viewModel.canSaveCourse ? 1 : 0.4)
                    .accessibilityIdentifier("coursePlanner.saveCourse")

                    Button { viewModel.insertWholeCourseRoundTrip() } label: {
                        Text("전체 왕복")
                            .font(DesignToken.Typography.sectionLabel)
                            .foregroundStyle(DesignToken.Color.accent)
                    }
                    .disabled(!viewModel.canInsertWholeCourseRoundTrip)
                    .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
                }
            }
        }
        .padding(.horizontal, DesignToken.Size.sheetPadding)
        .padding(.vertical, 16)
    }

    private var subtitleText: String {
        if viewModel.isLoading { return "경로를 계산하고 있어요" }
        if viewModel.errorMessage != nil { return "도로에 더 가까운 지점을 눌러보세요" }
        if let infoMessage = viewModel.infoMessage { return infoMessage }
        if viewModel.distanceText != nil { return "도보 기준 · 탭해서 이어 그리기" }
        if viewModel.isDrawingMode { return "지도에 손으로 경로를 그려보세요" }
        return "지도를 탭해 출발지를 선택하세요"
    }

    private var subtitleAccessibilityIdentifier: String {
        if viewModel.isLoading { return "coursePlanner.loading" }
        if viewModel.errorMessage != nil { return "coursePlanner.error" }
        if viewModel.infoMessage != nil { return "coursePlanner.info" }
        return "coursePlanner.prompt"
    }
```

Note: `GlassIconButtonStyle` is being applied here to non-circular, label-with-text buttons ("저장", "전체 왕복" sits outside it) — the style's `.frame(width:height:)` only self-applies inside `GlassIconButtonStyle.makeBody`, which forces a fixed square frame; since "저장" needs to fit a label, add `.fixedSize()` after the style (already included above) so the button doesn't get clipped to a 42×42 square. Verify visually in Step 2 — if the button looks wrong, it means `GlassIconButtonStyle` needs a `isCompact`/width-flexible variant; in that case fall back to a plain `Capsule().fill(DesignToken.Color.accent)` background inline instead of reusing the style for this one button, since forcing every future pill-shaped button through an icon-only style would be the wrong abstraction.

- [ ] **Step 2: BUILD, then screenshot check** — distance headline (44pt bold rounded + tabular "km" unit), subtitle per state (empty/start-set/drawing/calculating/route/error), status chip, save + whole-round-trip buttons in the header, grabber capsule at top.

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

Drive each subtitle state manually on the simulator (empty → tap once → tap twice → toggle draw mode → force an error by tapping open water) and confirm the copy in §2.1 of the spec appears verbatim for each.

- [ ] **Step 3: Manual regression** — save button still opens the name alert (and keyboard doesn't zoom the map — Global Constraint re-check since this task touches the header inside the sheet that sits in the bottom `safeAreaInset`); whole round trip button still inserts a round trip when enabled; **tapping "저장" or "전체 왕복" must only fire that button's own action and must NOT also expand/collapse the sheet** (this is what the sibling-not-nested restructure in Step 1 is for); tapping the distance/subtitle area still expands/collapses the sheet with a visible spring animation (not an instant snap).

- [ ] **Step 4: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift
git commit -m "style: 바텀시트 헤더(거리 헤드라인·서브타이틀·상태칩·저장/전체왕복)에 토큰 적용"
```

---

### Task 7: Style the segment list rows + top hint pill

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift` (`expandedSheetBody`/`segmentRow` only)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (add the top hint pill overlay)

**Interfaces:**
- Consumes: `DesignToken.*`, `HintPill` (Task 2), `SegmentPalette.color(at:)` (Task 8 will update its underlying colors, but the call site here is unchanged).

- [ ] **Step 1: Restyle `segmentRow`**

```swift
    private func segmentRow(_ row: PanelRow) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectSegment(at: row.index)
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                        .frame(width: 10, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("구간 \(row.index + 1)")
                            .font(DesignToken.Typography.segmentRowTitle)
                            .foregroundStyle(DesignToken.Color.ink)
                        Text(row.segment.isRoundTrip ? "왕복" : "지점 연결")
                            .font(DesignToken.Typography.segmentRowSubtitle)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0fm", row.segment.distanceMeters))
                            .font(DesignToken.Typography.segmentRowDistance)
                            .foregroundStyle(DesignToken.Color.ink)
                        Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: row.index) / 1000))
                            .font(.caption2)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DesignToken.Corner.row)
                        .fill(row.index == viewModel.selectedSegmentIndex ? DesignToken.Color.surface2 : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Corner.row)
                        .strokeBorder(
                            row.index == viewModel.selectedSegmentIndex ? DesignToken.Color.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(row.index)")

            Button {
                viewModel.insertRoundTrip(afterColorKey: row.colorKey)
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .font(.callout)
                    .foregroundStyle(DesignToken.Color.ink2)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInsertRoundTrip(afterColorKey: row.colorKey))
            .accessibilityIdentifier("coursePlanner.segmentPanel.roundTrip.\(row.index)")
        }
    }
```

- [ ] **Step 2: Add the top hint pill to `CoursePlannerPage.swift`**

Add supporting state near the other `@State` declarations, and a side-effect-free computed property for the raw hint text (`topHintText` only reports what *should* show; `isTopHintDismissed` — driven by `.onChange` below, never mutated inside the computed property — decides whether it's currently visible):

```swift
    @State private var isTopHintDismissed = false

    private var topHintText: String? {
        if let errorMessage = viewModel.errorMessage { return errorMessage }
        if viewModel.isDrawingMode && viewModel.course == nil { return "손으로 경로를 그려보세요" }
        return nil
    }
```

In `mapView`, add another overlay (order after the `fabStack` overlay, before `.onGeometryChange`) plus the `onChange`/`.task(id:)` pair that drives the 2.6s auto-dismiss. `.task(id: topHintText)` automatically cancels its previous sleep the moment `topHintText` changes to a new value (SwiftUI's built-in behavior for `id`-keyed tasks), so a second error arriving before the first one's 2.6s elapses restarts the clock instead of the first timer prematurely dismissing the second error:

```swift
        .overlay(alignment: .top) {
            if let hint = topHintText, !isTopHintDismissed {
                HintPill(text: hint, isError: viewModel.errorMessage != nil)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .onChange(of: topHintText) { _, _ in
            isTopHintDismissed = false
        }
        .task(id: topHintText) {
            guard topHintText != nil else { return }
            try? await Task.sleep(for: .seconds(HintPill.autoDismissDelay))
            isTopHintDismissed = true
        }
```

- [ ] **Step 3: BUILD, then screenshot check** — segment rows show the color bar/title/subtitle/distance layout, selected row shows accent border + tinted background, top hint pill appears for drawing-mode guidance and for errors, and the error pill disappears on its own after ~2.6s.

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

- [ ] **Step 4: Manual regression** — selecting a row still fits the camera to that segment (existing `onChange(of: viewModel.selectedSegmentIndex)`); per-row round trip button still inserts correctly; triggering a routing error (tap open water) shows the pill and it clears after ~2.6s without user action, and a *new* error while one is showing keeps it visible instead of leaving a stale dismissed state.

- [ ] **Step 5: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "style: 구간 리스트 행 + 상단 힌트 필(2.6초 자동 해제)에 토큰 적용"
```

---

### Task 8: Style map pins and polylines (+ casing)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/SegmentPalette.swift`
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (`mapPins` colors only)

**Interfaces:**
- Consumes: `Seg0`...`Seg5` dynamic assets (Task 1).
- Produces: `SegmentPalette.color(at:)` keeps its exact signature (`(Int) -> UIColor`), so no call site elsewhere needs to change.

- [ ] **Step 1: `SegmentPalette.swift` resolves dynamic assets**

```swift
import UIKit

enum SegmentPalette {
    static func color(at index: Int) -> UIColor {
        UIColor(named: "Seg\(index % 6)") ?? .systemBlue
    }
}
```

- [ ] **Step 2: Add a casing polyline type + renderer to `MapViewRepresentable.swift`**

Add next to `SegmentPolyline` (near line 37-41). It carries both `segmentIndex` (array-position, for selection matching — same reason `SegmentPolyline` carries it) and `colorKey` (color identity):

```swift
final class SegmentCasingPolyline: MKPolyline {
    var segmentIndex: Int = 0
    var colorKey: Int = 0
}
```

Add a dynamic casing color helper near the top of the file (below imports):

```swift
private let polylineCasingColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.35)
        : UIColor.white.withAlphaComponent(0.6)
}
```

In the overlay-rebuild loop (around line 241-258), add the casing overlay **before** the colored one so it renders underneath (MapKit draws later-added overlays on top, same convention already used for `WaypointDotsOverlay` — see the comment at line 82-85):

```swift
            for (index, segment) in segments.enumerated() {
                var coords = displayCoordinates[index].map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard coords.count >= 2 else { continue }
                let colorKey = index < segmentColorKeys.count ? segmentColorKeys[index] : index

                let casing = SegmentCasingPolyline(coordinates: &coords, count: coords.count)
                casing.segmentIndex = index
                casing.colorKey = colorKey
                uiView.addOverlay(casing)

                let polyline = SegmentPolyline(coordinates: &coords, count: coords.count)
                polyline.segmentIndex = index
                polyline.colorKey = colorKey
                uiView.addOverlay(polyline)

                let annotation = SegmentDistanceAnnotation(
                    coordinate: midpointAlongPath(coords),
                    distanceText: String(format: "%.0fm", segment.distanceMeters),
                    color: SegmentPalette.color(at: colorKey)
                )
                uiView.addAnnotation(annotation)
            }
```

Update the selection-refresh loop (around line 265-273) to also refresh casing width when a segment is selected (casing must stay proportionally wider than the stroke):

```swift
        if context.coordinator.lastSelectedIndex != selectedSegmentIndex {
            context.coordinator.lastSelectedIndex = selectedSegmentIndex
            for overlay in uiView.overlays {
                if let polyline = overlay as? SegmentPolyline,
                   let renderer = uiView.renderer(for: polyline) as? MKPolylineRenderer {
                    configureRenderer(renderer, segmentIndex: polyline.segmentIndex, colorKey: polyline.colorKey, selected: selectedSegmentIndex)
                    renderer.setNeedsDisplay()
                } else if let casing = overlay as? SegmentCasingPolyline,
                          let renderer = uiView.renderer(for: casing) as? MKPolylineRenderer {
                    renderer.lineWidth = casing.segmentIndex == selectedSegmentIndex ? 11 : 9.5
                    renderer.setNeedsDisplay()
                }
            }
        }
```

Update `configureRenderer` widths to match the spec (stroke 5.5 / casing 9.5, both scaled up slightly when selected — keep the existing selected/unselected ratio):

```swift
    private func configureRenderer(_ renderer: MKPolylineRenderer, segmentIndex: Int, colorKey: Int, selected: Int?) {
        renderer.strokeColor = SegmentPalette.color(at: colorKey)
        renderer.lineWidth = segmentIndex == selected ? 7 : 5.5
    }
```

Update `mapView(_:rendererFor:)` (around line 357-367) to build the casing renderer:

```swift
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dotsOverlay = overlay as? WaypointDotsOverlay {
                return WaypointDotsRenderer(overlay: dotsOverlay)
            }
            if let casing = overlay as? SegmentCasingPolyline {
                let renderer = MKPolylineRenderer(polyline: casing)
                renderer.strokeColor = polylineCasingColor
                renderer.lineWidth = casing.segmentIndex == parent.selectedSegmentIndex ? 11 : 9.5
                return renderer
            }
            guard let polyline = overlay as? SegmentPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            parent.configureRenderer(renderer, segmentIndex: polyline.segmentIndex, colorKey: polyline.colorKey, selected: parent.selectedSegmentIndex)
            return renderer
        }
```

- [ ] **Step 3: Update pin glyphs/colors in `CoursePlannerPage.swift`'s `mapPins`**

Replace the hardcoded `.systemGreen`/`.systemRed`/`.systemGray` with token-backed colors. Add near the top of `MapViewRepresentable.swift` (or reuse from `Tokens.swift` via a UIKit bridge) — simplest is to resolve directly by name at each pin construction site in `mapPins`:

```swift
    private var mapPins: [MapPin] {
        let accentUIColor = UIColor(named: "AccentColor") ?? .systemGreen
        let dangerUIColor = UIColor(named: "Danger") ?? .systemRed
        var pins: [MapPin] = []
        if let course = viewModel.course {
            if viewModel.isClosedCourse, let first = course.coordinates.first {
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    title: "출발/도착", color: accentUIColor, systemImage: "figure.run", role: .merged
                ))
            } else {
                if let first = course.coordinates.first {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                        title: "출발", color: accentUIColor, systemImage: "figure.run", role: .start
                    ))
                }
                if let last = course.coordinates.last, course.coordinates.count > 1 {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                        title: "도착", color: dangerUIColor, systemImage: "flag.checkered", role: .end
                    ))
                }
            }
        }
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발", color: accentUIColor, systemImage: "figure.run", role: .pendingStart
            ))
        }
        if viewModel.interactionMode == .tap, let pending = viewModel.pendingTapMarker {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: pending.latitude, longitude: pending.longitude),
                title: "확인 중", color: .systemGray, systemImage: "circle.dashed", role: .pendingStart
            ))
        }
        return pins
    }
```

(The neutral "확인 중" pending marker intentionally stays `.systemGray` — spec §2 only assigns tokens to start/end/current-location/error, not to this internal transient state.)

Also update the merged-pin badge color in `MapViewRepresentable.swift` (line ~393, `badge.backgroundColor = .systemRed`) to `UIColor(named: "Danger") ?? .systemRed`.

- [ ] **Step 4: Pin pop-in motion (spec §1.4) + best-effort current-location tint**

`MKMarkerAnnotationView.animatesWhenAdded` (default `true`) already gives the scale+fade pop MapKit calls for — make it explicit rather than relying on the undocumented default. In `Coordinator.mapView(_:viewFor:)` (`MapViewRepresentable.swift`, the `ColoredPinAnnotation` branch), add right after `view.collisionMode = .none`:

```swift
            view.animatesWhenAdded = true
```

For the current-location indicator, `showsUserLocation = true` (line 169) already gives MapKit's native pulsing dot; recoloring it to the `locBlue` token is best-effort since `MKUserLocationView` tinting is not a stable documented API across iOS versions. Add this branch at the top of `mapView(_:viewFor:)`, before the `SegmentDistanceAnnotation`/`ColoredPinAnnotation` checks:

```swift
            if annotation is MKUserLocation {
                return nil // 시스템 기본 파란 점 + 펄스 유지 — 재색상은 안정적 공개 API가 없어 보류
            }
```

This is a no-op today (returning `nil` already was the implicit behavior since `MKUserLocation` never matched the other `as?` casts), made explicit so a future reader doesn't wonder why the user dot isn't styled — it's a documented, deliberate scope trim, not an oversight.

- [ ] **Step 5: BUILD, then screenshot check** — polylines now show a visible casing (light: white halo; dark: soft black halo) under the colored stroke; start/end pins use the teal/mint accent and coral danger tokens in both appearances; selected segment's stroke+casing both thicken; adding a new pin visibly pops in rather than appearing instantly.

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

- [ ] **Step 6: Manual regression** — draw/tap a multi-segment course, confirm casing renders under every segment without covering the distance-label annotations (overlays stay below annotations per the existing z-order guarantee — no change needed there); select different segments and confirm both stroke and casing widths update; closed-course merged pin still shows the checkered badge in the danger color; newly placed pins pop in.

- [ ] **Step 7: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/SegmentPalette.swift Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "style: 지도 핀·폴리라인에 토큰 색상 + 케이싱(2-pass) 렌더링 적용"
```

---

### Task 9: Style the saved-course list sheet

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+CourseListComponent.swift`

**Interfaces:**
- Consumes: `DesignToken.*` (Task 1).

- [ ] **Step 1: Restyle `savedCourseRow` and the empty state**

```swift
import SwiftUI

extension CoursePlannerPage {
    var courseListSheet: some View {
        NavigationStack {
            Group {
                if viewModel.savedCourses.isEmpty {
                    ContentUnavailableView(
                        "저장한 코스가 없어요",
                        systemImage: "map",
                        description: Text("코스를 만들고 저장 버튼을 눌러보세요")
                    )
                } else {
                    savedCourseList
                }
            }
            .navigationTitle("저장한 코스")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var savedCourseList: some View {
        List {
            ForEach(viewModel.savedCourses) { course in
                Button {
                    Task { await viewModel.requestLoad(course) }
                } label: {
                    savedCourseRow(course)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("coursePlanner.savedCourse.\(course.name)")
            }
            .onDelete { indexSet in
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.savedCourses[first])
            }
        }
        .listStyle(.plain)
        .alert(
            "코스를 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteCourse != nil },
                set: { _ in }
            )
        ) {
            Button("삭제", role: .destructive) { Task { await viewModel.confirmPendingDelete() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingDelete() }
        } message: {
            Text(viewModel.pendingDeleteCourse.map { "'\($0.name)'은(는) 되돌릴 수 없습니다" } ?? "")
        }
    }

    private func savedCourseRow(_ course: SavedCourse) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: SegmentPalette.color(at: 0)))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(DesignToken.Typography.segmentRowTitle)
                    .foregroundStyle(DesignToken.Color.ink)
                Text("\(String(format: "%.2f", course.distanceMeters / 1000))km · \(course.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(DesignToken.Typography.segmentRowSubtitle)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: DesignToken.Corner.row).fill(Color.clear))
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: BUILD, then screenshot check** — row shows a left color bar, course name + "distance · date" subtitle, empty state shows "저장한 코스가 없어요" (spec §3.1 exact copy).

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

- [ ] **Step 3: Manual regression** — tap a row still loads the course (with the existing "지금 만들던 코스를 대체할까요?" confirmation if applicable); swipe-to-delete still shows the destructive confirmation alert; `coursePlanner.savedCourse.<name>` identifiers unchanged.

- [ ] **Step 4: TEST + LINT + stamp + commit**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+CourseListComponent.swift
git commit -m "style: 저장 코스 목록 sheet에 토큰 적용 + 빈 상태 문구 통일"
```

---

### Task 10: Final verification, decisions, backlog, real-device QA

**Files:**
- Modify: `docs/agent-rules/project-decisions.md`
- Modify: `docs/backlog.md`
- Create: `docs/qa/2026-07-11-design-apply-device-checklist.md`
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Full spec §6 acceptance pass on simulator**

Using XcodeBuildMCP `build_run_sim` + `screenshot`, in both light and dark appearance:
1. §2 components match the token table (top bar, FAB stack, sheet header, segment rows, pins, polylines+casing, status chip, hint pill).
2. No regression: tap/draw mode switch, undo/redo/clear, save → list → load → delete, per-segment round trip, whole-course round trip, error display (pill + sheet subtitle both show it).
3. Save alert does not zoom the map out (Global Constraint, re-verify one final time end-to-end).

- [ ] **Step 2: BUILD + full TEST + LINT**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
```

Expected: `TraceTests` full suite green (unchanged from before Task 1 — confirms domain/ViewModel untouched across all 9 style tasks), `TraceUITests` green, zero lint violations.

- [ ] **Step 3: Record the kickoff decisions in `project-decisions.md`**

Add under `## Current Defaults`:

```markdown
- 프레젠테이션 공용 레이어: `Trace/DesignSystem/`(Tokens.swift + Component/) 신설 — Pages와 별도 계층, 추후 모듈 분리 대상 (결정 2026-07-11, MVP12 design-apply). 상세: `docs/superpowers/specs/2026-07-10-design-direction-design.md` §4
- design-apply 범위: P1(토큰·탑바·FAB·시트·구간리스트·핀/폴리라인·저장/목록/왕복/redo 재배치)만 적용, P2(시트 드래그 리사이즈·지도 halo·km 마커·점선 애니메이션·다크 글로우·커스텀 저장 다이얼로그)는 백로그로 이연 (결정 2026-07-11, 킥오프 인터뷰). 상세: `docs/superpowers/specs/2026-07-10-design-direction-design.md` §5
```

- [ ] **Step 4: Add the 6 deferred P2 items to `docs/backlog.md`**

Append a new section:

```markdown
## MVP12 design-apply P2 (2026-07-11 킥오프에서 이연)

- [ ] **바텀시트 드래그로 높이 조절** — *what:* 탭 토글(P1)만으로는 손가락으로 시트를 끌어 임의 높이로 조절할 수 없음 / *trigger:* 실사용에서 탭 토글이 답답하다는 피드백이 나오면. `open`
- [ ] **구간 선택 시 지도 위 halo 하이라이트** — *what:* 리스트에서 구간 선택 시 지도의 해당 폴리라인에 후광 효과 추가 / *trigger:* 카메라 핏만으로 선택 구간 식별이 어렵다는 피드백이 나오면. `open`
- [ ] **km 마커 뱃지** — *what:* 경로를 따라 1km 간격 마커 표시 / *trigger:* 장거리 코스에서 거리 감각 파악이 어렵다는 피드백이 나오면. `open`
- [ ] **그리는 중 점선 행진 애니메이션** — *what:* 손으로 그리는 스트로크에 이동하는 점선 효과 / *trigger:* MapKit 오버레이로 구현 난이도가 있어 별도 검증 필요 — 시각적 임팩트 대비 우선순위 낮음. `open`
- [ ] **다크 모드 폴리라인 글로우** — *what:* 다크 테마에서 네온 민트 경로에 발광 효과 추가 / *trigger:* 다크 모드 실사용 피드백에서 케이싱만으로 부족하다는 의견이 나오면. `open`
- [ ] **커스텀 저장 다이얼로그** — *what:* 시스템 알럿 대신 디자인 시스템을 입힌 커스텀 다이얼로그 / *trigger:* 시스템 알럿이 브랜드 일관성을 크게 해친다는 판단이 서면. 킥오프에서 시스템 알럿 유지가 기본값으로 확정(2026-07-10 스펙 §3.2). `open`
```

- [ ] **Step 5: Update `docs/roadmap.md`** — mark `design-apply` `[x]` under MVP12 and note completion.

- [ ] **Step 6: Write the real-device QA checklist**

Save `docs/qa/2026-07-11-design-apply-device-checklist.md` following the scenario-card template in `docs/agent-rules/testing.md` (§ Real-Device Checklist Template) — cover: light/dark appearance switch while the app is open, save-alert keyboard behavior, tap/draw toggle feel, FAB stack tap targets at 44pt, sheet expand/collapse gesture feel, segment row selection, round trip buttons, saved-course list load/delete, and one "의도 일치" section asking whether the applied look matches the intended mockup.

- [ ] **Step 7: Commit**

```bash
git add docs/agent-rules/project-decisions.md docs/backlog.md docs/roadmap.md docs/qa/2026-07-11-design-apply-device-checklist.md
git commit -m "docs: design-apply 마일스톤 완료 — 결정 기록·P2 백로그 이연·실기기 체크리스트"
```

- [ ] **Step 8: Request branch review**

Use `superpowers:requesting-code-review` (or `/code-review`) for a full-branch diff review of `feature/design-apply` against `main`. After addressing findings, ask the user whether to integrate (`scripts/trace-integrate.sh`) — **push and integration require the user's approval**, never run them automatically.
