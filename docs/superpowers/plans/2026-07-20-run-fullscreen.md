# MVP16 run-fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러닝 탭을 지도 없는 나이키식 숫자 중심 전체화면으로 재구성하고, 기록 목록·상세를 전체화면 페이지 문법으로 정리하며, 기록 상세 지도에 포인트 구간별 색상 폴리라인을 표시한다.

**Architecture:** 러닝 탭에서 `Map`을 완전히 제거하고(지도는 코스 탭 + 기록 상세 두 곳만), 화면 전환은 기존 `RunSession.State` 스위치를 그대로 쓴다. 카운트다운은 뷰 오버레이가 아니라 `RunSession.State.countingDown`이라는 **세션 상태**로 승격해, 탭바 숨김 판정(`AppTab.isTabBarHidden`)이 카운트다운부터 걸리게 만든다. 포인트 구간 폴리라인은 샘플 스트림을 포인트 타임스탬프로 자르는 **Domain 순수 함수**로 계산하고, 지도와 구간 표가 같은 1-기반 index로 `SegmentPalette` 색을 공유한다.

**Tech Stack:** SwiftUI (iOS 17+), Swift 6, MapKit(기록 상세만), XCTest. 외부 의존성 추가 없음.

**Specs:** `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md`(§1–2) + `docs/superpowers/specs/2026-07-19-mvp16-ui-direction-design.md`(§3·§4·§5·§6·§7)

## Global Constraints

- Swift 6 언어 모드, 격리 기본값은 클래식(기본 nonisolated) + UI 타입에 명시 `@MainActor` (`project-decisions.md`)
- 색·폰트는 `DesignToken`만 사용 (직접 `Color`/`Font` 리터럴 금지). 새 폰트가 필요하면 `Tokens.swift`에 추가하고 쓴다
- ViewModel은 MapKit을 import하지 않는다 (아키텍처 규칙) — 이번 사이클에서 `RunPageViewModel`의 MapKit import는 제거된다
- 러닝 탭에는 `Map`을 두지 않는다 (킥오프 §2.3 — 트래킹·대기·요약 전부). 지도는 **코스 탭 + 기록 상세** 두 곳뿐
- 러닝 플로우(카운트다운~요약 닫기 전) 동안 탭바는 숨는다 (킥오프 §2.2). 기록 목록·상세는 대기 화면과 같은 계층이므로 **탭바 노출** (ui-direction §5)
- 트래킹 계산 로직·저장 스키마는 건드리지 않는다 (킥오프 §1 "표현/구조만 바꾸는 개편"). 예외는 Task 1의 `State` 확장 — 표현(탭바 숨김)을 올바르게 만들기 위한 최소 변경이며 거리·시간 계산에는 영향이 없다
- 평균 페이스는 **활동 시간(`activeElapsedSeconds`) 기준**으로만 계산한다. `RunTrack.averagePaceSecondsPerKm`(GPS 샘플 구간 = 일시정지 포함)을 화면에 쓰지 않는다 — 요약 화면·발화와 값이 어긋난다 (MVP14 §3.1)
- 검증 명령 (모든 태스크 공통, 시뮬레이터는 iPhone 17 Pro / iOS 26.5 = `D887D0A4-074C-4AFB-8D08-D87329D0EFD4` 고정, 세션당 하나만):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build`
  - 테스트: 같은 명령에 `-parallel-testing-enabled NO test` (병렬 금지 필수)
  - 린트: `swiftlint`
  - 각각 통과 후 `touch .git/trace-verify-build.ok` / `trace-verify-test.ok` / `trace-verify-lint.ok` (pre-commit 훅 요건)
- 커밋: `scripts/trace-commit.sh -m "<tag>: 한국어 제목\n\n- 본문 3~4줄" -- <paths>` — 경로 명시 스테이징, `git add -A` 금지

---

## 배경 — 왜 카운트다운을 세션 상태로 올리는가

현재 카운트다운은 `RunPageViewModel.countdown`(뷰 전용 상태)이고, 그동안 `RunSession.state`는 `.idle`이다. `AppTab.isTabBarHidden(runState:)`가 `runState != .idle`이므로 **카운트다운 중에는 탭바가 살아 있다.** 실기기 QA(2026-07-20)에서 발견된 갇힘 버그가 여기서 나왔다: 카운트다운 중 코스 탭으로 이동 → 트래킹 시작 → 탭바 숨김 → 코스 탭에 탭바 없이 갇힘.

지금은 `RootView`의 `onChange`가 "트래킹이 시작되면 러닝 탭으로 끌고 온다"로 **증상만** 막아둔 상태다(커밋 `c7d55fe`). 이번 사이클은 그 우회를 제거하고, 카운트다운을 러닝 플로우의 일부로 만들어 탭 전환 창 자체를 없앤다.

**주의 — `countdown != nil`로 판정하면 안 된다.** `startTapped`는 `await session.prepareStart(...)`(정확도 게이트, 시스템 프롬프트 포함)를 먼저 기다리고 그 **뒤에** `countdown`을 세팅한다. 그 await 구간은 여전히 `countdown == nil`이라 탭 전환 창이 그대로 열려 있다. 그래서 상태 전환은 `prepareStart`의 **첫 suspension point 이전**(동기 구간)에서 일어나야 한다.

**추가 함정 — `streamEnded()`의 예열 분기.** 예열 중 스트림이 죽으면(권한 회수 등) `isPreparing = false`만 하고 `return`한다. 지금은 state가 `.idle`이라 무해했지만, `.countingDown`을 도입하면 이 경로가 상태를 복원하지 않아 **탭바 없는 카운트다운 화면에 영구히 갇힌다.** Task 1에서 반드시 함께 고친다.

---

### Task 1: 카운트다운을 `RunSession.State`로 승격 + 갇힘 우회 제거

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift` (State enum, `prepareStart`, `beginTracking`, `cancelPreparation`, `streamEnded`)
- Modify: `Trace/Application/RunTracking/RunActivityController.swift:52`
- Modify: `Trace/Application/RunTracking/RunAudioCoach.swift:55`
- Modify: `Trace/App/RootView.swift` (onChange 우회 제거)
- Modify: `Trace/Pages/RunPage/RunPage.swift` (`controls` 스위치에 임시 케이스 — 새 케이스를 안 채우면 non-exhaustive로 빌드가 깨진다)
- Test: `TraceTests/RunSessionTests.swift` (상태 전이), `TraceTests/AppTabTests.swift` (탭바 판정)

**Interfaces:**
- Produces: `RunSession.State.countingDown` — Task 3의 `RunPage.controls` 스위치가 이 케이스로 카운트다운 화면을 그린다. `AppTab.isTabBarHidden(runState:)`는 이미 `runState != .idle`이라 **구현 수정 불필요**(자동으로 카운트다운도 숨김 대상) — 테스트에 케이스만 추가한다.

- [ ] **Step 1: 실패하는 테스트 작성**

상태 전이는 전부 `RunSession`에서 일어나므로 ViewModel의 카운트다운 루프를 태우지 않고 세션을 직접 검증한다. `TraceTests/RunSessionTests.swift`의 `MockRunLocationStream`은 이미 `finish()`로 스트림 종료를 재현할 수 있으므로 프로덕션에 테스트 훅을 넣지 않는다.

`TraceTests/RunSessionTests.swift`의 `RunSessionTests` 클래스 안(마지막 테스트 메서드 뒤)에 추가한다. 필드 `stream`·`session`과 헬퍼 `waitUntil`은 이미 그 클래스에 있다:

```swift
    func test_준비가_끝나면_countingDown_상태다() async {
        // 카운트다운 구간부터 러닝 플로우 — 탭바 숨김이 여기서부터 걸려야 한다
        let started = await session.prepareStart()
        XCTAssertTrue(started)
        XCTAssertEqual(session.state, .countingDown)
    }

    func test_정확도_거부로_시작에_실패하면_idle로_복귀한다() async {
        stream.accuracy = .reduced
        stream.accuracyAfterRequest = .reduced
        let started = await session.prepareStart()
        XCTAssertFalse(started)
        XCTAssertEqual(session.state, .idle)
    }

    func test_카운트다운_취소하면_idle로_돌아온다() async {
        _ = await session.prepareStart()
        session.cancelPreparation()
        XCTAssertEqual(session.state, .idle)
    }

    func test_카운트다운이_끝나면_acquiring으로_넘어간다() async {
        _ = await session.prepareStart()
        session.beginTracking()
        XCTAssertEqual(session.state, .acquiring)
    }

    func test_예열_중_스트림이_죽으면_countingDown에_갇히지_않는다() async {
        // streamEnded의 isPreparing 분기가 상태를 복원하지 않으면 탭바 없는 화면에 영구히 갇힌다
        _ = await session.prepareStart()
        stream.finish()
        await waitUntil { session.state == .idle }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastStartFailure, .permissionDenied)
    }
```

`TraceTests/AppTabTests.swift`의 기존 상태 나열 테스트에 한 줄 추가한다 (`XCTAssertFalse(...idle)` 다음 줄):

```swift
        XCTAssertTrue(AppTab.isTabBarHidden(runState: .countingDown))
```

- [ ] **Step 2: 테스트가 실패하는 것 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`

Expected: 컴파일 실패 — `RunSession.State`에 `.countingDown` 케이스 없음

- [ ] **Step 3: `RunSession` 상태 전환 구현**

`Trace/Application/RunTracking/RunSession.swift`의 `State` enum에 케이스를 추가한다 (`case idle` 바로 아래):

```swift
    enum State: Equatable {
        case idle
        /// 시작 탭 직후 카운트다운(3-2-1) 구간 — 아직 트래킹 전이지만 러닝 플로우에 속한다.
        /// 탭바 숨김 판정(`AppTab.isTabBarHidden`)이 이 상태부터 걸려, 카운트다운 중 탭을
        /// 옮겼다가 탭바 없이 갇히던 버그를 구조적으로 차단한다(MVP16 run-fullscreen).
        case countingDown
        case acquiring
        case tracking
        case paused
        case summary
    }
```

`prepareStart`에서 상태를 올린다. **첫 `await` 이전**(동기 구간)이어야 한다 — 정확도 게이트를 기다리는 동안에도 탭바가 이미 사라져 있어야 전환 창이 안 열린다:

```swift
    func prepareStart(goal: RunGoal = .open) async -> Bool {
        guard state == .idle, isPreparing == false else { return false }
        isPreparing = true // 아래 정확도 재요청 await 지점 전에 닫아야 재진입 창이 안 생긴다
        lastStartFailure = nil
        // 첫 suspension point 이전(동기 구간)에 올린다 — 정확도 게이트를 await하는 동안에도
        // 탭바가 이미 사라져 있어야 탭 전환 창이 열리지 않는다(run-fullscreen Task 1).
        state = .countingDown

        var accuracy = locationStream.currentAccuracy()
        if accuracy == .reduced {
            accuracy = await locationStream.requestSessionFullAccuracy()
        }
        guard accuracy == .full else {
            lastStartFailure = .reducedAccuracy
            isPreparing = false // 재시도를 막지 않도록 원복
            state = .idle // 시작 실패 — 대기 화면으로 복귀
            return false
        }
```

(이 아래 `track = RunTrack()`부터 `return true`까지는 그대로 둔다.)

`beginTracking`의 guard를 새 상태에 맞추고, 실패 경로에서 상태를 복원한다:

```swift
    /// 카운트다운 종료 시점 — 여기부터가 세션 시작(활동 시간·거리 적산 기준, 스펙 §1.1)
    func beginTracking(now: Date = Date()) {
        guard isPreparing, state == .countingDown else { return }
        isPreparing = false
        guard lastStartFailure == nil else { // 예열 중 스트림 사망(권한 회수)
            stopStream()
            state = .idle
            return
        }
        startedAt = now
        state = .acquiring
    }
```

`cancelPreparation`에서 상태를 되돌린다 (`goalAchieved = false` 다음 줄에 추가):

```swift
    /// 카운트다운 취소 — 예열 스트림을 내리고 대기 상태로 되돌린다
    func cancelPreparation() {
        guard isPreparing else { return }
        isPreparing = false
        stopStream()
        startedAt = nil
        goal = .open
        goalHalfReached = false
        goalAchieved = false
        state = .idle // 카운트다운 화면을 닫고 대기 화면으로(run-fullscreen Task 1)
    }
```

`streamEnded`의 예열 분기에서 상태를 복원한다 — **이게 없으면 탭바 없는 카운트다운 화면에 영구히 갇힌다**:

```swift
    /// 스트림이 밖에서 끊긴 경우(러닝 도중 권한 회수 등) — 수집분을 버리지 않는다(스펙 §6)
    private func streamEnded() {
        if isPreparing { // 예열 중 스트림 사망(권한 회수 등) — beginTracking이 시작을 거부하게 표시
            isPreparing = false
            locationStream.stopUpdates()
            lastStartFailure = .permissionDenied
            state = .idle // 카운트다운 화면에 갇히지 않게 대기 화면으로 복귀(run-fullscreen Task 1)
            return
        }
```

(이 아래 `guard isActive else { return }`부터는 그대로 둔다.)

- [ ] **Step 4: 비뷰 소비자 2곳 대응**

`Trace/Application/RunTracking/RunActivityController.swift`의 `sync()` — 카운트다운 중에는 Live Activity를 시작하지 않는다(아직 트래킹 전):

```swift
        case .idle, .countingDown, .acquiring, .summary:
            endActivityIfNeeded()
```

`Trace/Application/RunTracking/RunAudioCoach.swift`의 `announceStateTransitionIfNeeded()` — 시작 발화 트리거 전이가 `.idle → .acquiring`에서 `.countingDown → .acquiring`으로 바뀐다:

```swift
        case (.countingDown, .acquiring):
            lastAnnouncedKm = 0 // 새 러닝 — km 카운터 리셋
            goalHalfAnnounced = false
            goalAchievedAnnounced = false
            lastWaypointCount = 0
            announcer.announce(RunAnnouncementBuilder.start)
```

`TraceTests/RunAudioCoachTests.swift`가 이 전이를 직접 만들어 검증한다면(실제 `RunSession`이 아니라 상태를 흉내 내는 방식이면) 같은 전이로 갱신한다. 실제 세션의 `start()`를 태우는 방식이면 수정 없이 통과한다 — 테스트를 먼저 읽고 판단한다.

- [ ] **Step 5: `RunPage.controls`에 임시 케이스 채우기**

`RunPage.controls`는 `default` 없는 `switch viewModel.session.state`라, 새 케이스를 안 채우면 **이 태스크에서 빌드가 깨진다.** 정식 카운트다운 화면은 Task 3에서 만들므로, 여기서는 GPS 대기 패널을 임시로 연결해 빌드를 통과시킨다.

`Trace/Pages/RunPage/RunPage.swift`의 `controls`:

```swift
    @ViewBuilder
    private var controls: some View {
        switch viewModel.session.state {
        case .idle:
            startControls
        case .countingDown:
            acquiringPanel // 임시 — Task 3에서 RunCountdownScreen으로 교체
        case .acquiring:
            acquiringPanel
        case .tracking, .paused:
            RunStatsPanel(viewModel: viewModel)
        case .summary:
            RunSummaryPanel(viewModel: viewModel)
        }
    }
```

이 태스크에서 카운트다운 오버레이(`.overlay { if let count = viewModel.countdown ... }`)는 **아직 지우지 않는다** — Task 2에서 지도와 함께 정리한다. 그때까지는 임시 패널 위에 기존 오버레이가 겹쳐 보이지만, 태스크 사이의 과도기 상태이고 동작은 정상이다.

- [ ] **Step 6: `RootView` 갇힘 우회 제거**

`Trace/App/RootView.swift`에서 `.onChange(of: container.runSession.state)` 블록 전체와 그 위 주석(41행대 주석은 남기고 47~56행의 카운트다운 우회 주석+블록)을 삭제한다. 카운트다운 시작 즉시 탭바가 사라지고, 그 시점 사용자는 러닝 탭에 있으므로(시작 버튼이 거기 있다) 갇힘 경로 자체가 없다.

삭제 후 `body`는 이렇게 끝난다:

```swift
            // 러닝 플로우(카운트다운~요약 닫기 전) 동안 탭바 자체를 제거 — 킥오프 §2.2.
            // RunSession은 @Observable이라 state 변화가 body를 다시 평가한다.
            if !AppTab.isTabBarHidden(runState: container.runSession.state) {
                TraceTabBar(selection: $selectedTab)
            }
        }
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`

Expected: 전체 PASS. 컴파일러가 `switch session.state`를 쓰는 모든 지점에서 누락 케이스를 잡아주므로, 새 에러가 나면 그 지점도 위 원칙(카운트다운 = 아직 트래킹 전)에 맞춰 처리한다.

- [ ] **Step 8: Commit**

```bash
scripts/trace-commit.sh -m "feat: 카운트다운을 러닝 세션 상태로 승격

- RunSession.State에 countingDown 추가, 첫 await 이전 동기 구간에서 전환
- 예열 스트림 사망·취소·시작 실패 경로 전부 idle 복원 (갇힘 차단)
- RootView의 강제 탭 전환 우회 제거 — 탭 전환 창 자체가 사라짐" -- Trace/Application/RunTracking/RunSession.swift Trace/Application/RunTracking/RunActivityController.swift Trace/Application/RunTracking/RunAudioCoach.swift Trace/App/RootView.swift Trace/Pages/RunPage/RunPage.swift TraceTests/RunSessionTests.swift TraceTests/AppTabTests.swift
```

---

### Task 2: 러닝 탭 지도 제거 + 대기 화면 재구성

**Files:**
- Modify: `Trace/Pages/RunPage/RunPage.swift` (runMap 제거, 대기 화면 §4 레이아웃)
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` (지도 상태·MapKit import 제거)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (recenterButton 제거)
- Modify: `Trace/DesignSystem/Tokens.swift` (러닝 화면 타이포 토큰 추가)
- Delete: `Trace/Pages/RunPage/PolylineThrottle.swift`
- Delete: `TraceTests/PolylineThrottleTests.swift`

**Interfaces:**
- Consumes: Task 1의 `RunSession.State.countingDown` (스위치 케이스는 Task 3에서 채운다 — 이 태스크에서는 컴파일만 통과하게 `EmptyView()` 자리표시로 두지 않고, 임시로 `acquiringPanel`을 재사용한다)
- Produces: `DesignToken.Typography.runDistanceHero` / `.runDistanceUnit` / `.runSecondaryStat` / `.runCountdown` — Task 3의 트래킹·카운트다운 화면이 소비한다

- [ ] **Step 1: 디자인 토큰 추가**

`Trace/DesignSystem/Tokens.swift`의 `enum Typography` 안, `static let subtitle` 다음 줄에 추가한다:

```swift
        /// 러닝 트래킹 화면의 주인공 숫자(ui-direction §3) — monospacedDigit()과 함께 써서 자릿수 흔들림을 막는다
        static let runDistanceHero = Font.system(size: 84, weight: .bold, design: .rounded)
        static let runDistanceUnit = Font.system(size: 20, weight: .semibold, design: .rounded)
        /// 주인공 숫자 위 보조 행(시간·평균 페이스)
        static let runSecondaryStat = Font.system(size: 28, weight: .semibold, design: .rounded)
        /// 카운트다운 3-2-1
        static let runCountdown = Font.system(size: 160, weight: .heavy, design: .rounded)
        /// 대기 화면 대형 시작 버튼 라벨
        static let runStartButton = Font.system(size: 22, weight: .bold, design: .rounded)
```

- [ ] **Step 2: ViewModel에서 지도 상태 제거**

`Trace/Pages/RunPage/RunPageViewModel.swift`에서 아래를 **삭제**한다:

- `import MapKit` (1행대) — 남은 코드에 MapKit 타입이 없어야 한다. 지운 뒤 `import SwiftUI`도 실제로 쓰이는지 확인하고, 안 쓰이면 함께 지운다(`Observation`·`Foundation`은 남는다)
- `var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)` 프로퍼티
- `private(set) var displayedCoordinates: [CLLocationCoordinate2D] = []` 프로퍼티
- `private var polylineThrottle = PolylineThrottle()` 프로퍼티
- `func refreshPolylineIfDue(now:)` 메서드 전체
- `func recenter()` 메서드 전체
- `private static func fittingRegion(for:)` 메서드 전체

`startTapped()` 끝부분에서 지도 관련 3줄을 지운다 — 남는 형태:

```swift
        guard session.lastStartFailure == nil else {
            presentStartFailure()
            return
        }
        summaryElapsedSeconds = nil
    }
```

`endRun()`에서 카메라 핏을 지운다 — 남는 형태:

```swift
    func endRun() {
        waypointCardDismissTask?.cancel()
        waypointCard = nil
        summaryElapsedSeconds = session.activeElapsedSeconds()
        session.finish()
    }
```

`closeSummary()`도 같이 정리한다:

```swift
    func closeSummary() {
        session.dismissSummary()
    }
```

- [ ] **Step 3: 죽은 코드 파일 삭제**

```bash
git rm Trace/Pages/RunPage/PolylineThrottle.swift TraceTests/PolylineThrottleTests.swift
```

Xcode 프로젝트가 파일 시스템 동기화 방식이 아니라면 `Trace.xcodeproj/project.pbxproj`에서 두 파일 참조도 함께 제거해야 한다. 먼저 `grep -n "PolylineThrottle" Trace.xcodeproj/project.pbxproj`로 참조 유무를 확인하고, 참조가 나오면 해당 라인들을 제거한다. 참조가 없으면(동기화 방식) 그대로 진행한다.

- [ ] **Step 4: `RunPage` 지도 제거 + 대기 화면 재구성**

`Trace/Pages/RunPage/RunPage.swift`의 `body`를 아래로 교체한다. 지도 대신 Surface 배경을 깔고, 카운트다운 오버레이는 제거한다(Task 3에서 `controls` 스위치의 정식 케이스가 된다):

```swift
    var body: some View {
        ZStack(alignment: .bottom) {
            DesignToken.Color.surface2.ignoresSafeArea() // 지도 제거 — 러닝 탭은 Surface 배경(킥오프 §2.3)
            controls
        }
        .alert("정확한 위치가 꺼져 있어요", isPresented: $viewModel.showsAccuracyAlert) {
            Button("설정 열기") { openSettings() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("러닝 경로를 기록하려면 설정 > 개인정보 보호 > 위치 서비스에서 정확한 위치를 켜 주세요.")
        }
        .alert("위치 권한이 필요해요", isPresented: $viewModel.showsPermissionAlert) {
            Button("설정 열기") { openSettings() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("러닝을 기록하려면 위치 접근을 허용해 주세요.")
        }
        .onChange(of: viewModel.countdown) { _, newValue in
            guard newValue != nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 숫자마다 햅틱(스펙 §1.1)
        }
        .sheet(isPresented: $showsHistory) {
            RunHistorySheet(viewModel: historyViewModel)
        }
    }
```

`runMap` 프로퍼티와 `countdownOverlay(count:)` 메서드를 **삭제**한다. 파일 맨 위 `import MapKit`도 삭제한다.

`controls` 스위치는 Task 1 Step 5에서 이미 `.countingDown → acquiringPanel` 임시 연결이 들어가 있다. 이 태스크에서는 **그대로 둔다**(Task 3에서 정식 화면으로 교체).

`startControls`를 §4 와이어프레임(우상단 기록 · 목표 선택 · 대형 시작 버튼)에 맞춰 전체화면 레이아웃으로 교체한다. 기존 `.overlay(alignment: .topTrailing)`의 기록 버튼도 여기로 흡수하므로, `body`에서 그 overlay는 이미 지웠다:

```swift
    private var startControls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showsHistory = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(GlassIconButtonStyle())
                .accessibilityLabel("러닝 기록")
                .accessibilityIdentifier("run.historyButton")
            }
            .padding(.horizontal, DesignToken.Size.screenMargin)

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

`startButton`의 `.padding(.bottom, 40)`은 위 `Spacer().frame(height: 40)`로 대체됐으므로 제거하고, 라벨 폰트를 토큰으로 바꾼다:

```swift
    private var startButton: some View {
        Button {
            goalFieldFocused = false
            Task { await viewModel.startTapped() }
        } label: {
            Text("시작")
                .font(DesignToken.Typography.runStartButton)
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 132, height: 132) // 화면 주인공 — 지도가 사라진 만큼 키운다(ui-direction §4)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .disabled(viewModel.isGoalInputValid == false)
        .opacity(viewModel.isGoalInputValid ? 1 : 0.5)
        .accessibilityIdentifier("run.startButton")
    }
```

`goalInputField`의 직접 폰트 리터럴도 토큰으로 교체한다:

```swift
                .font(DesignToken.Typography.runSecondaryStat)
```

`acquiringPanel`의 `.padding(.bottom, 40)`은 그대로 둔다.

- [ ] **Step 5: `recenterButton` 제거**

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`에서 `.overlay(alignment: .topTrailing) { recenterButton }` 한 줄과 `private var recenterButton: some View { ... }` 메서드 전체를 삭제한다. 지도가 없으므로 "현위치로" 동작 자체가 사라진다.

- [ ] **Step 6: 빌드 + 테스트 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`

Expected: 빌드 성공 + 전체 PASS. `PolylineThrottleTests` 4개가 목록에서 사라진다. `RunPageViewModelTests`에 `displayedCoordinates`/`cameraPosition`을 참조하는 테스트가 남아 있으면 그 테스트도 함께 삭제한다(지도가 없어졌으므로 검증 대상이 아니다).

Run: `swiftlint`
Expected: 경고 0

- [ ] **Step 7: Commit**

```bash
scripts/trace-commit.sh -m "feat: 러닝 탭 지도 제거 + 대기 화면 전체화면 재구성

- Map·폴리라인 스로틀·카메라 상태 전부 제거 (지도는 코스 탭+기록 상세만)
- 대기 화면을 기록 버튼·목표 선택·대형 시작 버튼 중심으로 재배치
- 러닝 화면 타이포 토큰 추가" -- Trace/Pages/RunPage/RunPage.swift Trace/Pages/RunPage/RunPageViewModel.swift Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift Trace/DesignSystem/Tokens.swift Trace/Pages/RunPage/PolylineThrottle.swift TraceTests/PolylineThrottleTests.swift
```

---

### Task 3: 트래킹 화면 "거리가 주인공" + 카운트다운 전체화면 (TDD)

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` (라이브 평균 페이스 추가)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (`RunStatsPanel` 전체화면 재구성)
- Create: `Trace/Pages/RunPage/UIComponent/RunPage+CountdownComponent.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift` (`controls`의 `.countingDown` 케이스 연결)
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: `DesignToken.Typography.runDistanceHero` / `.runDistanceUnit` / `.runSecondaryStat` / `.runCountdown` (Task 2)
- Produces: `RunCountdownScreen(count: Int?, onCancel: () -> Void)` — `RunPage.controls`가 소비한다. `RunPageViewModel.liveAveragePaceSecondsPerKm: Double?`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunPageViewModelTests.swift`의 클래스 안에 추가한다. 필드 `stream`·`session`·`viewModel`과 헬퍼 `sample(at:latOffsetMeters:)`·`waitUntil`은 이미 그 클래스에 있다:

```swift
    func test_라이브_평균_페이스는_활동_시간_기준이다() async throws {
        // RunTrack.averagePaceSecondsPerKm(GPS 샘플 구간 = 일시정지 포함)을 쓰면
        // 같은 러닝의 요약 화면·발화와 값이 어긋난다(MVP14 §3.1) — 활동 시간 기준이어야 한다
        XCTAssertNil(viewModel.liveAveragePaceSecondsPerKm) // 거리 0이면 nil

        await session.start()
        let now = Date()
        stream.yield(sample(at: now))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: now.addingTimeInterval(60), latOffsetMeters: 200))
        await waitUntil { session.track.totalDistanceMeters > 0 }

        let distanceKm = session.track.totalDistanceMeters / 1000
        let elapsed = try XCTUnwrap(session.activeElapsedSeconds())
        XCTAssertGreaterThan(elapsed, 0)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.liveAveragePaceSecondsPerKm),
            elapsed / distanceKm,
            accuracy: 1.0
        )
    }
```

- [ ] **Step 2: 테스트가 실패하는 것 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test -only-testing:TraceTests/RunPageViewModelTests`

Expected: 컴파일 실패 — `liveAveragePaceSecondsPerKm` 없음

- [ ] **Step 3: 라이브 평균 페이스 구현**

`Trace/Pages/RunPage/RunPageViewModel.swift`의 `summaryAveragePaceSecondsPerKm` 프로퍼티 바로 위에 추가한다:

```swift
    /// 트래킹 화면 평균 페이스 — 활동 시간(일시정지 제외) 기준.
    /// `RunTrack.averagePaceSecondsPerKm`은 GPS 샘플 구간(일시정지 포함) 기준이라
    /// 같은 러닝의 요약 화면·발화(RunAudioCoach.averagePace)와 값이 어긋난다(MVP14 §3.1).
    var liveAveragePaceSecondsPerKm: Double? {
        let distanceMeters = session.track.totalDistanceMeters
        guard distanceMeters > 0,
              let elapsed = session.activeElapsedSeconds(), elapsed > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test -only-testing:TraceTests/RunPageViewModelTests`

Expected: PASS

- [ ] **Step 5: 트래킹 화면을 전체화면으로 재구성**

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`의 `RunStatsPanel.body`를 ui-direction §3 위계(보조 행 → 주인공 거리 → 목표 진행률 → 컨트롤)로 교체한다. 하단 시트 배경(`UnevenRoundedRectangle`)은 전체화면이 되었으므로 제거한다:

```swift
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 보조 행: 시간 · 평균 페이스 (ui-direction §3)
            HStack(spacing: 36) {
                secondaryStat(label: "시간") { elapsedText }
                secondaryStat(label: "평균 페이스") {
                    Text(RunPaceFormatter.string(secondsPerKm: viewModel.liveAveragePaceSecondsPerKm))
                        .font(DesignToken.Typography.runSecondaryStat)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                }
            }

            // 주인공: 누적 거리
            VStack(spacing: 0) {
                Text(String(format: "%.2f", viewModel.session.track.totalDistanceMeters / 1000))
                    .font(DesignToken.Typography.runDistanceHero)
                    .monospacedDigit()
                    .foregroundStyle(DesignToken.Color.ink)
                Text("km")
                    .font(DesignToken.Typography.runDistanceUnit)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("run.distanceHero")

            statusLine
            goalProgress

            Spacer()
            controlRow
                .padding(.horizontal, DesignToken.Size.screenMargin)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// GPS 약신호·일시정지·포인트 카드 — 셋 다 없으면 자리만 유지해 숫자가 위아래로 안 튄다
    @ViewBuilder
    private var statusLine: some View {
        VStack(spacing: 4) {
            if viewModel.session.isSignalWeak {
                Text("GPS 신호 약함")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
            }
            if viewModel.session.isPaused {
                Text("일시정지됨")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            if let card = viewModel.waypointCard {
                Text("포인트 \(card.index) · \(String(format: "%.2f", card.segmentMeters / 1000)) km")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.accent)
                    .transition(.opacity)
                    .accessibilityIdentifier("run.waypointCard")
            }
        }
        .frame(minHeight: 22)
    }

    @ViewBuilder
    private var goalProgress: some View {
        if let label = RunGoalFormatter.label(viewModel.session.goal),
           let fraction = viewModel.goalProgressFraction {
            VStack(spacing: 4) {
                HStack {
                    Text(label)
                        .font(DesignToken.Typography.chip)
                        .foregroundStyle(DesignToken.Color.ink2)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(DesignToken.Typography.chip)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink2)
                }
                ProgressView(value: fraction)
                    .tint(DesignToken.Color.accent)
            }
            .padding(.horizontal, 48)
            .padding(.top, 12)
        }
    }

    /// 컨트롤 영역 — 달리는 중엔 포인트+일시정지, 멈춘 뒤에만 종료가 더해진다(ui-direction §3).
    /// 포인트 버튼은 일시정지 중에도 자리를 지킨다(비활성 dimmed) — 버튼이 사라지면
    /// "왜 못 찍는지"가 안 보인다는 스펙 §2.2의 상태 가시화 의도가 깨진다.
    private var controlRow: some View {
        HStack(spacing: 12) {
            waypointButton
            pauseResumeButton
            if viewModel.session.isPaused {
                endButton
            }
        }
    }

    @ViewBuilder
    private var elapsedText: some View {
        if viewModel.session.isPaused {
            // 멈춘 시간 고정 표시 — activeElapsedSeconds는 일시정지 중 상수라 안전
            Text(RunDurationFormatter.string(seconds: viewModel.session.activeElapsedSeconds() ?? 0))
                .font(DesignToken.Typography.runSecondaryStat)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink2)
        } else if let timerStart = viewModel.session.displayTimerStart {
            Text(timerInterval: timerStart...Date.distantFuture, countsDown: false)
                .font(DesignToken.Typography.runSecondaryStat)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink)
        }
    }

    private func secondaryStat<Content: View>(
        label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 2) {
            content()
            Text(label)
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }
```

기존의 `private func stat(value:unit:)` 메서드는 더 이상 쓰이지 않으므로 **삭제**한다. `endButton`·`pauseResumeButton`·`waypointButton`은 그대로 둔다 — `endButton`은 일시정지 중에만 렌더되므로 홀드 링 동작은 변경 없이 유지된다.

> **동작 변경 주의(ui-direction §3 확정):** 종료는 이제 **일시정지 중에만** 노출된다. 달리는 중 종료하려면 일시정지 → 길게 눌러 종료 2단계다. 실기기 QA 시나리오에 반드시 포함한다.

- [ ] **Step 6: 카운트다운 전체화면 컴포넌트 작성**

`Trace/Pages/RunPage/UIComponent/RunPage+CountdownComponent.swift`를 새로 만든다:

```swift
import SwiftUI

/// 카운트다운 전체화면(ui-direction §3 연장 — 러닝 플로우는 시작부터 전체화면).
/// 세션이 `.countingDown`인 동안만 그려지고, 그 상태에서는 탭바가 이미 사라져 있어
/// 카운트다운 중 다른 탭으로 빠져나가는 경로 자체가 없다(run-fullscreen Task 1).
struct RunCountdownScreen: View {
    /// 3→2→1. nil이면 아직 정확도 게이트(시스템 프롬프트 포함)를 기다리는 준비 구간이다.
    let count: Int?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DesignToken.Color.surface2.ignoresSafeArea()
            if let count {
                Text("\(count)")
                    .font(DesignToken.Typography.runCountdown)
                    .foregroundStyle(DesignToken.Color.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: count)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("준비 중…")
                        .font(DesignToken.Typography.subtitle)
                        .foregroundStyle(DesignToken.Color.ink2)
                }
            }
            VStack {
                Spacer()
                Text("화면을 탭하면 취소돼요")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCancel) // 취소 = 화면 탭(스펙 §1.1)
        .accessibilityIdentifier("run.countdownScreen")
    }
}
```

- [ ] **Step 7: `controls` 스위치에 정식 연결**

`Trace/Pages/RunPage/RunPage.swift`의 `controls`에서 Task 2의 임시 연결을 교체한다:

```swift
        case .countingDown:
            RunCountdownScreen(count: viewModel.countdown) { viewModel.cancelCountdown() }
```

- [ ] **Step 8: 빌드 + 테스트 + 시뮬레이터 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`
Expected: 전체 PASS

Run: `swiftlint`
Expected: 경고 0

시뮬레이터에서 러닝 탭 → 시작을 눌러 확인한다: 카운트다운 화면이 전체화면으로 뜨고 **탭바가 보이지 않는지**, 화면 탭으로 취소하면 대기 화면+탭바로 돌아오는지.

- [ ] **Step 9: Commit**

```bash
scripts/trace-commit.sh -m "feat: 트래킹 화면 거리 중심 전체화면 + 카운트다운 화면

- 보조 행(시간·평균 페이스) 위에 누적 거리를 주인공으로 배치
- 평균 페이스를 활동 시간 기준으로 계산 (요약·발화와 동일 기준)
- 종료는 일시정지 중에만 노출, 카운트다운을 전체화면 컴포넌트로 분리" -- Trace/Pages/RunPage/RunPageViewModel.swift Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift Trace/Pages/RunPage/UIComponent/RunPage+CountdownComponent.swift Trace/Pages/RunPage/RunPage.swift TraceTests/RunPageViewModelTests.swift
```

---

### Task 4: 요약 화면 전체화면 + 기록 목록·상세를 페이지 문법으로

**Files:**
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (`RunSummaryPanel` 배경 정리)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` (`RunHistorySheet` → `RunHistoryPage`)
- Modify: `Trace/Pages/RunPage/RunPage.swift` (`.sheet` → `NavigationStack` push)

**Interfaces:**
- Consumes: Task 2가 남긴 `startControls`·`showsHistory` 상태
- Produces: `RunHistoryPage(viewModel:)` — `RunHistorySheet`를 대체하는 이름. 기록 상세 `RunRecordDetailView`는 이름·시그니처 그대로 유지되며 Task 5가 그 지도를 수정한다

- [ ] **Step 1: 요약 화면 배경 정리**

`RunSummaryPanel.body`에서 하단 시트 배경을 걷어내고 전체화면 중앙 정렬로 바꾼다. 콘텐츠 구성(수치·저장 상태·닫기)은 ui-direction §5에 따라 **그대로 유지**한다. `.padding(DesignToken.Size.sheetPadding)` 다음의 `.frame`/`.background` 두 modifier를 아래로 교체한다:

```swift
        .padding(DesignToken.Size.sheetPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
```

(`.background(DesignToken.Color.surface, in: UnevenRoundedRectangle(...))` 삭제 — 배경은 `RunPage`가 깐 `surface2`가 담당한다.)

`VStack(spacing: 16)`의 맨 위에 `Spacer()`를, `Button("닫기")` 아래에 `Spacer()`를 넣어 세로 중앙에 오게 한다.

- [ ] **Step 2: 기록 목록을 페이지로 전환**

`Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`에서 `RunHistorySheet`를 `RunHistoryPage`로 바꾼다. 자체 `NavigationStack`과 `presentationDetents`를 제거한다 — 이제 러닝 탭 안 `NavigationStack`에 **push되는 페이지**이기 때문이다:

```swift
/// 기록 목록 페이지 — 러닝 탭 대기 화면에서 push 진입(ui-direction §5).
/// 대기 화면과 같은 계층이라 탭바가 계속 보인다. 행은 요약 컬럼만 사용한다.
struct RunHistoryPage: View {
    let viewModel: RunHistoryViewModel

    var body: some View {
        Group {
            if viewModel.summaries.isEmpty {
                ContentUnavailableView(
                    "아직 기록이 없어요",
                    systemImage: "figure.run",
                    description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                )
            } else {
                historyList
            }
        }
        .navigationTitle("러닝 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
```

`historyList`의 `NavigationLink(value: summary)`는 그대로 둔다 — `navigationDestination`은 Step 3에서 러닝 탭 쪽 스택으로 옮긴다. `historyList` 이하 나머지 코드(alert 2개 포함)는 변경 없다.

- [ ] **Step 3: 러닝 탭에 `NavigationStack` 도입**

`Trace/Pages/RunPage/RunPage.swift`에서 `showsHistory` 불리언을 경로 배열로 바꾼다:

```swift
    @State private var historyPath: [RunHistoryRoute] = []
```

파일 하단(구조체 밖)에 라우트 타입을 정의한다:

```swift
/// 러닝 탭 기록 스택의 경로 — 목록과 상세 두 단계뿐이다(ui-direction §5)
enum RunHistoryRoute: Hashable {
    case list
    case detail(SavedRunSummary)
}
```

`body`의 `.sheet(...)`를 삭제하고, **대기 화면일 때만** 네비게이션 스택으로 감싼다. 트래킹·요약이 네비게이션 바를 물려받지 않도록 스코프를 좁히는 게 핵심이다. `controls`의 `.idle` 케이스를 아래로 교체한다:

```swift
        case .idle:
            NavigationStack(path: $historyPath) {
                startControls
                    .navigationBarHidden(true) // 대기 화면 자체는 네비바 없음(ui-direction §4)
                    .navigationDestination(for: RunHistoryRoute.self) { route in
                        switch route {
                        case .list:
                            RunHistoryPage(viewModel: historyViewModel)
                        case .detail(let summary):
                            RunRecordDetailView(summary: summary, viewModel: historyViewModel)
                        }
                    }
            }
```

기록 버튼의 액션을 경로 push로 바꾼다 (`startControls` 안):

```swift
                Button { historyPath.append(.list) } label: {
```

`RunHistoryPage`의 목록 행 `NavigationLink(value: summary)`가 `SavedRunSummary`를 직접 넘기므로, 라우트 타입과 맞추기 위해 값을 감싼다:

```swift
                NavigationLink(value: RunHistoryRoute.detail(summary)) {
                    RunHistoryRow(summary: summary)
                }
```

`RunHistoryPage`가 `RunHistoryRoute`를 참조하므로 두 타입이 같은 타깃에 있는지 확인한다(둘 다 `Trace` 타깃이므로 import 불필요).

- [ ] **Step 4: 빌드 + 시뮬레이터 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`
Expected: 전체 PASS

Run: `swiftlint`
Expected: 경고 0

시뮬레이터에서 확인: 대기 화면 → 기록 버튼 → 목록이 **밀려 들어오고 탭바가 계속 보이는지**, 목록 → 상세 → 뒤로가 정상인지.

- [ ] **Step 5: Commit**

```bash
scripts/trace-commit.sh -m "feat: 요약 전체화면 + 기록 목록·상세를 페이지 문법으로

- 요약 패널의 하단 시트 배경 제거, 전체화면 중앙 정렬
- 기록 목록을 모달 시트에서 러닝 탭 NavigationStack push로 전환
- 기록 화면에서 탭바 노출 유지 (대기 화면과 같은 계층)" -- Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift Trace/Pages/RunPage/RunPage.swift
```

---

### Task 5: 포인트 구간별 색상 폴리라인 + 구간 표 색 스와치 (TDD)

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunPathSegment.swift`
- Modify: `Trace/Pages/CoursePlannerPage/SegmentPalette.swift` (SwiftUI Color 접근자 추가)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` (`detailMap`, `RunWaypointsSection`)
- Test: `TraceTests/RunPathSegmentsCalculatorTests.swift` (신규)

**Interfaces:**
- Produces: `RunPathSegment { index: Int, coordinates: [CourseCoordinate] }` 및 `RunPathSegmentsCalculator.segments(samples:waypoints:) -> [RunPathSegment]`. `index`는 `RunWaypointSegment.index`와 **같은 1-기반 번호**라 지도와 구간 표가 같은 팔레트 색을 공유한다. `SegmentPalette.swiftUIColor(at:) -> Color`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunPathSegmentsCalculatorTests.swift`를 새로 만든다:

```swift
import XCTest
@testable import Trace

final class RunPathSegmentsCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(offset: TimeInterval, lat: Double) -> SavedRunSample {
        SavedRunSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat, longitude: 127.0,
            altitudeMeters: 10, speedMetersPerSecond: 3
        )
    }

    private func waypoint(offset: TimeInterval, lat: Double) -> RunWaypoint {
        RunWaypoint(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat, longitude: 127.0, totalDistanceMeters: offset
        )
    }

    func test_포인트가_없으면_빈_배열이다() {
        // 뷰가 단일색 폴백으로 그리도록 빈 배열을 준다(ui-direction §6)
        let samples = [sample(offset: 0, lat: 37.50), sample(offset: 10, lat: 37.51)]
        XCTAssertEqual(RunPathSegmentsCalculator.segments(samples: samples, waypoints: []), [])
    }

    func test_포인트_1개는_구간_2개로_나뉜다() {
        let samples = (0...4).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let segments = RunPathSegmentsCalculator.segments(
            samples: samples, waypoints: [waypoint(offset: 20, lat: 37.52)]
        )
        XCTAssertEqual(segments.map(\.index), [1, 2])
    }

    func test_이웃_구간은_경계_좌표를_공유해_선이_끊기지_않는다() {
        let samples = (0...4).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let segments = RunPathSegmentsCalculator.segments(
            samples: samples, waypoints: [waypoint(offset: 20, lat: 37.52)]
        )
        XCTAssertEqual(segments[0].coordinates.last, segments[1].coordinates.first)
    }

    func test_구간_번호는_구간_표와_같은_1기반_번호다() {
        // 지도 색과 표 색이 대응하려면 RunWaypointSegmentsCalculator와 번호 체계가 같아야 한다
        let samples = (0...6).map { sample(offset: TimeInterval($0) * 10, lat: 37.50 + Double($0) * 0.01) }
        let waypoints = [waypoint(offset: 20, lat: 37.52), waypoint(offset: 40, lat: 37.54)]
        let paths = RunPathSegmentsCalculator.segments(samples: samples, waypoints: waypoints)
        let rows = RunWaypointSegmentsCalculator.segments(waypoints: waypoints, totalDistanceMeters: 60)
        XCTAssertEqual(paths.map(\.index), rows.map(\.index))
    }

    func test_샘플이_2개_미만이면_빈_배열이다() {
        XCTAssertEqual(
            RunPathSegmentsCalculator.segments(
                samples: [sample(offset: 0, lat: 37.5)], waypoints: [waypoint(offset: 0, lat: 37.5)]
            ),
            []
        )
    }
}
```

- [ ] **Step 2: 테스트가 실패하는 것 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test -only-testing:TraceTests/RunPathSegmentsCalculatorTests`

Expected: 컴파일 실패 — `RunPathSegment`, `RunPathSegmentsCalculator` 없음

- [ ] **Step 3: Domain 분할 로직 구현**

`Trace/Domain/RunTracking/Entity/RunPathSegment.swift`를 새로 만든다:

```swift
import Foundation

/// 포인트 경계에서 잘린 경로 구간 — 기록 상세 지도의 구간별 색상 폴리라인용(ui-direction §6).
/// `index`는 `RunWaypointSegment.index`와 같은 1-기반 번호라 지도와 구간 표가 같은 팔레트 색을 쓴다.
struct RunPathSegment: Equatable, Sendable {
    let index: Int
    let coordinates: [CourseCoordinate]
}

enum RunPathSegmentsCalculator {
    /// 샘플 스트림을 포인트 타임스탬프 경계에서 자른다.
    /// 경계 샘플은 앞뒤 구간이 함께 포함해(공유) 선이 끊겨 보이지 않는다.
    /// 포인트가 없으면 빈 배열 — 뷰가 현행 단일색 폴리라인으로 폴백한다(ui-direction §6).
    static func segments(samples: [SavedRunSample], waypoints: [RunWaypoint]) -> [RunPathSegment] {
        guard waypoints.isEmpty == false, samples.count >= 2 else { return [] }
        var result: [RunPathSegment] = []
        var startIndex = 0
        for (offset, waypoint) in waypoints.enumerated() {
            guard let endIndex = samples.lastIndex(where: { $0.timestamp <= waypoint.timestamp })
            else { continue }
            if endIndex > startIndex {
                result.append(RunPathSegment(
                    index: offset + 1,
                    coordinates: samples[startIndex...endIndex].map(\.coordinate)
                ))
            }
            startIndex = max(startIndex, endIndex)
        }
        // 마지막 포인트 → 종료 구간. 번호는 표의 마지막 행(waypoints.count + 1)과 일치한다.
        if startIndex < samples.count - 1 {
            result.append(RunPathSegment(
                index: waypoints.count + 1,
                coordinates: samples[startIndex...].map(\.coordinate)
            ))
        }
        return result
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test -only-testing:TraceTests/RunPathSegmentsCalculatorTests`

Expected: 5개 전부 PASS

- [ ] **Step 5: 팔레트에 SwiftUI 접근자 추가**

`Trace/Pages/CoursePlannerPage/SegmentPalette.swift`를 교체한다. 기존 `color(at:)`(UIColor, MKMapView용)는 그대로 두고 SwiftUI용을 더한다:

```swift
import SwiftUI
import UIKit

enum SegmentPalette {
    static func color(at index: Int) -> UIColor {
        UIColor(named: "Seg\(index % 6)") ?? .systemBlue
    }

    /// SwiftUI Map/스와치용 — 기록 상세의 구간 폴리라인과 구간 표가 같은 색을 쓴다(ui-direction §6)
    static func swiftUIColor(at index: Int) -> Color {
        Color(uiColor: color(at: index))
    }
}
```

- [ ] **Step 6: 기록 상세 지도에 구간 색상 적용**

`Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`의 `detailMap`에서 단일 폴리라인을 구간별 폴리라인으로 바꾼다. 포인트가 없으면 기존 단일색 그대로다:

```swift
    @ViewBuilder
    private var detailMap: some View {
        if let loadedRun, loadedRun.samples.count >= 2 {
            let coordinates = loadedRun.samples.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            let pathSegments = RunPathSegmentsCalculator.segments(
                samples: loadedRun.samples, waypoints: loadedRun.waypoints
            )
            Map(initialPosition: RunRecordDetailView.fittedPosition(for: coordinates)) {
                if pathSegments.isEmpty {
                    // 포인트 없는 기록은 현행 단일색 유지(ui-direction §6)
                    MapPolyline(coordinates: coordinates)
                        .stroke(DesignToken.Color.accent, lineWidth: 5)
                } else {
                    ForEach(pathSegments, id: \.index) { segment in
                        MapPolyline(coordinates: segment.coordinates.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(SegmentPalette.swiftUIColor(at: segment.index), lineWidth: 5)
                    }
                }
                ForEach(Array(loadedRun.waypoints.enumerated()), id: \.offset) { index, waypoint in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: waypoint.latitude, longitude: waypoint.longitude
                    )) {
                        WaypointMarkerBadge(number: index + 1)
                    }
                }
            }
        } else if loadFinished {
            ContentUnavailableView(
                "경로를 불러올 수 없어요",
                systemImage: "map",
                description: Text("기록 데이터에 문제가 있어 경로 표시만 건너뜁니다")
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

> **왕복 겹침은 무대응**이 확정 기본값이다(ui-direction §6) — 겹치면 나중에 그린 구간이 위로 온다. 오프셋 렌더링 이식은 트리거 대기 항목이다.

- [ ] **Step 7: 구간 표에 색 스와치 추가**

같은 파일 `RunWaypointsSection`의 행에서, 라벨 앞에 지도와 같은 색 점을 넣는다 — "표와 지도가 색으로 대응"이 §6의 요구다:

```swift
            ForEach(segments, id: \.index) { segment in
                HStack {
                    Circle()
                        .fill(SegmentPalette.swiftUIColor(at: segment.index))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true) // 색은 보조 채널 — 라벨이 이미 구간을 말한다
                    Text(Self.label(for: segment))
                        .font(DesignToken.Typography.segmentRowTitle)
                        .foregroundStyle(DesignToken.Color.ink)
                    Spacer()
```

(이 아래 거리 텍스트·삭제 버튼 부분은 그대로 둔다.)

- [ ] **Step 8: 빌드 + 전체 테스트 + 시뮬레이터 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`
Expected: 전체 PASS

Run: `swiftlint`
Expected: 경고 0

포인트가 있는 기존 기록이 시뮬레이터에 없으면 이 단계의 육안 확인은 생략하고 Task 6의 실기기 QA 항목으로 넘긴다.

- [ ] **Step 9: Commit**

```bash
scripts/trace-commit.sh -m "feat: 기록 상세 포인트 구간별 색상 폴리라인

- 샘플 스트림을 포인트 타임스탬프로 자르는 Domain 순수 함수 추가
- 지도 구간과 구간 표가 같은 1기반 번호로 SegmentPalette 색 공유
- 포인트 없는 기록은 단일색 유지" -- Trace/Domain/RunTracking/Entity/RunPathSegment.swift Trace/Pages/CoursePlannerPage/SegmentPalette.swift Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift TraceTests/RunPathSegmentsCalculatorTests.swift
```

---

### Task 6: 통합 검증 + 문서 갱신 + 실기기 QA 체크리스트

**Files:**
- Modify: `docs/roadmap.md` (run-fullscreen 마일스톤 `[x]`)
- Modify: `docs/agent-rules/project-decisions.md` (카운트다운 상태 승격 결정 기록)
- Create: `docs/qa/2026-07-20-run-fullscreen-device-checklist.md`

- [ ] **Step 1: 전체 회귀 검증**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test`
Expected: 전체 PASS, 실패 0

Run: `swiftlint`
Expected: 경고 0

Run: `grep -rn "PolylineThrottle\|displayedCoordinates\|cameraPosition" Trace TraceTests --include="*.swift" | grep -v CoursePlanner`
Expected: 출력 없음 (러닝 탭 지도 잔재가 남지 않았는지 확인)

- [ ] **Step 2: 시뮬레이터 통합 확인**

시뮬레이터에서 아래를 순서대로 확인한다. 하나라도 어긋나면 고치고 Step 1로 돌아간다.

1. 러닝 탭 대기 화면에 지도가 없고 탭바가 보인다
2. 시작 → 카운트다운 전체화면, **탭바 없음**
3. 카운트다운 중 화면 탭 → 대기 화면 + 탭바 복귀
4. 대기 화면 → 기록 버튼 → 목록 push, **탭바 계속 보임** → 상세 → 뒤로

- [ ] **Step 3: 로드맵 마일스톤 완료 처리**

`docs/roadmap.md`의 MVP16 `run-fullscreen` 항목을 `- [ ]`에서 `- [x]`로 바꾸고, 설명을 실제 구현 내용으로 갱신한다. 카운트다운 아이디어가 이번 사이클에 포함됐다는 것(현행 강제 탭 전환 우회 제거)을 명시한다. 플랜 경로(`docs/superpowers/plans/2026-07-20-run-fullscreen.md`)와 QA 체크리스트 경로를 함께 적는다.

- [ ] **Step 4: 결정 기록**

`docs/agent-rules/project-decisions.md`에 한 줄 추가한다: 카운트다운을 `RunSession.State.countingDown`으로 승격해 탭바 숨김을 상태의 단일 함수로 유지하기로 한 결정과, `RootView`의 강제 탭 전환 우회를 제거한 근거(전환 창 자체 제거).

- [ ] **Step 5: 실기기 QA 체크리스트 작성**

`docs/qa/2026-07-20-run-fullscreen-device-checklist.md`를 만든다. 형식은 `docs/qa/2026-07-19-tab-restructure-device-checklist.md`와 `docs/agent-rules/testing.md`의 Real-Device Verification 템플릿을 따른다(시나리오 카드 + 평이한 언어 + 세션 단위 묶기). 최소한 아래를 시나리오로 담는다:

1. 카운트다운 중 탭 전환 시도 — 탭바가 없어 전환 자체가 불가능한지 (갇힘 버그 근본 차단 확인)
2. 카운트다운 취소 → 대기 화면 복귀 + 탭바 복귀
3. 러닝 중 종료 흐름 — **일시정지를 먼저 눌러야 종료 버튼이 나오는 것**이 실사용에서 답답하지 않은지 (동작 변경점)
4. 트래킹 화면 가독성 — 뛰면서 흘긋 봤을 때 거리가 바로 읽히는지, 자릿수가 바뀌어도 숫자가 안 흔들리는지
5. 지도 없는 러닝 탭의 체감 — "허전하다/불안하다"가 있는지 (킥오프 §2.3의 복원 트리거)
6. 기록 목록·상세 push 이동 + 탭바 노출 유지
7. 포인트 여러 개 찍은 기록의 상세 지도 — 구간마다 색이 다르고 **아래 구간 표의 색 점과 대응**하는지
8. 포인트 없는 기록의 상세 지도 — 단일색 유지
9. 백그라운드/잠금화면 — 카운트다운 중 잠갔다 돌아와도 진행되는지, Live Activity가 카운트다운 중엔 안 뜨고 트래킹부터 뜨는지

- [ ] **Step 6: Commit**

```bash
scripts/trace-commit.sh -m "docs: run-fullscreen 마일스톤 완료 + 실기기 QA 체크리스트

- 로드맵 run-fullscreen done 처리
- 카운트다운 상태 승격 결정 기록
- 실기기 QA 체크리스트 9개 시나리오 작성" -- docs/roadmap.md docs/agent-rules/project-decisions.md docs/qa/2026-07-20-run-fullscreen-device-checklist.md
```
