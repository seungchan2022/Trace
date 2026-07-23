# history-tab 구현 플랜 (MVP17 마일스톤 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록 탭을 신설해 러닝 집계(기간 합계·8주 추이·마지막 러닝)를 제공하고, 기존 기록 목록·상세를 그리로 옮기면서 러닝 탭에 이번 주 요약 줄을 심는다.

**Architecture:** 집계는 `Domain/RunTracking/Entity/RunStats.swift`의 순수 계산기 한 벌이
전담하고(기존 `RunSplitCalculator`·`RunPathSegmentsCalculator`와 같은 "결과 타입 +
`enum` 계산기 한 파일" 패턴), 기록 탭과 러닝 탭이 **같은 함수**를 소비한다. 입력은
`[SavedRunSummary]`뿐이라 무거운 blob을 열지 않는다. Domain은 3단 폴백의 결과까지만
정하고 한국어 화면 문구는 RunPage 포맷터가 맡는다. 기록 데이터의 소유권은
`DependencyContainer`로 올려 두 탭이 한 벌의 배열을 본다.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts(이 저장소 최초 도입), SwiftData(기존 저장소 경유), XCTest

**스펙:** `docs/superpowers/specs/2026-07-21-mvp17-run-history-kickoff-design.md`

**상태(2026-07-23):** 구현 미착수. 다음 세션은 아래 착수 전 사용자 확인 게이트에서
시작하고, 게이트 통과 뒤 Task 1로 간다.

## Global Constraints

- Swift 언어 모드 6. 격리 기본값은 **기본 nonisolated + 명시 `@MainActor`** — UI/상태 타입에만 `@MainActor`를 붙인다(`project-decisions.md`). Domain 순수 계산기에는 붙이지 않는다.
- 최소 iOS 17.0. 아이폰 **세로 전용** — `verticalSizeClass` 기반 가로 분기를 새로 만들지 않는다.
- 프레젠테이션은 MVVM + `@Observable`(`ObservableObject`/`@Published` 금지).
- 페이지 코드는 `Trace/Pages/{PageName}Page/`, 페이지 전용 서브뷰는 `UIComponent/{PageName}Page+{Role}Component.swift`.
- 색·폰트는 `DesignToken`을 사용한다. 레이아웃 간격·크기는 기존 러닝/기록 컴포넌트의
  수치를 재사용하고, 둘 이상의 새 화면에서 반복되는 의미 있는 값만 토큰으로 승격한다.
- **시뮬레이터는 세션 전체에서 단 하나만** 사용한다. iOS 18.x·26.0 런타임 금지(`@Observable` malloc 크래시) — iOS **26.5**로 고정. `id=$SIM_UDID` 형식만 쓰고 `name=`은 금지.
- 테스트는 반드시 raw bash `xcodebuild ... -parallel-testing-enabled NO test`로 실행한다. XcodeBuildMCP의 `test_sim` 사용 금지(병렬 복제로 행 발생).
- 커밋 전 **빌드·테스트·린트 3종 통과** + 검증 스탬프 갱신 필수(`.git/trace-verify-{build,test,lint}.ok`).
- 스테이징은 경로 명시. `git add -A`/`git add .` 금지. 커밋은 `scripts/trace-commit.sh` 사용 권장.
- 브랜치: `feature/mvp17-history-tab` (`main`에서 분기). **push 금지.**

### 검증 명령 (모든 태스크 공통)

```bash
# SIM_UDID는 docs/agent-rules/testing.md "기준 시뮬레이터 선택 절차"로 고정한 값
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```

---

## 착수 전 사용자 확인 게이트

먼저 이 문서가 있는 `docs/mvp17-kickoff` 브랜치가 `main`에 통합됐는지 확인한다. 아직
통합 전이면 `main`에서 구현 브랜치를 새로 만들지 않는다. 문서 통합을 먼저 끝낸 뒤
`main`에서 `feature/mvp17-history-tab`을 만들어야 같은 작업이 두 갈래로 갈라지지 않는다.

킥오프 스펙 §3.1의 반증 확인을 구현보다 먼저 수행한다. 실제 기기의 현재 저장 기록 수와
최근 8주 중 기록이 있는 주 수를 사용자에게 확인해 보고한다. 이 값은 저장소나 시뮬레이터
데이터로 추정하지 않는다.

- [ ] 실제 저장 기록 수와 최근 8주 활성 주 수를 사용자에게 확인해 실행 로그에 남긴다.
- [ ] 값이 예상보다 훨씬 적어 집계 화면이 대부분 비어 보일 가능성이 있으면 구현을 시작하지
  않고, 스펙 §2.2의 반증 신호로 볼지 사용자에게 확인한다.
- [ ] 사용자가 현재 데이터량을 인지한 상태에서 진행을 확인하면 Task 1로 간다.

이 게이트는 제품 방향을 다시 브레인스토밍하는 단계가 아니다. 이미 확정한 반증 조건을
구현 전에 한 번 확인해, 되돌리기 비용이 가장 큰 3탭 이사를 무근거로 시작하지 않기 위한
체크포인트다.

---

## File Structure

| 파일 | 책임 | 태스크 |
|---|---|---|
| `Trace/App/AppTab.swift` | 탭 열거 — `history` 추가 | 1 |
| `Trace/App/RootView.swift` | 탭 호스팅 — 기록 탭 마운트, 공유 스토어 주입 | 1, 5 |
| `Trace/App/DependencyContainer.swift` | 기록 스토어 소유권 | 5 |
| `Trace/DesignSystem/Formatter/RunDurationFormatter.swift` | **이동** — 러닝·기록 공용 시간 문구 | 5 |
| `Trace/DesignSystem/Formatter/RunGoalFormatter.swift` | **이동** — 러닝·기록 공용 목표 문구 | 5 |
| `Trace/DesignSystem/Formatter/RunPaceFormatter.swift` | **이동** — 러닝·기록 공용 페이스 문구 | 5 |
| `Trace/Domain/RunTracking/Entity/RunStats.swift` | **신설** — 결과 타입 3종 + `enum RunStatsCalculator` | 2 |
| `Trace/Pages/HistoryPage/HistoryPage.swift` | **신설** — 기록 탭 루트(대시보드 + 목록) | 3, 4, 5 |
| `Trace/Pages/HistoryPage/HistoryPageViewModel.swift` | **신설** — 기간 선택 상태 + 집계 파생 | 3 |
| `Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift` | **신설** — 세그먼트·숫자·그래프 | 3, 4 |
| `Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift` | **이동·개명** — 기록 행·상세 | 5 |
| `Trace/Pages/RunPage/RunPage.swift` | 기록 버튼·`NavigationStack` 제거, 요약 줄 추가 | 5, 6 |
| `Trace/Pages/RunPage/RunIdleSummaryFormatter.swift` | **신설** — 3단 폴백 결과의 한국어 화면 문구 | 6 |
| `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` | **이동 원본** — Task 5에서 HistoryPage 폴더로 이동 | 5 |
| `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` | 저장 중 요약 닫기 경합 차단 | 6 |
| `TraceTests/AppTabTests.swift` | 3탭 단언으로 갱신 | 1 |
| `TraceTests/RunStatsCalculatorTests.swift` | **신설** — 계산기 경계 테스트 | 2 |
| `TraceTests/HistoryPageViewModelTests.swift` | **신설** — 기간 전환·빈 상태 | 3 |
| `TraceTests/RunIdleSummaryFormatterTests.swift` | **신설** — 러닝 대기 화면 문구 테스트 | 6 |

---

## Task 1: 3탭 구조 + 렌더링 확인

**스펙 §5.1이 이 태스크를 첫 번째로 요구한다** — 이 저장소는 탭바·안전영역 회귀 이력이 있어(MVP16 갇힘 버그, 시트 예산 이중 차감), **콘텐츠를 얹기 전에** 3탭이 멀쩡히 그려지는지부터 확인한다. 대시보드까지 지어놓고 발견하면 원인 분리가 어려워진다.

**Files:**
- Modify: `Trace/App/AppTab.swift`
- Modify: `Trace/App/RootView.swift:40-47`
- Modify: `TraceTests/AppTabTests.swift:5-11`

**Interfaces:**
- Consumes: 없음(첫 태스크)
- Produces: `AppTab.history` 케이스. Task 3·5가 `RootView`의 기록 탭 슬롯에 실제 페이지를 꽂는다.

- [ ] **Step 1: 기존 2탭 테스트의 기준선 통과를 먼저 확인한다**

`TraceTests/AppTabTests.swift:6`이 `AppTab.allCases == [.course, .run]`을 단언하므로, 케이스를 추가하면 **반드시 실패한다.** 이것이 이 태스크의 첫 신호다.

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/AppTabTests test
```
Expected: PASS (아직 케이스를 안 넣었으므로 현재는 통과 — 기준선 확인)

- [ ] **Step 2: 테스트를 3탭 기대값으로 먼저 고친다 (실패 유도)**

`TraceTests/AppTabTests.swift`의 첫 테스트를 통째로 교체:

```swift
    func test_탭은_코스_러닝_기록_순서로_세_개다() {
        XCTAssertEqual(AppTab.allCases, [.course, .run, .history])
        XCTAssertEqual(AppTab.course.title, "코스")
        XCTAssertEqual(AppTab.run.title, "러닝")
        XCTAssertEqual(AppTab.history.title, "기록")
        XCTAssertEqual(AppTab.course.systemImage, "map")
        XCTAssertEqual(AppTab.run.systemImage, "figure.run")
        XCTAssertEqual(AppTab.history.systemImage, "chart.bar.xaxis")
    }
```

- [ ] **Step 3: 테스트가 실패하는 것을 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/AppTabTests test
```
Expected: 컴파일 실패 — `type 'AppTab' has no member 'history'`

- [ ] **Step 4: `AppTab`에 케이스 추가**

`Trace/App/AppTab.swift`를 다음으로 교체(기존 `isTabBarHidden`은 그대로 둔다 — `runState != .idle` 한 줄이라 탭 수와 무관하게 동작한다):

```swift
import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case course
    case run
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course: return "코스"
        case .run: return "러닝"
        case .history: return "기록"
        }
    }

    var systemImage: String {
        switch self {
        case .course: return "map"
        case .run: return "figure.run"
        case .history: return "chart.bar.xaxis"
        }
    }

    // 킥오프 §2.2: 러닝 플로우(시작~요약 닫기 전) 동안 앱 내 탭 전환 진입점 자체를 제거한다.
    // summary도 숨김 — 요약 화면을 닫아 idle로 돌아와야 탭바가 복귀한다.
    // 탭이 몇 개든 이 판정은 세션 상태 하나로만 결정된다.
    static func isTabBarHidden(runState: RunSession.State) -> Bool {
        runState != .idle
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/AppTabTests test
```
Expected: PASS (2 tests)

- [ ] **Step 6: `RootView`에 임시 플레이스홀더를 꽂는다**

`Trace/App/RootView.swift`의 `ZStack` 안, `RunPage` 블록 **뒤에** 추가:

```swift
                    // Task 3에서 HistoryPage로 교체된다. 지금은 3탭 렌더링만 확인한다.
                    DesignToken.Color.surface2
                        .ignoresSafeArea()
                        .overlay {
                            Text("기록")
                                .font(DesignToken.Typography.runSecondaryStat)
                                .foregroundStyle(DesignToken.Color.ink)
                        }
                        .opacity(selectedTab == .history ? 1 : 0)
                        .allowsHitTesting(selectedTab == .history)
                        .accessibilityHidden(selectedTab != .history)
```

- [ ] **Step 7: 빌드 + 전체 테스트 + 린트**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```
Expected: 빌드 성공 / 전체 테스트 통과(착수 전 기준선 348개: 단위 344 + UI 4) / 린트 에러 0

- [ ] **Step 8: 시뮬레이터로 3탭 렌더링을 눈으로 확인 (이 태스크의 핵심)**

XcodeBuildMCP로 앱을 실행하고 스크린샷을 찍어 다음을 확인한다:

1. 탭바에 **3개 탭이 균등 분할**되어 있고 라벨(코스/러닝/기록)이 잘리지 않는다
2. 기록 탭을 탭하면 플레이스홀더 화면으로 전환된다
3. 탭바가 홈 인디케이터 영역까지 배경을 확장하고, 다이내믹 아일랜드를 침범하지 않는다
4. 러닝 탭에서 시작 → 카운트다운 진입 시 **탭바가 사라진다**(3탭이어도 `isTabBarHidden` 정상 동작)

**실패 시:** `TraceTabBar`는 `ForEach(AppTab.allCases)` + `.frame(maxWidth: .infinity)` 균등
분할이라 구조적으로는 안전하다. 라벨 잘림·안전영역 침범이 보이면 공유 타이포그래피 값을
추측으로 바꾸지 말고 `superpowers:systematic-debugging`으로 `TraceTabBar`의 실제 폭·높이
원인을 먼저 확정한다. 수정 후 위 4개 항목을 전부 다시 확인하며, **여기서 막히면 다음
태스크로 넘어가지 않는다.**

- [ ] **Step 9: 검증 스탬프 갱신 후 커밋**

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 앱 루트에 기록 탭 추가

- AppTab에 history 케이스를 넣어 코스·러닝·기록 3탭 구조로 확장한다
- 탭바 숨김 판정(isTabBarHidden)은 세션 상태 한 줄이라 탭 수와 무관하게 그대로 동작한다
- 콘텐츠를 얹기 전에 3탭 렌더링을 먼저 확인한다(스펙 5.1 — 탭바 회귀 이력)
- 페이지 본체는 후속 태스크에서 채우고 지금은 플레이스홀더를 둔다" \
  -- Trace/App/AppTab.swift Trace/App/RootView.swift TraceTests/AppTabTests.swift
```

---

## Task 2: `RunStats` 순수 계산기

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunStats.swift`
- Test: `TraceTests/RunStatsCalculatorTests.swift`

**Interfaces:**
- Consumes: `SavedRunSummary`(`Trace/Domain/RunTracking/Entity/SavedRun.swift:5` — `id`, `startedAt`, `distanceMeters`, `duration`, `elevationGainMeters`, 파생 `averagePaceSecondsPerKm`)
- Produces:
  - `struct RunStats { totalDistanceMeters: Double, runCount: Int, totalDuration: TimeInterval }`
  - `struct RunWeeklyBar { weekStart: Date, distanceMeters: Double }`
  - `struct LastRunSummary { distanceMeters: Double, daysAgo: Int }`
  - `enum RunStatsPeriod { case thisWeek, thisMonth, all }`
  - `RunStatsCalculator.stats(summaries:period:now:calendar:) -> RunStats`
  - `RunStatsCalculator.weeklyBars(summaries:weekCount:now:calendar:) -> [RunWeeklyBar]`
  - `RunStatsCalculator.lastRun(summaries:now:calendar:) -> LastRunSummary?`

**설계 주의 — `now`와 `calendar`를 주입받는다.** 내부에서 `Date()`나 `Calendar.current`를 직접 부르면 테스트가 "오늘이 무슨 요일인가"에 따라 붙었다 떨어졌다 한다. 호출부(뷰모델)가 `Calendar.current`와 `Date()`를 넘기고, 테스트는 고정값을 넘긴다.

- [ ] **Step 1: 실패하는 테스트를 먼저 쓴다**

Create `TraceTests/RunStatsCalculatorTests.swift`:

```swift
import XCTest
@testable import Trace

final class RunStatsCalculatorTests: XCTestCase {
    // 결정적 테스트를 위해 달력과 기준 시각을 고정한다.
    // 2026-07-22(수) 12:00 KST. 일요일 시작 달력에서 이번 주는 07-19(일)~07-25(토).
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        cal.firstWeekday = 1 // 일요일 시작 — 한국 로케일 기본값(스펙 4.2)
        return cal
    }()

    private let now = Date(timeIntervalSince1970: 1_784_689_200) // 2026-07-22 12:00 KST

    private func summary(daysAgo: Int, distanceMeters: Double, duration: TimeInterval) -> SavedRunSummary {
        summary(
            startedAt: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            distanceMeters: distanceMeters,
            duration: duration
        )
    }

    private func summary(
        startedAt: Date,
        distanceMeters: Double,
        duration: TimeInterval
    ) -> SavedRunSummary {
        SavedRunSummary(
            id: UUID(),
            startedAt: startedAt,
            distanceMeters: distanceMeters,
            duration: duration,
            elevationGainMeters: 0
        )
    }

    // MARK: - 기간 합계

    func test_빈_배열이면_전부_0이다() {
        let stats = RunStatsCalculator.stats(
            summaries: [], period: .thisWeek, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 0)
        XCTAssertEqual(stats.totalDistanceMeters, 0)
        XCTAssertEqual(stats.totalDuration, 0)
    }

    func test_이번_주는_일요일_시작부터_토요일_끝까지다() throws {
        let saturdayEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 25, hour: 23, minute: 59
        )))
        let sundayStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 19, hour: 0, minute: 0
        )))
        let previousSaturday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 23, minute: 59
        )))
        let summaries = [
            summary(startedAt: sundayStart, distanceMeters: 5000, duration: 1800),
            summary(startedAt: saturdayEnd, distanceMeters: 3000, duration: 1200),
            summary(startedAt: previousSaturday, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisWeek, now: saturdayEnd, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 8000)
        XCTAssertEqual(stats.totalDuration, 3000)
    }

    func test_이번_달은_1일_시작부터_말일_끝까지다() throws {
        let julyEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 31, hour: 23, minute: 59
        )))
        let julyStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 0, minute: 0
        )))
        let juneEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 30, hour: 23, minute: 59
        )))
        let summaries = [
            summary(startedAt: julyStart, distanceMeters: 5000, duration: 1800),
            summary(startedAt: julyEnd, distanceMeters: 3000, duration: 1200),
            summary(startedAt: juneEnd, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisMonth, now: julyEnd, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 8000)
    }

    func test_전체는_아무것도_거르지_않는다() {
        let summaries = [
            summary(daysAgo: 3, distanceMeters: 5000, duration: 1800),
            summary(daysAgo: 400, distanceMeters: 9000, duration: 3600)
        ]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .all, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 14000)
    }

    func test_자정을_넘긴_러닝은_시작_시각_기준으로_분류된다() {
        // 러닝 종료가 다음 날이어도 startedAt이 속한 기간으로 센다.
        // SavedRunSummary가 기간 분류에 필요한 startedAt만 갖는다.
        let summaries = [summary(daysAgo: 3, distanceMeters: 5000, duration: 7 * 3600)]
        let stats = RunStatsCalculator.stats(
            summaries: summaries, period: .thisWeek, now: now, calendar: calendar
        )
        XCTAssertEqual(stats.runCount, 1)
    }

    // MARK: - 8주 추이

    func test_주간_막대는_안_뛴_주도_0으로_채워_항상_요청한_개수만큼_나온다() {
        // 스펙 6.2: 공백을 숨기지 않는다 — 막대 개수가 데이터에 따라 흔들리면 안 된다
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [summary(daysAgo: 3, distanceMeters: 5000, duration: 1800)],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.count, 8)
        XCTAssertEqual(bars.filter { $0.distanceMeters == 0 }.count, 7)
    }

    func test_주간_막대는_과거에서_현재_순으로_정렬된다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [], weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars, bars.sorted { $0.weekStart < $1.weekStart })
    }

    func test_마지막_막대가_이번_주다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [summary(daysAgo: 3, distanceMeters: 5000, duration: 1800)],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.last?.distanceMeters, 5000)
    }

    func test_같은_주의_여러_러닝은_한_막대로_합산된다() {
        let bars = RunStatsCalculator.weeklyBars(
            summaries: [
                summary(daysAgo: 3, distanceMeters: 5000, duration: 1800),
                summary(daysAgo: 2, distanceMeters: 3000, duration: 1200)
            ],
            weekCount: 8, now: now, calendar: calendar
        )
        XCTAssertEqual(bars.last?.distanceMeters, 8000)
    }

    // MARK: - 마지막 러닝

    func test_기록이_없으면_마지막_러닝은_nil이다() {
        XCTAssertNil(RunStatsCalculator.lastRun(summaries: [], now: now, calendar: calendar))
    }

    func test_마지막_러닝은_가장_최근_기록이고_경과일을_함께_준다() {
        let summaries = [
            summary(daysAgo: 10, distanceMeters: 9000, duration: 3600),
            summary(daysAgo: 3, distanceMeters: 5200, duration: 1800)
        ]
        let last = RunStatsCalculator.lastRun(summaries: summaries, now: now, calendar: calendar)
        XCTAssertEqual(last?.distanceMeters, 5200)
        XCTAssertEqual(last?.daysAgo, 3)
    }

    func test_경과일은_달력_날짜_차이지_24시간_단위가_아니다() {
        // 어제 23:00에 뛰고 오늘 00:30에 보면 경과 시간은 1.5시간이지만
        // "어제"(1일 전)여야 한다.
        let yesterdayLate = calendar.date(byAdding: .hour, value: -13, to: now) ?? now
        let summaries = [SavedRunSummary(
            id: UUID(), startedAt: yesterdayLate,
            distanceMeters: 5000, duration: 1800, elevationGainMeters: 0
        )]
        let last = RunStatsCalculator.lastRun(summaries: summaries, now: now, calendar: calendar)
        XCTAssertEqual(last?.daysAgo, 1)
    }
}
```

> **Step 1 주의:** `1_784_689_200`은 `Asia/Seoul` 기준 2026-07-22 12:00이다.
> 13시간 전은 07-21 23:00이므로 마지막 테스트의 정답은 **1일 전**이다. 기대값을 실행
> 결과에 맞춰 바꾸지 말고, 실패하면 주입한 달력·타임존과 구현을 확인한다.

- [ ] **Step 2: 테스트가 실패하는 것을 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunStatsCalculatorTests test
```
Expected: 컴파일 실패 — `cannot find 'RunStatsCalculator' in scope`

- [ ] **Step 3: 계산기 구현**

Create `Trace/Domain/RunTracking/Entity/RunStats.swift`:

```swift
import Foundation

/// 기간 집계 결과.
/// 기록 탭 대시보드와 러닝 탭 요약 줄이 같은 타입을 소비한다(스펙 §4).
struct RunStats: Equatable, Sendable {
    let totalDistanceMeters: Double
    let runCount: Int
    let totalDuration: TimeInterval

    static let empty = RunStats(totalDistanceMeters: 0, runCount: 0, totalDuration: 0)
}

/// 주간 추이 막대 하나. `weekStart`는 달력의 주 시작일(스펙 §4.2 — 로케일 기본값).
struct RunWeeklyBar: Equatable, Sendable {
    let weekStart: Date
    let distanceMeters: Double
}

/// 가장 최근 러닝 — 이번 주 0회일 때 러닝 탭 요약 줄이 폴백으로 쓴다(스펙 §7.1).
struct LastRunSummary: Equatable, Sendable {
    let distanceMeters: Double
    /// 달력 날짜 차이. 오늘이면 0, 어제면 1.
    let daysAgo: Int
}

enum RunStatsPeriod: CaseIterable, Hashable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case all

    var id: Self { self }
}

/// `[SavedRunSummary]`만 입력받는 순수 계산기 — 무거운 blob을 열지 않는다.
/// `now`/`calendar`를 주입받는 이유: 내부에서 `Date()`를 부르면 테스트가 실행 시점에
/// 따라 결과가 달라진다. 호출부가 `Date()`와 `Calendar.current`를 넘긴다.
enum RunStatsCalculator {
    static func stats(
        summaries: [SavedRunSummary],
        period: RunStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> RunStats {
        let filtered = summaries.filter { isInPeriod($0.startedAt, period: period, now: now, calendar: calendar) }
        guard filtered.isEmpty == false else { return .empty }
        return RunStats(
            totalDistanceMeters: filtered.reduce(0) { $0 + $1.distanceMeters },
            runCount: filtered.count,
            totalDuration: filtered.reduce(0) { $0 + $1.duration }
        )
    }

    /// 최근 `weekCount`주의 거리 합.
    /// 기록이 없는 주도 0으로 채워 항상 `weekCount`개를 돌려준다.
    /// 막대 개수가 데이터에 따라 흔들리면 화면 구조가 불안정해진다(스펙 §6.2).
    static func weeklyBars(
        summaries: [SavedRunSummary],
        weekCount: Int,
        now: Date,
        calendar: Calendar
    ) -> [RunWeeklyBar] {
        guard weekCount > 0, let thisWeekStart = weekStart(of: now, calendar: calendar) else { return [] }

        let starts: [Date] = (0..<weekCount).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeekStart)
        }

        var totals: [Date: Double] = [:]
        for summary in summaries {
            guard let start = weekStart(of: summary.startedAt, calendar: calendar) else { continue }
            totals[start, default: 0] += summary.distanceMeters
        }

        return starts.map { RunWeeklyBar(weekStart: $0, distanceMeters: totals[$0] ?? 0) }
    }

    static func lastRun(
        summaries: [SavedRunSummary],
        now: Date,
        calendar: Calendar
    ) -> LastRunSummary? {
        guard let latest = summaries.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        // 달력 날짜 차이 — 24시간 단위가 아니다.
        // 어제 23시에 뛰고 오늘 0시 반에 보면 "1일 전"이어야 한다.
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: latest.startedAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return LastRunSummary(distanceMeters: latest.distanceMeters, daysAgo: max(0, days))
    }

    // MARK: - Private

    private static func isInPeriod(
        _ date: Date,
        period: RunStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch period {
        case .all:
            return true
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
    }

    private static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunStatsCalculatorTests test
```
Expected: PASS (12 tests)

- [ ] **Step 5: 빌드 + 전체 테스트 + 린트 후 커밋**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 러닝 집계 순수 계산기 RunStats 추가

- 기간 합계·최근 8주 추이·마지막 러닝을 SavedRunSummary만으로 계산한다(blob 미열람)
- now와 calendar를 주입받아 실행 시점과 무관하게 결정적으로 동작한다
- 안 뛴 주도 0 막대로 채워 막대 개수가 데이터에 따라 흔들리지 않게 한다
- 기존 RunSplitCalculator 패턴대로 결과 타입과 enum 계산기를 한 파일에 둔다" \
  -- Trace/Domain/RunTracking/Entity/RunStats.swift TraceTests/RunStatsCalculatorTests.swift
```

---

## Task 3: 기록 탭 페이지 + 집계 숫자

**Files:**
- Create: `Trace/Pages/HistoryPage/HistoryPageViewModel.swift`
- Create: `Trace/Pages/HistoryPage/HistoryPage.swift`
- Create: `Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift`
- Test: `TraceTests/HistoryPageViewModelTests.swift`
- Modify: `Trace/App/RootView.swift` (플레이스홀더 → 실제 페이지)

**Interfaces:**
- Consumes: Task 2의 `RunStatsCalculator.stats(summaries:period:now:calendar:)`, `RunStatsCalculator.weeklyBars(...)`, `RunStatsPeriod`
- Produces:
  - `@MainActor @Observable final class HistoryPageViewModel`, `init(repository: RunRecordRepositoryProtocol)`
  - `var period: RunStatsPeriod`(쓰기 가능 — 세그먼트 바인딩), `private(set) var summaries: [SavedRunSummary]`
  - `var stats: RunStats`, `var weeklyBars: [RunWeeklyBar]`, `var isEmpty: Bool`
  - `func load() async`
  - Task 4가 `weeklyBars`를 차트에 꽂고, Task 5가 `summaries`를 목록에 쓴다.

- [ ] **Step 1: 뷰모델 테스트를 먼저 쓴다**

Create `TraceTests/HistoryPageViewModelTests.swift`:

```swift
import XCTest
@testable import Trace

@MainActor
final class HistoryPageViewModelTests: XCTestCase {
    private func makeSummary(daysAgo: Int, distanceMeters: Double) -> SavedRunSummary {
        SavedRunSummary(
            id: UUID(),
            startedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
            distanceMeters: distanceMeters,
            duration: 1800,
            elevationGainMeters: 0
        )
    }

    private func makeRun(_ summary: SavedRunSummary) -> SavedRun {
        SavedRun(summary: summary, samples: [], pauses: [], goal: .open, waypoints: [])
    }

    func test_초기_기간은_이번_주다() {
        let viewModel = HistoryPageViewModel(repository: MockRunRecordRepository())
        XCTAssertEqual(viewModel.period, .thisWeek)
    }

    func test_기록이_없으면_isEmpty가_참이고_집계는_0이다() async {
        let viewModel = HistoryPageViewModel(repository: MockRunRecordRepository())
        await viewModel.load()
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.stats.runCount, 0)
    }

    func test_기록이_없어도_주간_막대는_8개다() async {
        // 스펙 6.2: 0건에서도 집계 영역은 그대로 렌더링한다
        let viewModel = HistoryPageViewModel(repository: MockRunRecordRepository())
        await viewModel.load()
        XCTAssertEqual(viewModel.weeklyBars.count, 8)
    }

    func test_기간을_바꾸면_집계가_다시_계산된다() async throws {
        let repository = MockRunRecordRepository()
        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))
        try await repository.save(makeRun(makeSummary(daysAgo: 200, distanceMeters: 9000)))

        let viewModel = HistoryPageViewModel(repository: repository)
        await viewModel.load()

        viewModel.period = .thisWeek
        XCTAssertEqual(viewModel.stats.runCount, 1)

        viewModel.period = .all
        XCTAssertEqual(viewModel.stats.runCount, 2)
        XCTAssertEqual(viewModel.stats.totalDistanceMeters, 14000)
    }

    func test_로드하면_isEmpty가_거짓이_된다() async throws {
        let repository = MockRunRecordRepository()
        try await repository.save(makeRun(makeSummary(daysAgo: 0, distanceMeters: 5000)))

        let viewModel = HistoryPageViewModel(repository: repository)
        await viewModel.load()

        XCTAssertFalse(viewModel.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는 것을 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/HistoryPageViewModelTests test
```
Expected: 컴파일 실패 — `cannot find 'HistoryPageViewModel' in scope`

- [ ] **Step 3: 뷰모델 구현**

Create `Trace/Pages/HistoryPage/HistoryPageViewModel.swift`:

```swift
import Foundation
import Observation

/// 기록 탭 상태.
/// 목록은 요약(캐시 컬럼)만 읽고, 집계는 그 배열에서 파생시킨다(스펙 §4).
/// 상세 진입 시에만 단건 blob을 읽는 기존 규칙은 그대로다.
@MainActor
@Observable
final class HistoryPageViewModel {
    /// 8주 — 스펙 §4.1. 기간 세그먼트와 무관하게 고정이다(§6).
    static let weeklyBarCount = 8

    private let repository: RunRecordRepositoryProtocol

    var period: RunStatsPeriod = .thisWeek
    private(set) var summaries: [SavedRunSummary] = []

    init(repository: RunRecordRepositoryProtocol) {
        self.repository = repository
    }

    var isEmpty: Bool { summaries.isEmpty }

    var stats: RunStats {
        RunStatsCalculator.stats(
            summaries: summaries, period: period, now: Date(), calendar: .current
        )
    }

    var weeklyBars: [RunWeeklyBar] {
        RunStatsCalculator.weeklyBars(
            summaries: summaries, weekCount: Self.weeklyBarCount, now: Date(), calendar: .current
        )
    }

    func load() async {
        summaries = await repository.fetchSummaries()
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/HistoryPageViewModelTests test
```
Expected: PASS (5 tests)

- [ ] **Step 5: 대시보드 컴포넌트 구현 (숫자까지, 그래프는 Task 4)**

Create `Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift`:

```swift
import SwiftUI

/// 집계 대시보드 — 기간 세그먼트 + "거리가 주인공" 숫자 블록.
/// 세그먼트는 이 숫자만 바꾼다. 그래프와 목록은 기간과 무관하다(스펙 §6).
struct HistoryDashboard: View {
    @Bindable var viewModel: HistoryPageViewModel

    var body: some View {
        VStack(spacing: 16) {
            Picker("기간", selection: $viewModel.period) {
                ForEach(RunStatsPeriod.allCases) { period in
                    Text(period.historyLabel).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("history.periodPicker")

            statBlock
        }
    }

    private var statBlock: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", viewModel.stats.totalDistanceMeters / 1000))
                    .font(DesignToken.Typography.runDistanceHero)
                Text("km")
                    .font(DesignToken.Typography.runDistanceUnit)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            .foregroundStyle(DesignToken.Color.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.period.historyLabel) 총 거리")
            .accessibilityValue("\(String(format: "%.2f", viewModel.stats.totalDistanceMeters / 1000))킬로미터")

            Text(
                "\(viewModel.stats.runCount)회 · "
                + RunDurationFormatter.string(seconds: viewModel.stats.totalDuration)
            )
                .font(DesignToken.Typography.subtitle)
                .foregroundStyle(DesignToken.Color.ink2)
                .accessibilityIdentifier("history.secondaryStats")
        }
    }
}

/// 화면 문구는 Presentation 소유다. Domain의 `RunStatsPeriod`에는 현지화 문자열을 넣지 않는다.
private extension RunStatsPeriod {
    var historyLabel: String {
        switch self {
        case .thisWeek: return "이번 주"
        case .thisMonth: return "이번 달"
        case .all: return "전체"
        }
    }
}
```

- [ ] **Step 6: 페이지 골격 구현**

Create `Trace/Pages/HistoryPage/HistoryPage.swift`:

```swift
import SwiftUI

/// 기록 탭 루트 — 집계 대시보드 + 전체 목록. 목록·상세는 Task 5에서 이관된다(스펙 §5).
/// 넷이 한 스크롤에 들어가고 고정 헤더는 없다(스펙 §6.1).
struct HistoryPage: View {
    @State private var viewModel: HistoryPageViewModel

    init(repository: RunRecordRepositoryProtocol) {
        _viewModel = State(initialValue: HistoryPageViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HistoryDashboard(viewModel: viewModel)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                // Task 5에서 기록 목록 섹션이 여기 들어온다.
                if viewModel.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "아직 기록이 없어요",
                            systemImage: "figure.run",
                            description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
        }
    }
}
```

> **구조 주의(스펙 §6.1):** 대시보드를 `ScrollView`로 감싸고 그 안에 `List`를 넣으면 **높이가 붕괴한다.** 전체를 하나의 `List`로 두고 대시보드를 섹션으로 넣는 이 방식이 기본이다. Task 5에서 목록 섹션을 더할 때 스와이프 삭제가 살아 있는지 반드시 확인한다.

- [ ] **Step 7: `RootView` 플레이스홀더를 실제 페이지로 교체**

`Trace/App/RootView.swift`에서 Task 1의 플레이스홀더 블록을 다음으로 교체:

```swift
                    HistoryPage(repository: container.runRecordRepository)
                        .opacity(selectedTab == .history ? 1 : 0)
                        .allowsHitTesting(selectedTab == .history)
                        .accessibilityHidden(selectedTab != .history)
```

- [ ] **Step 8: 빌드 + 전체 테스트 + 린트, 시뮬레이터 확인 후 커밋**

시뮬레이터로 기록 탭을 열어 확인:
1. 기간 세그먼트를 바꾸면 큰 숫자가 바뀐다
2. 기록이 0건이어도 **세그먼트와 숫자(0.00km)가 그대로 보이고** `ContentUnavailableView`는 그 아래에만 나온다

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 기록 탭 집계 대시보드 추가

- 기간 세그먼트(이번 주/이번 달/전체)와 거리 중심 숫자 블록을 만든다
- 세그먼트는 숫자만 바꾸고 그래프·목록은 기간과 무관하게 고정이다(스펙 6)
- 기록 0건에서도 집계 영역은 그대로 렌더링하고 안내는 목록 자리에만 둔다
- ScrollView 안 List 중첩을 피해 전체를 하나의 List 섹션 구성으로 짠다" \
  -- Trace/Pages/HistoryPage/HistoryPage.swift \
     Trace/Pages/HistoryPage/HistoryPageViewModel.swift \
     Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift \
     TraceTests/HistoryPageViewModelTests.swift \
     Trace/App/RootView.swift
```

---

## Task 4: 최근 8주 막대그래프 (Swift Charts)

**Files:**
- Modify: `Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift`

**Interfaces:**
- Consumes: Task 3의 `HistoryPageViewModel.weeklyBars -> [RunWeeklyBar]`
- Produces: 없음(표시 전용)

**이 저장소 최초의 `import Charts`다.** 차트는 자체 색·폰트 기본값을 갖고 있어 디자인 토큰과 어긋나기 쉽고, **기본적으로 VoiceOver에 데이터를 노출하지 않는다.**

- [ ] **Step 1: 차트 뷰 추가**

`HistoryPage+DashboardComponent.swift` 최상단 import에 `import Charts`를 추가하고, `HistoryDashboard.body`의 `statBlock` 아래에 `weeklyChart`를 넣는다:

```swift
    var body: some View {
        VStack(spacing: 16) {
            Picker("기간", selection: $viewModel.period) {
                ForEach(RunStatsPeriod.allCases) { period in
                    Text(period.historyLabel).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("history.periodPicker")

            statBlock
            weeklyChart
        }
    }
```

그리고 같은 타입 안에 추가:

```swift
    /// 최근 8주 거리 추이. 기간 세그먼트와 무관하게 항상 8주 고정이다(스펙 §6) —
    /// 추이는 고정된 창으로 봐야 주마다 비교가 되고,
    /// "전체"에서 몇 년치 막대를 그릴 수도 없다.
    private var weeklyChart: some View {
        Chart(viewModel.weeklyBars, id: \.weekStart) { bar in
            BarMark(
                x: .value("주", bar.weekStart, unit: .weekOfYear),
                y: .value("거리", bar.distanceMeters / 1000)
            )
            .foregroundStyle(DesignToken.Color.accent)
            .accessibilityLabel(Self.weekLabel(bar.weekStart))
            .accessibilityValue("\(String(format: "%.1f", bar.distanceMeters / 1000))킬로미터")
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(DesignToken.Color.border)
                AxisValueLabel()
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("최근 8주 주간 거리")
        .accessibilityIdentifier("history.weeklyChart")
    }

    private static func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day()) + " 주"
    }
```

- [ ] **Step 2: 빌드**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
```
Expected: 빌드 성공. `import Charts` 실패가 나면 iOS 배포 타깃이 16 미만인지 확인한다(현재 17.0이라 문제없어야 한다).

- [ ] **Step 3: 검증 3종 — 시뮬레이터로 직접 확인 (스펙 §6.3 플랜 요구)**

XcodeBuildMCP로 기록 탭을 열어 확인한다:

1. **다크모드** — 시뮬레이터 외관을 다크로 전환해 막대·축 라벨·그리드가 배경에 묻히지 않는지 본다. 묻히면 `DesignToken.Color`로 명시 지정한다.
2. **Dynamic Type** — 접근성 텍스트 크기를 최대로 올려 축 라벨이 겹치거나 잘리지 않는지 본다. 겹치면 `AxisMarks`의 `values:`를 격주(`.stride(by: .weekOfYear, count: 2)`)로 줄인다.
3. **VoiceOver** — VoiceOver를 켜고 차트로 이동해 **막대별 값(주차·거리)이 실제로 읽히는지** 확인한다. 안 읽히면 `.accessibilityLabel`/`.accessibilityValue`가 `BarMark`에 제대로 붙었는지 본다. **이 항목이 이 태스크의 핵심 검증이다** — 기본값으로는 스크린리더에 그래프가 통째로 빈 화면이 된다.

세 항목의 결과를 태스크 완료 보고에 그대로 적는다. "확인함"이 아니라 무엇이 어떻게 보였는지 쓴다.

- [ ] **Step 4: 전체 테스트 + 린트 후 커밋**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 기록 탭에 최근 8주 거리 막대그래프 추가

- Swift Charts를 이 저장소에서 처음 도입한다(iOS 17 최소라 사용 가능)
- 막대별 accessibilityLabel/Value를 붙여 VoiceOver로 주차와 거리가 읽히게 한다
- 차트 기본 색 대신 디자인 토큰을 명시해 다크모드에서 묻히지 않게 한다
- 기간 세그먼트와 무관하게 항상 8주 고정이라 주마다 비교가 가능하다" \
  -- Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift
```

---

## Task 5: 목록·상세 이관 + 데이터 소유권 통일

**스펙 §5의 경계 규칙:** 목적지(목록·상세)만 옮기고 버튼을 남기면 **죽은 버튼**이 생긴다. 이 태스크가 이관 전체를 한 단위로 처리한다.

**Files:**
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `Trace/App/RootView.swift`
- Modify: `Trace/Pages/HistoryPage/HistoryPage.swift`
- Modify: `Trace/Pages/HistoryPage/HistoryPageViewModel.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift:41-85, 185-189`
- Move: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`
  → `Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift`
- Move: `Trace/Pages/RunPage/RunDurationFormatter.swift`
  → `Trace/DesignSystem/Formatter/RunDurationFormatter.swift`
- Move: `Trace/Pages/RunPage/RunGoalFormatter.swift`
  → `Trace/DesignSystem/Formatter/RunGoalFormatter.swift`
- Move: `Trace/Pages/RunPage/RunPaceFormatter.swift`
  → `Trace/DesignSystem/Formatter/RunPaceFormatter.swift`

**Interfaces:**
- Consumes: Task 3의 `HistoryPageViewModel`
- Produces: `DependencyContainer.runHistoryViewModel: RunHistoryViewModel`(공유 인스턴스). Task 6이 러닝 탭 요약 줄에서 같은 인스턴스를 읽는다.

**데이터 소유권 결정(스펙 §7.2 플랜 요구 ②):** `RunHistoryViewModel`은 지금 `RunPage.init` 안의 `@State`다. 기록 탭과 러닝 탭이 각자 인스턴스를 들면 `[SavedRunSummary]` 캐시가 **두 벌**이 되고, 두 탭이 동시에 살아 있는 구조라 한쪽의 삭제가 다른 쪽에 반영되지 않는다. **`DependencyContainer`로 올려 한 벌을 공유한다** — `runSession`이 이미 쓰는 패턴이다.

- [ ] **Step 1: `DependencyContainer`에 공유 뷰모델 추가**

`Trace/App/DependencyContainer.swift`의 `struct` 프로퍼티에 추가:

```swift
    /// 기록 탭과 러닝 탭 요약 줄이 같은 배열을 봐야 한다 — 각자 인스턴스를 들면
    /// 한쪽의 삭제·저장이 다른 쪽에 반영되지 않은 채 공존한다(스펙 §7.2)
    let runHistoryViewModel: RunHistoryViewModel
```

`live()`의 `return DependencyContainer(` 인자에 추가(`runRecordRepository` 다음 줄):

```swift
            runHistoryViewModel: RunHistoryViewModel(repository: runRecordRepository),
```

`uiTesting()`의 `return DependencyContainer(`에도 `runRecordRepository` 다음 줄에 정확히
같은 공유 인스턴스 생성식을 추가한다:

```swift
            runHistoryViewModel: RunHistoryViewModel(repository: runRecordRepository),
```

- [ ] **Step 2: `HistoryPageViewModel`이 공유 뷰모델을 쓰도록 변경**

`HistoryPageViewModel`이 자체 `summaries`를 들지 않고 공유 인스턴스를 참조하게 바꾼다. `Trace/Pages/HistoryPage/HistoryPageViewModel.swift`를 교체:

```swift
import Foundation
import Observation

/// 기록 탭 상태 — 기간 선택만 소유하고, 데이터는 공유 `RunHistoryViewModel`에서 읽는다.
/// 집계는 그 배열에서 파생시킨다(스펙 §4).
/// 상세 진입 시에만 단건 blob을 읽는 규칙은 그대로다.
@MainActor
@Observable
final class HistoryPageViewModel {
    /// 8주 — 스펙 §4.1. 기간 세그먼트와 무관하게 고정이다(§6).
    static let weeklyBarCount = 8

    let history: RunHistoryViewModel

    var period: RunStatsPeriod = .thisWeek

    init(history: RunHistoryViewModel) {
        self.history = history
    }

    var summaries: [SavedRunSummary] { history.summaries }

    var isEmpty: Bool { summaries.isEmpty }

    var stats: RunStats {
        RunStatsCalculator.stats(
            summaries: summaries, period: period, now: Date(), calendar: .current
        )
    }

    var weeklyBars: [RunWeeklyBar] {
        RunStatsCalculator.weeklyBars(
            summaries: summaries, weekCount: Self.weeklyBarCount, now: Date(), calendar: .current
        )
    }

    func load() async {
        await history.load()
    }
}
```

`TraceTests/HistoryPageViewModelTests.swift`에서 저장소를 즉석 생성하던 세 테스트는 다음처럼
바꾼다:

```swift
        let viewModel = HistoryPageViewModel(
            history: RunHistoryViewModel(repository: MockRunRecordRepository())
        )
```

이미 `let repository = MockRunRecordRepository()`가 있는 두 테스트는 같은 저장소를 공유해야
하므로 다음처럼 바꾼다:

```swift
        let viewModel = HistoryPageViewModel(history: RunHistoryViewModel(repository: repository))
```

- [ ] **Step 3: 기록 컴포넌트 파일을 HistoryPage 소유로 이동한다**

목록·상세가 더 이상 러닝 탭 전용이 아니므로 페이지 소유권 규칙에 맞춰 파일을 먼저
옮긴다. 상세 화면과 러닝 화면이 함께 쓰는 포맷터 3개도 특정 페이지 아래에 두지 않고
공용 Presentation 위치로 이동한다:

```bash
mkdir -p Trace/DesignSystem/Formatter
git mv \
  Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift \
  Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift
git mv \
  Trace/Pages/RunPage/RunDurationFormatter.swift \
  Trace/DesignSystem/Formatter/RunDurationFormatter.swift
git mv \
  Trace/Pages/RunPage/RunGoalFormatter.swift \
  Trace/DesignSystem/Formatter/RunGoalFormatter.swift
git mv \
  Trace/Pages/RunPage/RunPaceFormatter.swift \
  Trace/DesignSystem/Formatter/RunPaceFormatter.swift
```

파일 시스템 동기화 그룹을 쓰므로 `.pbxproj` 수정은 필요 없다. 타입 이름과 테스트 파일
위치는 바꾸지 않는다.

- [ ] **Step 4: 목록·상세를 기록 탭 안으로 옮긴다**

`Trace/Pages/HistoryPage/HistoryPage.swift`를 교체:

```swift
import SwiftUI

/// 기록 탭 루트 — 집계 대시보드 + 전체 목록.
/// 넷이 한 스크롤에 들어가고 고정 헤더는 없다(스펙 §6.1).
/// 상세는 push. 기간 세그먼트는 집계 숫자만 바꾸고 목록은 항상 전체다(스펙 §6).
struct HistoryPage: View {
    @State private var viewModel: HistoryPageViewModel

    init(history: RunHistoryViewModel) {
        _viewModel = State(initialValue: HistoryPageViewModel(history: history))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HistoryDashboard(viewModel: viewModel)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if viewModel.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "아직 기록이 없어요",
                            systemImage: "figure.run",
                            description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(viewModel.summaries) { summary in
                            NavigationLink(value: summary) {
                                HistoryRecordRow(summary: summary)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        .onDelete { indexSet in
                            guard let first = indexSet.first else { return }
                            viewModel.history.requestDelete(viewModel.summaries[first])
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedRunSummary.self) { summary in
                HistoryRecordDetailView(summary: summary, viewModel: viewModel.history)
            }
            .task { await viewModel.load() }
            .alert(
                "기록을 삭제할까요?",
                isPresented: Binding(
                    get: { viewModel.history.pendingDelete != nil },
                    set: { _ in }
                )
            ) {
                Button("삭제", role: .destructive) { Task { await viewModel.history.confirmPendingDelete() } }
                Button("취소", role: .cancel) { viewModel.history.cancelPendingDelete() }
            } message: {
                Text("삭제한 기록은 되돌릴 수 없습니다")
            }
            .alert("삭제하지 못했어요", isPresented: Bindable(viewModel.history).showsDeleteFailure) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("잠시 후 다시 시도해 주세요")
            }
        }
    }
}
```

- [ ] **Step 5: 이동한 기록 컴포넌트에서 이전 목록 페이지를 걷어낸다**

`Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift`의
`RunHistoryPage` 타입과 그 설명을 삭제한 뒤, `private struct RunHistoryRow`를 다음으로 바꾼다:

```swift
/// 기록 탭 목록 행 — 요약 컬럼만 사용하고 무거운 blob은 열지 않는다.
struct HistoryRecordRow: View {
```

같은 파일의 `RunRecordDetailView`도 페이지 소유권이 드러나도록 이름을 바꾼다:

```swift
struct HistoryRecordDetailView: View {
```

목록은 이제 `HistoryPage`가 그린다. 상세의 나머지 구현과 하위 private 컴포넌트는
그대로 둔다.
삭제 뒤 파일에 `RunHistoryRoute` 참조가 남아 있지 않은지 확인한다:

```bash
rg -n "RunHistoryPage|RunHistoryRoute|RunHistoryRow|RunRecordDetailView" \
  Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift
```

Expected: no matches.

- [ ] **Step 6: 러닝 탭에서 기록 진입점을 전부 걷어낸다**

`Trace/Pages/RunPage/RunPage.swift`에서:

1. `historyViewModel`, `historyPath` `@State` 삭제
2. `init`에서 `recordRepository` 파라미터와 `_historyViewModel` 초기화 삭제
3. `controls`의 `.idle` 케이스를 `NavigationStack` 없이 `startControls`만 두도록 교체
4. `startControls`에서 기록 버튼 `HStack` 블록 삭제
5. 파일 끝 `enum RunHistoryRoute` 삭제

`.idle` 케이스는 다음이 된다:

```swift
        case .idle:
            startControls
```

`startControls`는 다음이 된다(Task 6에서 요약 줄이 이 자리에 들어온다):

```swift
    private var startControls: some View {
        VStack(spacing: 0) {
            Spacer()
            goalPicker
            Spacer()
            startButton
            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

`init`은 다음이 된다:

```swift
    init(session: RunSession, announcer: VoiceAnnouncerProtocol) {
        _viewModel = State(initialValue: RunPageViewModel(session: session, announcer: announcer))
    }
```

- [ ] **Step 7: `RootView` 호출부 갱신**

```swift
                    RunPage(
                        session: container.runSession,
                        announcer: container.voiceAnnouncer
                    )
                    .opacity(selectedTab == .run ? 1 : 0)
                    .allowsHitTesting(selectedTab == .run)
                    .accessibilityHidden(selectedTab != .run)

                    HistoryPage(history: container.runHistoryViewModel)
                        .opacity(selectedTab == .history ? 1 : 0)
                        .allowsHitTesting(selectedTab == .history)
                        .accessibilityHidden(selectedTab != .history)
```

- [ ] **Step 8: 빌드 + 전체 테스트**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
```
Expected: 빌드 성공, 전체 통과. 현재 코드 검색상 UI 테스트에는 `run.historyButton` 참조가
없다. 아래 검색으로 이전 경로가 남지 않았는지 명시적으로 확인한다:

```bash
rg -n "RunHistoryRoute|RunHistoryPage|RunHistoryRow|RunRecordDetailView|run\\.historyButton" \
  Trace TraceTests TraceUITests
```

Expected: no matches.

- [ ] **Step 9: 시뮬레이터로 이관 확인**

1. 러닝 탭 대기 화면에 **기록 버튼이 없다**
2. 기록 탭에서 목록이 보이고, 행을 탭하면 상세로 push된다
3. 목록에서 **스와이프 삭제가 동작한다**(`List` 섹션 구성이 제스처를 살렸는지 — 스펙 §6.1 확인 항목)
4. 삭제 후 집계 숫자와 그래프가 함께 갱신된다(공유 뷰모델이 한 벌인지 확인)

- [ ] **Step 10: 린트 후 커밋**

```bash
swiftlint
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "refactor: 기록 목록·상세를 기록 탭으로 이관

- 러닝 탭의 기록 버튼과 NavigationStack을 걷어내고 목록을 기록 탭 루트로 옮긴다
- 목적지만 옮기고 버튼을 남기면 죽은 버튼이 생기므로 이관을 한 단위로 처리한다
- RunHistoryViewModel을 DependencyContainer로 올려 두 탭이 같은 배열을 본다
- 각자 인스턴스를 들면 한쪽의 삭제가 다른 쪽에 반영되지 않은 채 공존한다" \
  -- Trace/App/DependencyContainer.swift \
     Trace/App/RootView.swift \
     Trace/Pages/HistoryPage/HistoryPage.swift \
     Trace/Pages/HistoryPage/HistoryPageViewModel.swift \
     Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift \
     Trace/DesignSystem/Formatter/RunDurationFormatter.swift \
     Trace/DesignSystem/Formatter/RunGoalFormatter.swift \
     Trace/DesignSystem/Formatter/RunPaceFormatter.swift \
     Trace/Pages/RunPage/RunPage.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift \
     Trace/Pages/RunPage/RunDurationFormatter.swift \
     Trace/Pages/RunPage/RunGoalFormatter.swift \
     Trace/Pages/RunPage/RunPaceFormatter.swift
```

---

## Task 6: 러닝 탭 이번 주 요약 줄 + 갱신 경로

**스펙 §5의 화면 온전성 규칙:** Task 5가 기록 버튼을 걷어냈으므로 러닝 탭은 지금 착수 전보다 요소가 하나 적다. **이 태스크가 같은 마일스톤 안에서 그것을 되메운다.**

**Files:**
- Modify: `Trace/Domain/RunTracking/Entity/RunStats.swift`
- Create: `Trace/Pages/RunPage/RunIdleSummaryFormatter.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`
- Modify: `Trace/App/RootView.swift`
- Test: `TraceTests/RunStatsCalculatorTests.swift` (폴백 분기 테스트 추가)
- Test: `TraceTests/RunIdleSummaryFormatterTests.swift`

**Interfaces:**
- Consumes: Task 2의 `RunStatsCalculator.stats(...)`·`lastRun(...)`, Task 5의
  `DependencyContainer.runHistoryViewModel`
- Produces: `RunIdleSummary` Domain 결과와 `RunIdleSummaryFormatter.string(for:)` 화면 문구.
  `RunPage`가 둘을 조합한다.

- [ ] **Step 1: 3단 폴백 정책과 화면 문구 테스트를 먼저 쓴다**

Domain 테스트는 한국어 문구가 아니라 3단 폴백 결과를 검증한다.
`TraceTests/RunStatsCalculatorTests.swift` 끝에 추가:

```swift
    // MARK: - 대기 화면 3단 폴백 정책 (스펙 §7.1)

    func test_이번_주에_뛰었으면_이번_주_집계를_준다() {
        let summaries = [summary(daysAgo: 3, distanceMeters: 12400, duration: 3600)]
        let result = RunStatsCalculator.idleSummary(
            summaries: summaries, now: now, calendar: calendar
        )
        XCTAssertEqual(
            result,
            .thisWeek(RunStats(
                totalDistanceMeters: 12400,
                runCount: 1,
                totalDuration: 3600
            ))
        )
    }

    func test_이번_주_0회면_마지막_러닝으로_폴백한다() {
        let summaries = [summary(daysAgo: 10, distanceMeters: 5200, duration: 1800)]
        let result = RunStatsCalculator.idleSummary(
            summaries: summaries, now: now, calendar: calendar
        )
        XCTAssertEqual(
            result,
            .lastRun(LastRunSummary(distanceMeters: 5200, daysAgo: 10))
        )
    }

    func test_기록이_아예_없으면_noRuns를_준다() {
        let result = RunStatsCalculator.idleSummary(
            summaries: [], now: now, calendar: calendar
        )
        XCTAssertEqual(result, .noRuns)
    }
```

화면 문구는 Presentation에서 별도로 검증한다. Create
`TraceTests/RunIdleSummaryFormatterTests.swift`:

```swift
import XCTest
@testable import Trace

final class RunIdleSummaryFormatterTests: XCTestCase {
    func test_이번_주_집계_문구() {
        let result = RunIdleSummary.thisWeek(RunStats(
            totalDistanceMeters: 12400,
            runCount: 1,
            totalDuration: 3600
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "이번 주 12.40km · 1회"
        )
    }

    func test_지난_러닝_문구() {
        let result = RunIdleSummary.lastRun(LastRunSummary(
            distanceMeters: 5200,
            daysAgo: 10
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "지난 러닝 5.20km · 10일 전"
        )
    }

    func test_어제_문구() {
        let result = RunIdleSummary.lastRun(LastRunSummary(
            distanceMeters: 5200,
            daysAgo: 1
        ))
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: result),
            "지난 러닝 5.20km · 어제"
        )
    }

    func test_기록_없음_문구() {
        XCTAssertEqual(
            RunIdleSummaryFormatter.string(for: .noRuns),
            "첫 러닝을 시작해보세요"
        )
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunStatsCalculatorTests \
  -only-testing:TraceTests/RunIdleSummaryFormatterTests test
```
Expected: 컴파일 실패 — `RunIdleSummary`와 `RunIdleSummaryFormatter`가 아직 없다.

- [ ] **Step 3: Domain의 3단 폴백 결과와 계산을 구현한다**

`Trace/Domain/RunTracking/Entity/RunStats.swift`에서 `LastRunSummary` 다음에 결과 enum을 추가:

```swift
/// 러닝 탭 대기 화면의 3단 폴백 결과.
/// Domain은 어떤 데이터를 보여줄지만 정하고, 한국어 화면 문구는 RunPage가 소유한다.
enum RunIdleSummary: Equatable, Sendable {
    case thisWeek(RunStats)
    case lastRun(LastRunSummary)
    case noRuns
}
```

`RunStatsCalculator` 안에서 `lastRun` 다음에 정책 함수를 추가:

```swift
    static func idleSummary(
        summaries: [SavedRunSummary],
        now: Date,
        calendar: Calendar
    ) -> RunIdleSummary {
        let weekly = stats(
            summaries: summaries,
            period: .thisWeek,
            now: now,
            calendar: calendar
        )
        if weekly.runCount > 0 {
            return .thisWeek(weekly)
        }
        if let last = lastRun(summaries: summaries, now: now, calendar: calendar) {
            return .lastRun(last)
        }
        return .noRuns
    }
```

- [ ] **Step 4: RunPage의 한국어 문구 포맷터를 구현한다**

Create `Trace/Pages/RunPage/RunIdleSummaryFormatter.swift`:

```swift
import Foundation

/// Domain의 3단 폴백 결과를 러닝 대기 화면 문구로 바꾼다.
enum RunIdleSummaryFormatter {
    static func string(for summary: RunIdleSummary) -> String {
        switch summary {
        case .thisWeek(let stats):
            return "이번 주 \(kilometerText(stats.totalDistanceMeters))km · "
                + "\(stats.runCount)회"
        case .lastRun(let last):
            return "지난 러닝 \(kilometerText(last.distanceMeters))km · "
                + dayText(last.daysAgo)
        case .noRuns:
            return "첫 러닝을 시작해보세요"
        }
    }

    private static func kilometerText(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }

    private static func dayText(_ daysAgo: Int) -> String {
        switch daysAgo {
        case 0: return "오늘"
        case 1: return "어제"
        default: return "\(daysAgo)일 전"
        }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunStatsCalculatorTests \
  -only-testing:TraceTests/RunIdleSummaryFormatterTests test
```
Expected: PASS (RunStatsCalculator 15 tests + RunIdleSummaryFormatter 4 tests)

- [ ] **Step 6: 러닝 탭에 요약 줄을 붙인다**

`Trace/Pages/RunPage/RunPage.swift`:

저장 프로퍼티 추가:
```swift
    private let history: RunHistoryViewModel
```

`init` 교체:
```swift
    init(session: RunSession, announcer: VoiceAnnouncerProtocol, history: RunHistoryViewModel) {
        _viewModel = State(initialValue: RunPageViewModel(session: session, announcer: announcer))
        self.history = history
    }
```

`startControls` 교체:
```swift
    private var startControls: some View {
        VStack(spacing: 0) {
            summaryLine
            Spacer()
            goalPicker
            Spacer()
            startButton
            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 대기 화면 최상단 요약 줄.
    /// 자리는 항상 유지하고 내용만 3단으로 바뀐다(스펙 §7.1).
    /// 집계는 기록 탭과 같은 계산기를 소비한다 — 자체 계산을 만들지 않는다(스펙 §4).
    private var summaryLine: some View {
        Text(RunIdleSummaryFormatter.string(
            for: RunStatsCalculator.idleSummary(
                summaries: history.summaries,
                now: Date(),
                calendar: .current
            )
        ))
        .font(DesignToken.Typography.subtitle)
        .foregroundStyle(DesignToken.Color.ink2)
        .padding(.top, 8)
        .accessibilityIdentifier("run.summaryLine")
    }
```

- [ ] **Step 7: 저장 완료 전에 요약을 닫는 경합을 차단한다**

현재 저장은 비동기다. `저장 중…`일 때 요약을 먼저 닫으면 `dismissSummary()`가
`saveStatus`와 `pendingRun`을 초기화하고, 저장 완료 이벤트를 관찰하기 전에 놓칠 수 있다.
`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`의 닫기 버튼을
저장 중에만 비활성화한다:

```swift
            Button("닫기") { viewModel.closeSummary() }
                .font(.system(size: 16, weight: .semibold))
                .disabled(viewModel.session.saveStatus == .saving)
                .accessibilityHint(
                    viewModel.session.saveStatus == .saving
                        ? "기록 저장이 끝나면 닫을 수 있습니다"
                        : ""
                )
```

저장 성공·실패가 결정되면 버튼은 다시 활성화된다. 실패 상태에서는 기존 `다시 시도`
동작을 그대로 쓰며, 기록이 저장되지 않았으므로 요약 줄도 이전 값에 머무는 것이 맞다.

- [ ] **Step 8: 저장 성공 이벤트에 갱신 경로를 연결한다 (스펙 §7.2 플랜 요구 ①)**

**`.task`/`.onAppear`는 쓸 수 없다.** `RootView`가 모든 탭을 `ZStack`에 상시 마운트한 채 `.opacity`만 토글하므로 뷰가 언마운트되지 않고, `.task`는 앱 최초 1회만 발화한다.

최초 로드는 상시 마운트된 `HistoryPage`의 기존 `.task`가 담당한다. 이후 새 러닝 저장은
`RunSession.saveStatus == .saved`가 된 뒤에만 저장소 재조회가 안전하다. `RootView`의
`VStack`에 저장 상태 감시를 붙인다:

```swift
        .onChange(of: container.runSession.saveStatus) { _, newStatus in
            // repository.save가 반환된 뒤에만 재조회한다. 저장 중 idle 전이는 Step 7에서 막는다.
            guard newStatus == .saved else { return }
            Task { await container.runHistoryViewModel.load() }
        }
```

- [ ] **Step 9: `RootView`의 `RunPage` 호출부에 `history` 전달**

```swift
                    RunPage(
                        session: container.runSession,
                        announcer: container.voiceAnnouncer,
                        history: container.runHistoryViewModel
                    )
```

- [ ] **Step 10: 빌드 + 전체 테스트 + 린트**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```

- [ ] **Step 11: 시뮬레이터로 갱신 경로 확인 (이 태스크의 핵심)**

1. 러닝 탭 대기 화면 최상단에 요약 줄이 보인다
2. 기록이 없으면 "첫 러닝을 시작해보세요"
3. 러닝 종료 직후 `저장 중…`인 동안 닫기 버튼이 비활성화되고, `기록 저장됨` 또는
   `저장 실패`가 된 뒤 다시 활성화된다
4. **저장 성공 뒤 요약 화면을 닫아 대기 화면으로 돌아왔을 때, 요약 줄 숫자가 방금 뛴
   기록을 반영한다** — GPX 시뮬레이션이나 짧은 시뮬레이터 러닝으로 확인
5. 기록 탭으로 갔다가 돌아와도 숫자가 일관된다
6. 기록 탭에서 기록을 삭제하면 러닝 탭 요약 줄에도 반영된다

3~4번이 실패하면 `saveStatus` 전이와 `RunHistoryViewModel.load()` 호출 시점을 계측한다.
**여기서 막히면 마일스톤을 닫지 않는다.**

- [ ] **Step 12: 커밋**

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 러닝 탭 대기 화면에 이번 주 요약 줄 추가

- 이번 주 실적, 0회면 마지막 러닝, 기록이 없으면 격려 문구로 3단 폴백한다
- 0회가 기본 상태에 가까워 곧바로 격려 문구로 대체하면 숫자가 대부분의 날 사라진다
- 기록 탭과 같은 계산기를 소비해 두 화면의 숫자가 어긋날 수 없게 한다
- 탭이 상시 마운트라 task가 최초 1회만 발화하므로 저장 성공 이벤트로 갱신한다" \
  -- Trace/Domain/RunTracking/Entity/RunStats.swift \
     Trace/Pages/RunPage/RunIdleSummaryFormatter.swift \
     Trace/Pages/RunPage/RunPage.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift \
     Trace/App/RootView.swift \
     TraceTests/RunStatsCalculatorTests.swift \
     TraceTests/RunIdleSummaryFormatterTests.swift
```

---

## 마일스톤 완료 체크

모든 태스크가 끝나면 확인한다:

- [ ] 전체 테스트 통과 (착수 전 기준선 348개 + 구현 중 추가된 테스트)
- [ ] `swiftlint` 에러 0 (경고는 마일스톤 4에서 정리 — 단 **새로 추가한 코드에는 경고를 만들지 않는다**)
- [ ] 러닝 탭에 기록 버튼이 없고, 요약 줄이 그 자리를 대신한다 (스펙 §5 화면 온전성)
- [ ] 기록 탭에서 목록·상세·스와이프 삭제가 전부 동작한다
- [ ] 러닝 종료 → 대기 화면 복귀 시 요약 줄이 갱신된다
- [ ] 저장 중에는 요약 닫기가 비활성화되고, 저장 성공 뒤 공유 기록이 갱신된다
- [ ] 차트가 다크모드·Dynamic Type·VoiceOver 세 조건에서 동작한다
- [ ] `rg -n "RunHistoryRoute|RunHistoryPage|RunHistoryRow|RunRecordDetailView|RunPage\\+HistoryComponent" Trace/`
  결과 0건 (이관 잔재·이전 타입명·이전 파일명 없음)

**실기기 QA는 별도로 진행한다** — 시뮬레이터에서 확인할 수 없는 것(실제 러닝 데이터로 집계가 맞는지, VoiceOver 실사용감)이 남아 있다. QA 체크리스트는 마일스톤 종료 후 `docs/qa/`에 작성한다(`testing.md` 시나리오 카드 형식).

**마일스톤 2(`run-idle-polish`)로 넘길 것:** 요약 줄의 시각 스타일, 대기 화면 위계 정리, 요약 줄 탭 동작 여부. 그리고 스펙 §8.3의 **완료 판정**("아직도 초라한가")은 마일스톤 2 종료 시점에 수행한다.
