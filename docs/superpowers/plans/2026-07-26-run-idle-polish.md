# run-idle-polish 구현 플랜 (MVP17 마일스톤 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**사이클 무게:** 경량 — `2026-07-23-run-idle-polish-design.md`에서 제품 방향과 데이터 소유권이 이미 확정됐고, 범위는 기존 대기 화면의 재구성과 의존성 제거에 한정된다. 새 레이어·외부 의존성·열린 제품 결정은 없다. 경량이므로 문서 서브에이전트 리뷰와 최종 브랜치 리뷰는 생략하되, TDD·태스크별 코드리뷰·실기기 QA·태스크별 커밋은 유지한다.

**Goal:** 러닝 탭 대기 화면을 `오늘의 러닝 → 목표 설정 → 시작`이라는 한 흐름으로 정리한다. 러닝 탭이 기록·집계를 읽지 않게 하여, 앱 재실행 뒤 `첫 러닝`으로 보였다가 기록 탭 방문 후 내용이 바뀌는 문제를 구조적으로 없앤다.

**Architecture:** `RunPage`는 `RunSession`과 `RunPageViewModel`의 목표 선택 상태만 소비한다. `RunHistoryViewModel`과 대기 요약 전용 Domain 타입·포맷터는 제거한다. `RootView`는 저장 뒤 `HistoryPage`를 최신화하는 기존 흐름은 유지하되, 그 데이터를 `RunPage`에 주입하지 않는다. 목표 입력·카운트다운·트래킹·저장 상태 전이는 변경하지 않는다.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XCUITest

**설계:** [`2026-07-23-run-idle-polish-design.md`](../specs/2026-07-23-run-idle-polish-design.md)

## Global Constraints

- 최소 iOS 17, 아이폰 세로 전용. 가로 전용 분기를 새로 만들지 않는다.
- MVVM + `@Observable`을 유지한다. Domain 순수 타입에는 `@MainActor`를 붙이지 않는다.
- 색·폰트·여백은 `DesignToken`과 현재 러닝 화면의 값을 우선 재사용한다. 이번 화면에서만 쓰는 임의 전역 토큰은 만들지 않는다.
- VoiceOver 기능 추가·재설계는 이 마일스톤 범위가 아니다. 자동 UI 테스트를 위한 식별자는 기존 방식대로 유지·추가할 수 있다.
- `RunPage`에서 `RunHistoryViewModel`을 제거해도 `RootView`의 저장 성공 뒤 `runHistoryViewModel.load()` 호출은 남긴다. 이 호출은 기록 탭 최신화의 소유권이다.
- 시뮬레이터는 iOS 26.5 `iPhone 17 Pro` UDID `D887D0A4-074C-4AFB-8D08-D87329D0EFD4` 하나만 사용한다.
- 테스트는 raw bash `xcodebuild ... -parallel-testing-enabled NO test`로만 실행한다.
- 각 태스크는 빌드·전체 테스트·SwiftLint·커밋 전 코드리뷰가 통과한 뒤 즉시 경로 명시 커밋한다. push는 하지 않는다.
- 사용자의 GPX 관련 Xcode 설정 변경(`Trace.xcodeproj/project.pbxproj`, `Trace.xcodeproj/xcshareddata/xcschemes/Trace.xcscheme`)은 이 사이클의 커밋에 포함하지 않는다.

## 검증 명령

```bash
SIM_UDID="D887D0A4-074C-4AFB-8D08-D87329D0EFD4"
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
| `Trace/App/RootView.swift` | RunPage 주입에서 기록 뷰모델 제거, 저장 뒤 기록 탭 최신화 유지 | 1 |
| `Trace/Pages/RunPage/RunPage.swift` | 대기 화면을 오늘의 러닝·목표·시작 순서로 재구성 | 1, 2 |
| `Trace/Domain/RunTracking/Entity/RunStats.swift` | 러닝 탭 전용 `LastRunSummary`·`RunIdleSummary`·`idleSummary` 제거 | 1 |
| `Trace/Pages/RunPage/RunIdleSummaryFormatter.swift` | 삭제 — 기록 요약 전용 화면 문구 | 1 |
| `TraceTests/RunStatsCalculatorTests.swift` | 삭제한 idle-summary 계산기 테스트 제거, 기록 탭 집계 테스트는 보존 | 1 |
| `TraceTests/RunIdleSummaryFormatterTests.swift` | 삭제 — 제거한 포맷터 테스트 | 1 |
| `TraceUITests/TraceUITests.swift` | 러닝 대기 화면의 제목·목표 선택·시작 진입점을 회귀 테스트 | 2 |
| `docs/qa/2026-07-26-run-idle-polish-device-checklist.md` | GPX 저장 경로와 대기 화면 의도 확인 | 3, 4 |
| `docs/roadmap.md` | 마일스톤 진행·완료 상태 | 3, 4 |

---

## Task 1: 기록 요약 의존성을 러닝 탭에서 분리

**목적:** 러닝 대기 화면이 기록 로딩 상태를 읽지 않도록 경계를 끊는다. 이 태스크가 끝나면 앱 재실행과 기록 탭 방문은 러닝 탭의 대기 콘텐츠를 바꾸지 못한다.

**Files:**
- Modify: `Trace/App/RootView.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift`
- Modify: `Trace/Domain/RunTracking/Entity/RunStats.swift`
- Modify: `TraceTests/RunStatsCalculatorTests.swift`
- Delete: `Trace/Pages/RunPage/RunIdleSummaryFormatter.swift`
- Delete: `TraceTests/RunIdleSummaryFormatterTests.swift`

- [x] **Step 1: 제거 대상의 테스트를 먼저 실패시킨다.** `RunStatsCalculatorTests`에서 대기 화면 3단 폴백(`idleSummary`) 기대를 삭제하고, `RunIdleSummaryFormatterTests`를 제거한다. 이어서 `RunPage` 생성자가 기록 뷰모델을 받지 않는 형태가 되도록 호출부 테스트/컴파일 기준을 바꾼다.
- [x] **Step 2: 최소 구현으로 의존성을 제거한다.** `RunPage`의 `history` 저장 프로퍼티·생성자 인자·`summaryLine`을 삭제하고, `RootView`의 RunPage 주입에서만 기록 뷰모델 인자를 제거한다. 저장 성공 뒤 `runHistoryViewModel.load()`와 `HistoryPage` 주입은 그대로 둔다.
- [x] **Step 3: 죽은 Domain/UI 코드를 정리한다.** `LastRunSummary`, `RunIdleSummary`, `RunStatsCalculator.idleSummary`, 포맷터 파일과 그 테스트를 제거한다. `RunStatsCalculator.stats`, `weeklyBars`, `lastRun`은 기록 탭이 계속 쓰므로 보존한다.
- [x] **Step 4: 회귀를 확인한다.** `rg`로 production 소스에 `RunIdleSummary`, `idleSummary`, `RunIdleSummaryFormatter`, `history: RunHistoryViewModel` 참조가 남지 않았는지 확인한다. `RootView`의 저장 성공 뒤 기록 최신화는 남아 있어야 한다.
- [x] **Step 5: 빌드·전체 테스트·SwiftLint를 통과시키고, 대기 화면을 시뮬레이터에서 연다.** 이 시점에는 목표 선택과 시작 버튼이 계속 보이고, 러닝·기록 탭을 왕복해도 요약 문구가 다시 나타나지 않는지 확인한다.
- [x] **Step 6: 커밋 전 코드리뷰를 받고, 검증 스탬프를 갱신한 뒤 커밋한다.**

```text
refactor: 러닝 대기 화면의 기록 요약 의존성 제거

- RunPage가 기록 데이터를 읽지 않도록 생성자와 RootView 주입을 정리한다
- 첫 러닝·이번 주·지난 러닝을 고르던 대기 요약 계산과 문구를 제거한다
- 저장 뒤 기록 탭을 최신화하는 기존 공유 스토어 흐름은 유지한다
```

## Task 2: `오늘의 러닝 → 목표 설정 → 시작` 위계 구현

**목적:** 첫 화면에서 사용자가 무엇을 고르고 어떻게 시작하는지 바로 이해하게 한다. 기존 자유·거리·시간 입력 동작과 시작 버튼의 유효성 제어는 유지한다.

**Files:**
- Modify: `Trace/Pages/RunPage/RunPage.swift`
- Modify: `TraceUITests/TraceUITests.swift`

- [ ] **Step 1: UI 회귀 테스트를 먼저 작성해 실패시킨다.** 러닝 탭을 연 뒤 `오늘의 러닝` 제목, `자유`·`거리`·`시간` 선택지, `run.goalPicker`, `run.startButton`이 보이는지 단언한다. `거리`를 선택했을 때 `km` 입력 안내가 나타나는지도 단언한다.
- [ ] **Step 2: 대기 화면의 시각적 순서를 구현한다.** `startControls`를 상단 `오늘의 러닝` 제목·짧은 안내, 가운데 목표 선택/입력 카드, 하단의 가장 강한 `시작` 행동 순서로 배치한다. 자유 모드에서는 추가 입력을 보이지 않게 하고, 거리·시간 모드에서는 기존 입력·단위·오류 문구를 그대로 쓴다.
- [ ] **Step 3: 테스트에 필요한 안정적 식별자를 유지한다.** 기존 `run.goalPicker`와 `run.startButton`은 보존하고, 화면 제목에는 `run.idle.title`을 부여한다. 제품 기능의 접근성 범위를 넓히지 않는다.
- [ ] **Step 4: 단위/UI 테스트를 통과시킨다.** 목표 입력의 파싱·검증·직전값 프리필·시작 시 저장을 다루는 `RunPageViewModelTests`와 새 UI 테스트가 모두 통과해야 한다.
- [ ] **Step 5: 시뮬레이터로 라이트·다크 모드에서 직접 확인한다.** 러닝 탭에서 자유/거리/시간을 차례로 선택해 입력 영역과 버튼 활성 상태를 확인한다. 큰 글자 크기에서도 제목·세그먼트·입력 카드·시작 버튼이 잘리거나 겹치지 않는지 스크린샷으로 확인한다.
- [ ] **Step 6: 빌드·전체 테스트·SwiftLint와 커밋 전 코드리뷰를 통과시키고, 검증 스탬프 갱신 후 커밋한다.**

```text
feat: 러닝 대기 화면을 목표 설정 흐름으로 정리

- 오늘의 러닝과 자유·거리·시간 목표를 첫 화면의 순서대로 배치한다
- 목표 입력 뒤 시작 행동이 가장 분명하게 이어지도록 대기 화면 위계를 조정한다
- 목표 선택과 시작 진입점을 UI 테스트로 고정해 회귀를 막는다
```

## Task 3: GPX 실기기 QA 준비과 진행 기록

**목적:** 실제로 뛰지 않아도 목표 설정부터 저장·기록 반영까지 확인할 수 있게 하고, 제품 의도가 맞는지 사용자의 판단을 받는다.

**Files:**
- Create: `docs/qa/2026-07-26-run-idle-polish-device-checklist.md`
- Modify: `docs/roadmap.md`
- Modify: 이 플랜의 Task 3 체크박스

- [ ] **Step 1: 사용자용 실기기 체크리스트를 작성한다.** 기존 `trace-history-tab-5km-1min-pace.gpx` 사용법을 짧게 연결하고, 다음을 한 세션으로 묶는다: 자유/거리/시간 중 하나 선택 → 목표값 확인 → 시작 → GPX 위치 시뮬레이션 → 종료·저장 → 기록 탭에서 방금 기록 확인.
- [ ] **Step 2: 의도 일치 확인을 별도 체크포인트로 둔다.** 사용자가 첫 러닝 화면을 보고 “무엇을 설정하고 어떻게 시작하는지”를 바로 이해했는지, 요약·지난 기록을 찾게 되는지 메모할 수 있게 한다. VoiceOver·실제 GPS 정확도·배터리는 이번 QA의 통과 조건이 아님을 명시한다.
- [ ] **Step 3: 체크리스트를 사용자에게 직접 제시한다.** 자동 검증·시뮬레이터 확인이 끝난 뒤 파일 링크와 함께 수행 순서를 안내한다. 이 단계에서는 마일스톤을 완료로 표시하지 않는다.
- [ ] **Step 4: 문서 검토 후 계획 진행 표시와 함께 커밋한다.**

```text
docs: 러닝 대기 화면 실기기 QA 경로 추가

- GPX 위치 시뮬레이션으로 목표 설정부터 저장·기록 반영까지 확인하는 절차를 남긴다
- 첫 화면의 목표 설정과 시작 흐름이 즉시 이해되는지 사용자 판단 항목을 둔다
- 실제 GPS 정확도와 배터리 평가는 이번 범위에서 분리한다
```

## Task 4: 실기기 QA 결과 수용 및 마일스톤 종료

**Files:**
- Modify: `docs/qa/2026-07-26-run-idle-polish-device-checklist.md`
- Modify: `docs/roadmap.md`
- Modify: 이 플랜의 Task 4 체크박스

- [ ] **Step 1: 사용자 QA 결과를 받아 항목별로 분류한다.** 스펙과 다른 실제 고장은 같은 브랜치에서 버그 경로로 수정한다. 의도 불일치는 `docs/backlog.md`에만 기록하고 다음 마일스톤 후보로 넘긴다.
- [ ] **Step 2: 통과 또는 수정 완료한 결과를 체크리스트에 기록한다.** 새 런을 직접 한 것처럼 추정하지 않고 사용자 확인 사실과 범위를 적는다.
- [ ] **Step 3: 수용된 경우에만 roadmap의 `run-idle-polish`를 완료로 바꾸고 플랜 체크박스를 갱신한다.** MVP17의 나머지 마일스톤 상태는 건드리지 않는다.
- [ ] **Step 4: 문서 변경을 검토하고 커밋한다.**

```text
docs: 러닝 대기 화면 실기기 QA 수용 기록

- 목표 설정부터 시작·저장·기록 확인까지의 사용자 QA 결과를 남긴다
- 대기 화면의 의도 일치 판정을 마일스톤 완료 근거로 연결한다
- 후속 개선은 버그와 분리해 백로그로 이관한다
```

## 플랜 자체 검토 (2026-07-26)

- [x] 설계 문서의 한 가지 질문과 화면 순서를 구현 태스크에 직접 연결했다.
- [x] 기록 탭 최신화는 유지하면서 RunPage만 기록 로딩에서 분리하는 경계를 명시했다.
- [x] 목표 입력·카운트다운·저장 플로우를 바꾸지 않는 비범위를 명시했다.
- [x] 자동·시뮬레이터·GPX 실기기 검증과 각 태스크의 커밋 경계를 분리했다.
