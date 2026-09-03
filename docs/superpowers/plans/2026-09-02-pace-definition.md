# pace-definition 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`(권장) 또는
> `superpowers:executing-plans`로 Task 단위로 실행한다. Step은 체크박스(`- [ ]`)로 추적한다.
> **체크박스는 그 Task의 커밋에 함께 담는다**(`docs/agent-rules/git.md`) — 체크박스만 고치는
> 커밋을 따로 만들지 않는다.

**Goal:** 트래킹 화면과 잠금화면 모두에서 현재 페이스와 평균 페이스를 나란히 보여 주고 라벨로
구분하며, 현재 페이스 창을 30초에서 10초로 줄인다.

**Architecture:** 도메인 안쪽부터 바깥으로 간다 — ①`RunTrack`의 창 상수 → ②`RunSession`에 활동
시간 기준 평균 페이스 계산 지점을 만든다 → ③트래킹 화면 → ④Live Activity 상태와 전달 →
⑤위젯 표시. 새 계산 로직은 ②뿐이고 나머지는 이미 있는 값을 꺼내 쓴다.

**Tech Stack:** Swift · SwiftUI · ActivityKit(Live Activity) · WidgetKit · XCTest

**설계 정본:** [`2026-09-02-pace-definition-design.md`](../specs/2026-09-02-pace-definition-design.md)

## Global Constraints

- **검증은 `docs/agent-rules/testing.md`의 Baseline을 따른다** — 빌드 → 테스트 → 린트 순이며,
  명령을 이 문서에 복사하지 않는다. 테스트는 반드시 raw bash `xcodebuild ... -parallel-testing-enabled NO test`로
  실행한다(XcodeBuildMCP의 테스트 툴 금지).
- 시뮬레이터는 **iOS 26.5 런타임**으로 고정한다. 세션 시작 시 UDID를 한 번 정하고 끝까지 바꾸지 않는다.
- 커밋 메시지는 `tag: 한국어 제목`(50자 이내, 마침표 없음) + **본문 3~4줄**이다.
  `Co-Authored-By:`는 훅이 차단한다.
- 페이스 표기는 기존 `RunPaceFormatter.string(secondsPerKm:)`을 쓴다. **표시 반올림은 넣지 않는다**
  (설계 「채택하지 않은 안」).
- **발화(`RunAudioCoach`·`RunAnnouncementBuilder`)는 건드리지 않는다.** 평균 페이스 그대로다.
- **평균 페이스 계산식을 새로 적지 않는다.** Task 2가 만드는 `RunSession`의 지점을 쓴다.
- 실기기 QA 체크리스트 작성·결과 수용·로드맵 갱신은 **마일스톤 종료 절차** 소관이라 Task에 넣지 않는다.

---

### Task 1: 현재 페이스 창을 10초로 줄인다

**Files:**
- Modify: `Trace/Domain/RunTracking/Entity/RunTrack.swift:8`
- Test: `TraceTests/RunTrackTests.swift:50-58`

**Interfaces:**
- Consumes: 없음
- Produces: `RunTrack.currentPaceWindowSeconds: TimeInterval = 10` — Task 3의 주석이 이 값을 가리킨다

- [x] **Step 1: 기존 테스트를 10초 기준으로 다시 쓴다**

`TraceTests/RunTrackTests.swift:50`의 `test_현재페이스는_최근30초_유효속도의_평균이다`를
아래로 **교체한다**(이름과 본문을 함께 바꾼다 — 지금 샘플 배치가 30초 창을 전제한다).

```swift
    func test_현재페이스는_최근10초_유효속도의_평균이다() {
        var track = RunTrack()
        track.append(sample(at: 0, speed: 10))   // 윈도 밖(마지막 기준 40초 전)
        track.append(sample(at: 25, speed: 8))   // 윈도 밖(15초 전) — 30초 창이었다면 포함됐다
        track.append(sample(at: 32, speed: -1))  // 음수 속도는 무시
        track.append(sample(at: 35, speed: 2))
        track.append(sample(at: 40, speed: 4))
        // 유효 속도 = [2, 4] → 평균 3m/s → 1000/3 ≈ 333초/km
        XCTAssertEqual(track.currentPaceSecondsPerKm ?? -1, 1000.0 / 3.0, accuracy: 1)
    }

    func test_현재페이스_윈도_경계에_걸친_샘플은_포함된다() {
        var track = RunTrack()
        track.append(sample(at: 29, speed: 10))  // 마지막 기준 11초 전 — 밖
        track.append(sample(at: 30, speed: 2))   // 마지막 기준 정확히 10초 전 — 경계, 포함
        track.append(sample(at: 40, speed: 4))
        // 유효 속도 = [2, 4] → 평균 3m/s
        XCTAssertEqual(track.currentPaceSecondsPerKm ?? -1, 1000.0 / 3.0, accuracy: 1)
    }
```

- [x] **Step 2: 테스트가 실패하는지 확인한다**

Baseline의 테스트 명령을 `-only-testing:TraceTests/RunTrackTests`로 좁혀 실행한다.
기대: 첫 테스트가 **FAIL** — 30초 창이면 25초 샘플(speed 8)이 포함돼 평균이 `(8+2+4)/3 ≈ 4.67 m/s`,
페이스가 약 214초/km로 나와 기댓값 333과 어긋난다.

- [x] **Step 3: 창 상수를 10으로 바꾸고 근거를 남긴다**

`RunTrack.swift:8`을 교체한다.

```swift
    /// 현재 페이스 창(초). 이 지표는 「지금 얼마나 빠른가」를 말하므로 최신성이 먼저다 —
    /// 창이 길면 이미 지나간 속도가 섞여 오르막·내리막 전환을 늦게 따라온다.
    /// 업계 관행은 5~10초다(Garmin 약 5초, Timex Global Trainer 5초 평균).
    /// 더 줄이지 않는 이유: `RunLocationTracker`가 `distanceFilter = 5`(m)를 써서 러닝 중 샘플
    /// 간격이 약 2초이고, 5초 창이면 평균 낼 샘플이 2~3개뿐이라 GPS 오차가 상쇄되지 않는다.
    /// 근거: docs/superpowers/specs/2026-09-02-pace-definition-design.md §3
    static let currentPaceWindowSeconds: TimeInterval = 10
```

- [x] **Step 4: 테스트가 통과하는지 확인한다**

같은 명령을 다시 실행한다. 기대: `RunTrackTests` 전부 **PASS**.

- [x] **Step 5: 커밋한다**

Baseline 3종(빌드·테스트·린트)을 통과시키고 검증 스탬프를 찍은 뒤 커밋한다.

```bash
git add Trace/Domain/RunTracking/Entity/RunTrack.swift TraceTests/RunTrackTests.swift \
        docs/superpowers/plans/2026-09-02-pace-definition.md
```

```text
refactor: 현재 페이스 창을 10초로 줄인다

- 30초는 이미 지나간 속도가 섞여 지금 상태를 늦게 따라온다
- 업계 관행 5~10초 중 10초를 골랐다 — 5초는 평균 낼 샘플이 2~3개뿐이다
- 왜 그 값인지 근거를 상수 주석에 남겨 다시 잠정값이 되지 않게 한다
```

---

### Task 2: `RunSession`에 활동 시간 기준 평균 페이스 계산 지점을 만든다

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift` (`summaryActiveElapsedSeconds` 아래, 약 `:112` 뒤)
- Test: `TraceTests/RunSessionTests.swift`

**Interfaces:**
- Consumes: `RunSession.activeElapsedSeconds(now:)` · `RunSession.track.totalDistanceMeters`
- Produces: `func averagePaceSecondsPerKm(now: Date = Date()) -> Double?` — Task 4가 이것을 쓴다.
  다음 사이클 `pace-dedup`이 나머지 네 곳을 이 자리로 모아 온다

- [x] **Step 1: 실패하는 테스트를 쓴다**

`TraceTests/RunSessionTests.swift`에 아래 두 테스트를 추가한다.

```swift
    func test_평균페이스는_일시정지를_제외한_활동시간_기준이다() async throws {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 100))
        await waitUntil { session.track.totalDistanceMeters > 50 }

        let started = try XCTUnwrap(session.startedAt)
        session.pause(now: started.addingTimeInterval(20))
        session.resume(now: started.addingTimeInterval(80))

        // 벽시계 120초 − 일시정지 60초 = 활동 60초, 거리 약 100m → 60 / 0.1 = 600초/km
        let pace = try XCTUnwrap(session.averagePaceSecondsPerKm(now: started.addingTimeInterval(120)))
        XCTAssertEqual(pace, 600, accuracy: 20)
    }

    func test_거리가_없으면_평균페이스는_nil이다() async {
        await session.start()
        XCTAssertNil(session.averagePaceSecondsPerKm())
    }
```

- [x] **Step 2: 테스트가 실패하는지 확인한다**

Baseline의 테스트 명령을 `-only-testing:TraceTests/RunSessionTests`로 좁혀 실행한다.
기대: **컴파일 실패** — `value of type 'RunSession' has no member 'averagePaceSecondsPerKm'`.

> ⚠️ Step 4에서 처음 통과시킬 때 **기댓값 600이 실제 계산과 맞는지 확인한다.**
> `latOffsetMeters: 100`은 위도 환산이라 정확히 100m가 아닐 수 있고, `startedAt`은 첫 샘플 도착에
> 따라오는 `beginTracking(now:)` 시점에 잡힌다. 어긋나면 `accuracy`를 넓히지 말고
> **실제 거리·활동 시간을 출력해 기댓값 쪽을 맞춘다** — 정확도를 낮추면 회귀를 못 잡는다.

- [x] **Step 3: 계산 지점을 추가한다**

`RunSession.swift`의 `summaryActiveElapsedSeconds` 아래에 넣는다.

```swift
    /// 평균 페이스(초/km) — 활동 시간(일시정지 제외) ÷ 거리.
    /// 발화(`RunAudioCoach`)·요약 화면·저장된 기록과 **같은 기준**이다(MVP14 §3.1).
    /// `RunTrack.averagePaceSecondsPerKm`는 GPS 샘플 구간(일시정지 포함) 기준이라 값이 다르므로
    /// 화면·발화용으로 쓰지 않는다.
    ///
    /// 같은 식이 지금 네 곳에 복사돼 있고, 다음 사이클 `pace-dedup`이 그것들을 이 자리로 모은다
    /// (근거: docs/superpowers/specs/2026-09-02-pace-definition-design.md §2-2).
    func averagePaceSecondsPerKm(now: Date = Date()) -> Double? {
        let distanceMeters = track.totalDistanceMeters
        guard distanceMeters > 0,
              let elapsed = activeElapsedSeconds(now: now), elapsed > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }
```

- [x] **Step 4: 테스트가 통과하는지 확인한다**

같은 명령을 다시 실행한다. 기대: `RunSessionTests` 전부 **PASS**.

- [x] **Step 5: 커밋한다**

```bash
git add Trace/Application/RunTracking/RunSession.swift TraceTests/RunSessionTests.swift \
        docs/superpowers/plans/2026-09-02-pace-definition.md
```

```text
feat: 활동 시간 기준 평균 페이스 계산 지점을 만든다

- 잠금화면에 평균 페이스를 넘기려면 세션에서 꺼낼 공개 지점이 필요한데 없었다
- 같은 식을 컨트롤러에 또 적으면 다섯 번째 복사가 되므로 한 곳을 먼저 만든다
- 다음 사이클 pace-dedup이 흩어진 네 곳을 이 자리로 모아 온다
```

---

### Task 3: 트래킹 화면 보조 행에 현재 페이스를 더한다

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` (`summaryAveragePaceSecondsPerKm` 아래, 약 `:125` 뒤)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift:12-21`
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: `RunTrack.currentPaceSecondsPerKm` (Task 1이 창을 정한 그 값)
- Produces: `RunPageViewModel.currentPaceSecondsPerKm: Double?`

- [x] **Step 1: 실패하는 테스트를 쓴다**

`TraceTests/RunPageViewModelTests.swift`에 추가한다.

```swift
    func test_현재페이스는_트랙의_값을_그대로_노출한다() async {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(5), latOffsetMeters: 20))
        await waitUntil { session.track.samples.count == 2 }
        XCTAssertEqual(viewModel.currentPaceSecondsPerKm, session.track.currentPaceSecondsPerKm)
    }

    func test_샘플이_없으면_현재페이스는_nil이다() {
        XCTAssertNil(viewModel.currentPaceSecondsPerKm)
    }
```

> `waitUntil` 헬퍼는 이 파일 `:43`에 이미 있고, `await session.start()` → `stream.yield(...)` →
> `await waitUntil { session.state == .tracking }` 패턴도 `:62` 이하 기존 테스트들과 같다.

- [x] **Step 2: 테스트가 실패하는지 확인한다**

Baseline의 테스트 명령을 `-only-testing:TraceTests/RunPageViewModelTests`로 좁혀 실행한다.
기대: **컴파일 실패** — `has no member 'currentPaceSecondsPerKm'`.

- [x] **Step 3: 뷰모델에 프로퍼티를 추가한다**

`RunPageViewModel.swift`의 `summaryAveragePaceSecondsPerKm` 아래에 넣는다.

```swift
    /// 트래킹 화면 현재 페이스 — 최근 `RunTrack.currentPaceWindowSeconds`초의 GPS 속도 평균.
    /// 평균 페이스와 나란히 두어 두 지표를 한 화면에서 비교할 수 있게 한다
    /// (근거: docs/superpowers/specs/2026-09-02-pace-definition-design.md §1).
    var currentPaceSecondsPerKm: Double? {
        session.track.currentPaceSecondsPerKm
    }
```

- [x] **Step 4: 테스트가 통과하는지 확인한다**

같은 명령을 다시 실행한다. 기대: **PASS**.

- [x] **Step 5: 보조 행에 세 번째 항목을 넣는다**

`RunPage+StatsPanelComponent.swift:12-21`을 교체한다.

```swift
            // 보조 행: 시간 · 평균 페이스 · 현재 페이스 (ui-direction §3의 보조 행을 셋으로 늘린다)
            HStack(spacing: 24) {
                secondaryStat(label: "시간") { elapsedText }
                secondaryStat(label: "평균 페이스") {
                    Text(RunPaceFormatter.string(secondsPerKm: viewModel.liveAveragePaceSecondsPerKm))
                        .font(DesignToken.Typography.runSecondaryStat)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                }
                secondaryStat(label: "현재 페이스") {
                    Text(RunPaceFormatter.string(secondsPerKm: viewModel.currentPaceSecondsPerKm))
                        .font(DesignToken.Typography.runSecondaryStat)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                }
            }
```

> `spacing`을 36에서 24로 줄인 것은 출발값이다. 다음 Step에서 실제로 보고 정한다.

- [x] **Step 6: 시뮬레이터로 배치를 확인한다**

빌드·설치·실행 후 러닝을 시작해 트래킹 화면을 본다(XcodeBuildMCP의 빌드·실행·스크린샷은 사용
가능하다 — 금지된 것은 테스트 실행뿐이다).

확인할 것: **세 항목의 숫자와 라벨이 잘리거나 겹치지 않는가.** 좁으면 `spacing`을 더 줄이거나
라벨을 「평균」·「현재」로 짧게 바꾼다. **거리(주인공)의 크기와 위치는 바꾸지 않는다.**

> 실측 결과: `spacing: 24`(출발값) 그대로 시간·평균 페이스·현재 페이스 세 항목이 잘리거나
> 겹치지 않고 표시됐다(2026-09-02, iPhone 17 Pro/iOS 26.5 시뮬레이터). 조정 불필요.
> **위치 시뮬레이션 경로 주의**: 문서 절차(`project.pbxproj` 파일 참조 + 스킴
> `LocationScenarioReference`)를 그대로 배선했으나, 이 세션의 실행 경로(XcodeBuildMCP →
> `xcodebuild`+`simctl`, Xcode IDE 아님)에서는 스킴의 `LocationScenarioReference`가 적용되지
> 않았다(`simctl location <udid> list`가 내장 시나리오만 보여주고 이 GPX를 노출하지 않음 — IDE
> 전용 기능으로 보인다). 대신 같은 GPX의 좌표·페이스(37.566500,126.978000 →
> 37.611415,126.978000, 100m/6초=16.6667 m/s, 전 구간 동일 경도라 직선)를
> `xcrun simctl location <udid> start --speed=16.6667 --distance=100 <시작> <끝>`으로 재현해
> 확인했다 — GPX 재생과 동일한 CoreLocation 입력이지만, 스킴 배선 자체가 이 실행 경로에서
> 동작하는지는 검증하지 못했다. Xcode IDE로 직접 실행하는 세션에서 재확인 필요.

- [x] **Step 7: 커밋한다**

```bash
git add Trace/Pages/RunPage/RunPageViewModel.swift \
        Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift \
        TraceTests/RunPageViewModelTests.swift \
        docs/superpowers/plans/2026-09-02-pace-definition.md
```

```text
feat: 트래킹 화면에 현재 페이스를 함께 보여준다

- 지금까지 평균과 현재를 한 화면에서 볼 자리가 앱에 없어 값이 어긋나 보일 때 비교가 안 됐다
- 보조 행을 시간·평균 페이스·현재 페이스 셋으로 늘리고 거리는 주인공 자리에 그대로 둔다
- 값은 RunTrack의 계산을 그대로 노출하며 새 계산을 만들지 않는다
```

---

### Task 4: Live Activity 상태에 평균 페이스를 싣는다

**Files:**
- Modify: `Trace/Domain/RunTracking/RunActivityAttributes.swift:7` 아래
- Modify: `Trace/Application/RunTracking/RunActivityController.swift:86-99` (`currentState()`)

**Interfaces:**
- Consumes: `RunSession.averagePaceSecondsPerKm(now:)` (Task 2)
- Produces: `RunActivityAttributes.ContentState.averagePaceSecondsPerKm: Double?` — Task 5가 표시한다

- [x] **Step 1: 상태에 필드를 추가한다**

`RunActivityAttributes.swift`의 `paceSecondsPerKm` 아래에 넣는다.

```swift
        /// 현재 페이스(초/km) — 최근 `RunTrack.currentPaceWindowSeconds`초의 GPS 속도 평균
        var paceSecondsPerKm: Double?
        /// 평균 페이스(초/km) — 활동 시간 기준. 현재 페이스와 나란히 두어 어느 지표인지 구분한다
        /// (근거: docs/superpowers/specs/2026-09-02-pace-definition-design.md §2).
        /// Live Activity 상태는 휘발성이라(디스크에 남는 blob이 아니다) 저장 포맷 호환 문제가 없다.
        var averagePaceSecondsPerKm: Double?
```

> 위 `paceSecondsPerKm` 줄에 주석이 이미 없다면 함께 붙인다 — 두 필드가 나란히 놓이면
> 이름만으로는 구분되지 않는다.

- [x] **Step 2: 컨트롤러가 값을 넘기게 한다**

`RunActivityController.swift`의 `currentState()`를 교체한다.

```swift
    private func currentState() -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            distanceMeters: session.track.totalDistanceMeters,
            paceSecondsPerKm: session.track.currentPaceSecondsPerKm,
            // 🔴 식을 여기 적지 않는다 — 세션의 계산 지점을 쓴다(설계 §2-2)
            averagePaceSecondsPerKm: session.averagePaceSecondsPerKm(),
            isPaused: session.isPaused,
            isPreparing: session.state == .countingDown || session.state == .acquiring,
            timerStart: session.displayTimerStart ?? session.startedAt ?? Date(),
            elapsedSecondsAtPause: session.isPaused ? session.activeElapsedSeconds() : nil,
            lastWaypoint: session.waypoints.lastSegmentMeters.map {
                .init(index: session.waypoints.count, segmentMeters: $0)
            }
        )
    }
```

- [x] **Step 3: 빌드가 통과하는지 확인한다**

Baseline의 빌드 명령을 실행한다. 기대: **성공.** `ContentState`를 만드는 다른 자리가 있으면
컴파일러가 인자 누락으로 잡아 주므로, 그때 같은 방식으로 값을 넘긴다.

> `RunActivityController`에는 단위 테스트가 없다. ActivityKit이 실기기·시뮬레이터 런타임에
> 의존해서다. 값이 맞는지는 Task 5의 시뮬레이터 확인과 실기기 QA에서 본다.

- [x] **Step 4: 커밋한다**

```bash
git add Trace/Domain/RunTracking/RunActivityAttributes.swift \
        Trace/Application/RunTracking/RunActivityController.swift \
        docs/superpowers/plans/2026-09-02-pace-definition.md
```

```text
feat: 잠금화면 상태에 평균 페이스를 싣는다

- 위젯 타깃은 세션을 볼 수 없어 평균 페이스를 앱이 넘겨야 한다
- 컨트롤러가 식을 새로 적지 않고 세션의 계산 지점을 호출한다
- Live Activity 상태는 휘발성이라 필드 추가에 저장 포맷 호환 문제가 없다
```

---

### Task 5: 잠금화면과 Dynamic Island에 두 페이스를 표시한다

**Files:**
- Modify: `TraceWidgets/RunLiveActivityWidget.swift:25-29` (Dynamic Island trailing) ·
  `:47-54` (잠금화면 본문) · `:137-140` (`paceText`)

**Interfaces:**
- Consumes: `RunActivityAttributes.ContentState.paceSecondsPerKm` ·
  `.averagePaceSecondsPerKm` (Task 4)
- Produces: 없음 (표시 계층)

- [x] **Step 1: 평균 페이스 포맷 함수를 추가한다**

`RunLiveActivityWidget.swift`의 `paceText` 아래에 넣는다. 기존 `paceText`의 중복 주석은 그대로 둔다
(포맷터 이중 구현 정리는 다음 사이클 `pace-dedup` 몫이다).

```swift
    // 주의: paceText와 같은 이유로 앱 타깃 RunPaceFormatter의 로직을 여기 중복 정의한다.
    private func averagePaceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        guard let pace = context.state.averagePaceSecondsPerKm, pace > 0, pace < 3600 else {
            return "--'--\""
        }
        return String(format: "%d'%02d\"", Int(pace) / 60, Int(pace) % 60)
    }
```

- [x] **Step 2: 잠금화면 본문에 평균 페이스를 넣고 라벨을 구분한다**

`:47-54`의 첫 `HStack`을 교체한다.

```swift
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                        .font(.title2)
                    metric(distanceText(context), label: "거리")
                    timeView(context, fontSize: 20)
                    metric(paceText(context), label: "현재 페이스")
                    metric(averagePaceText(context), label: "평균 페이스")
                }
```

> `spacing`을 20에서 14로 줄인 것은 출발값이다. Step 4에서 실제로 보고 정한다.

- [x] **Step 3: Dynamic Island 확장에 평균 페이스를 넣는다**

`:25-29`의 trailing 영역 라벨을 바꾸고, 그 아래 `.bottom` 영역을 새로 더한다.

```swift
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPreparing == false {
                        metric(paceText(context), label: "현재 페이스")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isPreparing == false {
                        metric(averagePaceText(context), label: "평균 페이스")
                    }
                }
```

- [x] **Step 4: 시뮬레이터로 두 배치를 확인한다**

빌드·설치·실행 후 러닝을 시작하고 화면을 잠가 잠금화면 카드를 본다. Dynamic Island는 길게 눌러
확장 상태로 본다.

확인할 것:
- 잠금화면 첫 행의 **다섯 요소가 잘리거나 겹치지 않는가.** 좁으면 ①`spacing`을 더 줄이거나
  ②평균 페이스를 두 번째 행(지금 `lastWaypoint`가 조건부로 쓰는 자리)으로 내린다
- Dynamic Island에서 「현재 페이스」·「평균 페이스」 **라벨이 잘리지 않는가.** 좁으면 그 영역만
  「현재」·「평균」으로 짧게 쓴다
- 두 숫자가 **서로 다른 값**으로 나오는가 — 같은 값만 계속 나오면 Task 4의 전달을 다시 본다

> 실측 결과(2026-09-02, iPhone 17 Pro/iOS 26.5 시뮬레이터, `xcrun simctl location <udid> start
> --speed --distance <좌표> <좌표>`로 GPS 스트림 주입 — 문서 절차의 GPX 스킴은 이 실행 경로에서
> 적용되지 않아 Task 3 발견대로 우회):
>
> - **`spacing: 14`(출발값) 그대로 다섯 요소(아이콘·거리·시간·현재 페이스·평균 페이스)가 잘리거나
>   겹치지 않았다.** 두 「좁으면」 조건 모두 발동하지 않아 조정 불필요.
> - **두 숫자가 서로 다른 값으로 나옴을 확인.** 주입 속도 2.0 m/s(=1000m/2.0s/m=500s/km) 구간에서
>   현재 페이스가 정확히 `8'20"`로 표시돼 계산이 맞는 필드를 읽고 있음을 수치로 확인했고, 평균
>   페이스는 같은 러닝 중 서로 다른 시점에 `4'50"`·`5'44"`로 관측돼 현재 페이스와 독립적으로
>   갱신됨을 확인했다.
> - **Dynamic Island 확장 영역(leading/trailing/bottom)이 이 시뮬레이터에서 빈 화면으로
>   렌더링됐다** — `.center`만 그려지고 나머지 세 영역은 내용이 보이지 않음. `git stash`로 이 Task
>   diff를 걷어낸 뒤(3영역, `.bottom` 없음) 같은 절차로 재현했을 때도 **동일하게 비었다** — 이
>   Task가 새로 만든 문제가 아님을 A/B로 확인했다. 다만 원인(시뮬레이터 렌더링 제약인지, 다른
>   요인인지)은 검증하지 않았다. 확장 라벨 잘림 확인은 설계 문서 「실기기 QA에서 확인할 것」
>   항목 2가 실기기 QA로 명시적으로 넘겨둔 항목이라, 이 시뮬레이터 세션에서 결론 내리지 않고
>   그대로 실기기 QA로 미룬다.
> - **Task 5 범위 밖의 사전 존재 갱신 간극을 발견**: `RunActivityController.observeOnce()`의 관찰
>   대상은 `session.state`·`track.totalDistanceMeters`·`waypoints.count`뿐이고(시간 아님),
>   `sync()`(→`updateActivity()`)의 유일한 호출 지점이다(grep 확인). GPS 스트림을 멈춰 이 세 값을
>   고정한 뒤 잠금화면 카드를 두 시점에서 캡처하니 거리(`0.06km`)·현재 페이스(`5'33"`)·평균
>   페이스(`5'54"`)가 바이트 단위로 동일했다. 반면 같은 카드 안에서 시스템이 자체 렌더링하는
>   시간(`Text(timerInterval:)`)의 분 자리는 `1:--`→`6:--`로 실제로 앞서 나갔다(초 자리가 캡처에서
>   `--`로 보이는 것은 렌더링 타이밍에 따른 캡처 아티팩트지만, 분 자리 이동 자체는 실제 갱신이다) —
>   같은 프레임 안에서 "위젯은 계속 다시 그려지는데 ContentState 필드만 멈춰 있다"를 보여주는
>   양성 대조로, `activity.update()`가 그 사이에 한 번도 호출되지 않았다는 것을 직접 뒷받침한다.
>   표시된 평균 페이스(`5'54"`)는 카드에 표시된 경과 시간(1분대~6분대)보다 훨씬 이전의, 평균을
>   계산한 짧은 구간 기준 값과 정합적이다 — 정확한 시각을 역산할 근거는 없지만 "멈추기 직전 값을
>   계속 물고 있다"는 방향과는 맞는다. **표시 코드(이 Task)의 결함이 아니라 갱신 트리거
>   집합(Task 5 이전부터 있던 코드)의 사전 존재 간극**이며, 다음 사이클에서 다룰 이슈로 남긴다.

> **최종 브랜치 리뷰 후속 확인(2026-09-02, 같은 iPhone 17 Pro/iOS 26.5 시뮬레이터)**: 최종
> 브랜치 리뷰어(Opus)가 실측 폰트 폭을 계산해 "지금까지 확인된 상태는 가장 좁은 케이스였고,
> 일시정지·10km+·1시간+ 같은 평범한 상태에서는 첫 행이 넘칠 가능성이 크다"고 지적했다.
> `xcrun simctl location <udid> set <lat>,<lng>`을 여러 번 연속 호출해(GPX/`start` 대신 순간
> 이동 방식으로) 짧은 시간 안에 큰 거리를 만든 뒤 확인:
> - **일시정지 직후, 거리 0.00km·경과 38초 상태에서 이미 잘림·겹침을 확인.** `pausedElapsedText`가
>   즉시 `H:MM:SS`(예: `0:00:38`)가 되면서 "0.00km"가 "0.00k"/"m"로 두 줄에 걸쳐 잘리고, "현재
>   페이스"·"평균 페이스" 라벨도 각각 "현재"/"페이스", "평균"/"페이스"로 두 줄에 걸쳐 겹쳤다 —
>   위 Step 4 실측(짧은 상태, 미정지)이 놓친 케이스였다.
> - **1차 조치**(`metric(_:label:)`·`timeView`에 `.lineLimit(1).minimumScaleFactor(0.75)`)로
>   재확인: 겹침·두 줄 표시는 없어졌지만, 거리 12.22km·경과 52초로 일시정지한 상태에서 거리
>   값이 `11.12...`처럼 말줄임표로 잘렸다 — `minimumScaleFactor(0.75)`로도 다섯 요소가 한 줄에
>   다 들어가지 않았다.
> - **2차 조치**: 플랜이 이미 적어 둔 대비책대로 평균 페이스를 둘째 행(`lastWaypoint`가 조건부로
>   쓰던 자리)으로 내렸다. 첫 행은 아이콘·거리·시간·현재 페이스 넷만 남는다. 재확인 결과 거리
>   12.22km·경과 0:00:52 일시정지 상태에서 "12.22km"가 말줄임 없이 온전히 보이고, 다섯 요소
>   전부(첫 행 넷 + 둘째 행 평균 페이스) 잘리거나 겹치지 않았다.
> - 시간 자릿수(`H:MM:SS`의 시 자리)는 1~9시간 구간에서 폭이 늘지 않으므로(항상 한 자리) 실제로
>   1시간을 채워 확인하지 않았다 — 폭에 영향을 주는 것은 "일시정지 여부"이지 "몇 시간째인지"가
>   아니다.
> - **후속 확인 두 가지(2차 조치 자체 검증 겸용)**: ① 둘째 행이 평균 페이스와 경유점 텍스트로
>   **동시에** 찬 상태 — 평균 페이스 텍스트에만 `.lineLimit(1)`이 있고 `.minimumScaleFactor`가
>   없어 경유점 텍스트와 잘림 정책이 다르던 것을 발견해 둘 다 `.lineLimit(1).minimumScaleFactor(0.75)`로
>   맞췄다. ② 일시정지가 아닌 **달리는 중** 상태 — `Text(timerInterval:)`에 `minimumScaleFactor`를
>   준 것이 매초 흔들림을 만들지 않는지 정적 스크린샷만으로는 완전히 배제할 수 없어 실측했다.
>   `simctl location start --speed=1.2 --distance=30`(느린 속도)로 실제 두 자리 분 페이스를
>   만든 뒤(포인트 버튼도 눌러 경유점 채움) 달리는 중 잠금화면을 캡처: 첫 행 "0.07km · 2:04 ·
>   13'53″"(현재 페이스 두 자리 분)와 둘째 행 "평균 페이스 24'24″  P1 · 0.00 km  [포인트]"가
>   모두 축소 없이 원래 크기로 한 줄에 들어갔다 — 이 폭에서는 `minimumScaleFactor`가 아예
>   발동하지 않아 흔들림 우려 자체가 없다.
> - **주의(실기기 QA로 넘김) — 결과로 닫음(2026-09-03)**: `metric(_:label:)`은 잠금화면과
>   Dynamic Island 확장(`.leading`/`.trailing`/`.bottom`)이 공유한다. 이번 조치로 이
>   함수에 붙인 `.lineLimit(1).minimumScaleFactor(0.75)`가 Dynamic Island 쪽 잘림 동작도
>   "줄바꿈"에서 "축소 후 말줄임"으로 바꿔 놓았는데, 이 시뮬레이터에서는 확장 영역
>   자체가 빈 화면으로 렌더링돼(백로그 항목 참고) 실제로 확인하지 못했다. 실기기에서
>   확인한 결과 잠금화면·Dynamic Island 양쪽 모두 라벨이 잘리지 않고 정상 렌더링됐다 —
>   이 변경 자체는 문제없음. (단, Dynamic Island는 러닝 중 leading/trailing 영역 자체가
>   안 보이는 별개의 사전 존재 문제가 있다 — `docs/backlog.md` 참고, 잘림과 무관한
>   문제라 이 메모의 걱정과는 다른 사안이다.)

- [x] **Step 5: 커밋한다**

```bash
git add TraceWidgets/RunLiveActivityWidget.swift \
        docs/superpowers/plans/2026-09-02-pace-definition.md
```

```text
feat: 잠금화면에 현재·평균 페이스를 함께 보여준다

- 라벨이 「페이스」뿐이라 발화가 읽는 평균과 다른 값인 줄 알 수 없었다
- 두 값을 나란히 두고 각각 현재 페이스·평균 페이스로 이름을 붙인다
- Dynamic Island는 세 영역이 차 있어 평균을 bottom 영역에 놓는다
```

---

## 이 계획이 다루지 않는 것

- **실기기 QA** — 체크리스트 작성·제시·결과 수용은 마일스톤 종료 절차가 담당한다.
  확인 항목은 설계 문서의 「실기기 QA에서 확인할 것」에 있다.
- **로드맵·현황판 갱신** — 같은 종료 절차 소관이다.
  > ⚠️ **이 줄을 다음 계획이 그대로 따라 쓰지 말 것(2026-09-03 정정).** 종료 절차를 계획 밖으로
  > 밀어낸 결과 실행 지점이 사라져 종료 4~6단계가 통째로 빠졌다. 지금 규칙은 **계획 끝에 「종료」
  > 절과 대상 지정 체크박스를 두는 것**이다 — `docs/agent-rules/workflow.md` 2항,
  > 근거는 `docs/workflow-audit.md` §5-9.
- **평균 페이스 계산 중복 정리와 앱·위젯 포맷터 이중 구현** — 다음 사이클 `pace-dedup`이 맡는다.
  이 계획은 Task 2에서 그 **목적지만** 만든다.
