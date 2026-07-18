# run-detail-polish (MVP15 사이클 ①) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러닝 시작/종료/발화/목표 입력의 실사용 마감 손질 — 시작 카운트다운(삼·이·일 발화), 종료 홀드 진행 링, 발화 문안 통일·속도 조정, 목표 거리·시간 직접 입력.

**Architecture:** 기존 구조를 유지한 채 확장한다. `RunSession.start()`를 `prepareStart()`(권한·정확도 게이트 + GPS 예열) / `beginTracking()`(카운트다운 종료 시점) / `cancelPreparation()`으로 분해하고, 카운트다운 오케스트레이션은 `RunPageViewModel`이 맡는다. 발화 문안은 `RunAnnouncementBuilder` 단일 출처, 오디오 세션 수명은 `VoiceAnnouncerProtocol` 확장(hold/release/stop)으로 제어한다.

**Tech Stack:** SwiftUI, Observation(@Observable), AVSpeechSynthesizer/AVAudioSession, XCTest.

**스펙:** `docs/superpowers/specs/2026-07-17-run-detail-waypoints-design.md` §1 (경량 사이클 — 태스크별 리뷰만, 최종 브랜치 리뷰 생략)

## Global Constraints

- Swift 6 언어 모드, 기본 nonisolated + UI/상태 타입 명시 `@MainActor` (project-decisions.md)
- 발화 문안은 스펙 §1.3 표가 단일 출처 — 임의로 바꾸지 않는다
- 카운트다운 숫자 발화는 "삼" / "이" / "일" (사용자 확정 2026-07-17)
- speech rate 초깃값 0.45 (실기기 QA에서 튜닝 예정 — 상수로 분리)
- 종료 홀드 시간 1.0초 유지 (문제는 길이가 아니라 피드백 부재)
- 목표 입력: 거리 km(소수 허용) `decimalPad`, 시간 분(정수) `numberPad`, 최소값 제약 없음(>0)
- force unwrap/cast/try 금지 (swiftlint 에러)

### 태스크 공통 검증·커밋 절차 (아래 각 태스크의 "검증 & 커밋" 스텝이 이 절차를 가리킨다)

```bash
# 시뮬레이터: docs/agent-rules/testing.md의 Baseline 절차로 iOS 26.5 시뮬레이터 UDID 1개 선정(세션당 1회, 전환 금지)
xcodebuild -project Trace.xcodeproj -scheme Trace -destination "id=$SIM_UDID" build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -destination "id=$SIM_UDID" -parallel-testing-enabled NO test && touch .git/trace-verify-test.ok
swiftlint --strict && touch .git/trace-verify-lint.ok
# 커밋은 반드시 scripts/trace-commit.sh -m "<메시지>" -- <경로들> (git add -A 금지)
```

---

### Task 1: 발화 문안 표 반영 (RunAnnouncementBuilder)

**Files:**
- Modify: `Trace/Application/RunTracking/RunAnnouncementBuilder.swift`
- Modify: `Trace/Application/RunTracking/RunAudioCoach.swift` (goalAchieved 호출에 페이스 전달)
- Test: `TraceTests/RunAnnouncementBuilderTests.swift`, `TraceTests/RunAudioCoachTests.swift`

**Interfaces:**
- Consumes: 기존 `RunAnnouncementBuilder` static API, `RunAudioCoach.averagePace(elapsed:)`
- Produces: `RunAnnouncementBuilder.countdown: [String]` == `["삼", "이", "일"]` (Task 4가 사용), `start == "러닝을 시작합니다"`, `pause == "일시정지합니다"`, `goalAchieved(distanceMeters:totalSeconds:averagePaceSecondsPerKm:)`, finish 문두 `"러닝을 종료합니다. …"`

- [x] **Step 1: 실패하는 테스트 작성** — `RunAnnouncementBuilderTests.swift`에서 기존 기대값을 스펙 §1.3 표로 갱신 + 신규 케이스 추가:

```swift
func test_카운트다운_문안() {
    XCTAssertEqual(RunAnnouncementBuilder.countdown, ["삼", "이", "일"])
}

func test_시작_일시정지_문안() {
    XCTAssertEqual(RunAnnouncementBuilder.start, "러닝을 시작합니다")
    XCTAssertEqual(RunAnnouncementBuilder.pause, "일시정지합니다")
    XCTAssertEqual(RunAnnouncementBuilder.resume, "재개합니다")
}

func test_목표달성_평균페이스_포함() {
    let text = RunAnnouncementBuilder.goalAchieved(
        distanceMeters: 5000, totalSeconds: 1750, averagePaceSecondsPerKm: 350
    )
    XCTAssertEqual(text, "목표를 달성했습니다. 5킬로미터, 29분 10초, 평균 페이스 5분 50초")
}

func test_목표달성_페이스_산출불가시_절생략() {
    let text = RunAnnouncementBuilder.goalAchieved(
        distanceMeters: 5000, totalSeconds: 1750, averagePaceSecondsPerKm: nil
    )
    XCTAssertEqual(text, "목표를 달성했습니다. 5킬로미터, 29분 10초")
}

func test_종료_문안() {
    let text = RunAnnouncementBuilder.finish(
        distanceMeters: 5200, totalSeconds: 1900, averagePaceSecondsPerKm: 365
    )
    XCTAssertEqual(text, "러닝을 종료합니다. 총 5.2킬로미터, 31분 40초, 평균 페이스 6분 5초")
}
```

기존 테스트 중 `"러닝 시작"`, `"일시정지"`, `"목표 달성!"`, `"러닝 종료"` 기대값은 전부 새 문안으로 교체한다. `RunAudioCoachTests.swift`의 발화 기대 문자열도 동일하게 교체하고, 목표 달성 발화 검증에 페이스 절 포함을 반영한다.

- [x] **Step 2: 테스트 실행 — 실패 확인**

Run: 공통 절차의 test 명령 (또는 해당 테스트 클래스만 `-only-testing:TraceTests/RunAnnouncementBuilderTests`)
Expected: FAIL — 새 문안·`countdown` 미구현

- [x] **Step 3: 구현** — `RunAnnouncementBuilder.swift`:

```swift
static let start = "러닝을 시작합니다"
static let pause = "일시정지합니다"
static let resume = "재개합니다"
/// 시작 카운트다운 낭독 순서(스펙 §1.1·§1.3, 사용자 확정: 숫자 낭독)
static let countdown = ["삼", "이", "일"]

static let goalHalf = "절반 왔습니다"

/// "목표를 달성했습니다. 5킬로미터, 29분 10초, 평균 페이스 5분 50초" — 페이스 절은 finish와 동일 생략 규칙(스펙 §1.3)
static func goalAchieved(
    distanceMeters: Double, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?
) -> String {
    var text = "목표를 달성했습니다. \(spokenDistance(distanceMeters)), \(spokenDuration(totalSeconds))"
    if let pace = spokenPace(averagePaceSecondsPerKm) {
        text += ", 평균 페이스 \(pace)"
    }
    return text
}
```

`finish`는 문두만 `"러닝을 종료합니다. 총 …"`로 변경. `RunAudioCoach.announceGoalIfNeeded()`의 호출을 갱신:

```swift
let elapsed = session.activeElapsedSeconds() ?? 0
announcer.announce(RunAnnouncementBuilder.goalAchieved(
    distanceMeters: session.track.totalDistanceMeters,
    totalSeconds: elapsed,
    averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
))
```

- [x] **Step 4: 테스트 실행 — 통과 확인** (전체 스위트)

- [x] **Step 5: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 발화 문안 통일 및 목표 달성 페이스 추가

- 스펙 §1.3 문안 표 반영: 통보체 통일, 카운트다운 삼/이/일 상수 추가
- 목표 달성 발화에 평균 페이스 절 추가(종료 발화와 동일 생략 규칙)
- RunAudioCoach 목표 달성 호출에 페이스 전달" -- Trace/Application/RunTracking/RunAnnouncementBuilder.swift Trace/Application/RunTracking/RunAudioCoach.swift TraceTests/RunAnnouncementBuilderTests.swift TraceTests/RunAudioCoachTests.swift
```

---

### Task 2: VoiceAnnouncer 확장 — 세션 hold/release, stop, rate

**Files:**
- Modify: `Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift`
- Modify: `Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift`

**Interfaces:**
- Produces (Task 4가 사용):
  - `holdAudioSession()` — 오디오 세션(.playback+.duckOthers)을 잡고 유지 (카운트다운~시작 발화 덕킹 1회)
  - `releaseAudioSession()` — 보유 해제; 큐가 비어 있으면 즉시 비활성화, 아니면 큐 소진 시점에 비활성화
  - `stopSpeaking()` — 진행·대기 중 발화 즉시 중단 (카운트다운 취소)
  - 프로토콜 확장에 기본 no-op 구현 → `NoopVoiceAnnouncer`·테스트 페이크는 필요한 것만 오버라이드

- [x] **Step 1: 프로토콜 확장** — `VoiceAnnouncerProtocol.swift`:

```swift
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String)
    /// 발화 묶음(카운트다운 등) 동안 오디오 세션을 잡아 덕킹을 1회로 유지한다(스펙 §1.1)
    func holdAudioSession()
    /// hold 해제 — 남은 발화가 끝나는 시점(큐 소진)에 실제 비활성화된다
    func releaseAudioSession()
    /// 진행 중·대기 중 발화 즉시 중단(카운트다운 취소용)
    func stopSpeaking()
}

extension VoiceAnnouncerProtocol {
    func holdAudioSession() {}
    func releaseAudioSession() {}
    func stopSpeaking() {}
}
```

- [x] **Step 2: 어댑터 구현** — `SpeechVoiceAnnouncer.swift`:

```swift
/// 실기기 QA에서 튜닝해 확정한다(스펙 §1.3) — 시스템 기본 0.5가 빠르다는 실사용 피드백으로 하향
private static let speechRate: Float = 0.45
/// holdAudioSession으로 세션을 보유 중인지 — 보유 중엔 발화별 활성화/비활성화를 건너뛴다
private var isHeld = false

func announce(_ text: String) {
    if pendingCount == 0 && isHeld == false {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            return // 활성화 실패(통화 중 등) — 이번 발화는 건너뛴다
        }
    }
    pendingCount += 1
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
    utterance.rate = Self.speechRate
    synthesizer.speak(utterance)
}

func holdAudioSession() {
    guard isHeld == false else { return }
    do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true)
        isHeld = true
    } catch {
        // 활성화 실패 — 보유 없이 진행하면 announce가 발화별 활성화로 폴백한다
    }
}

func releaseAudioSession() {
    guard isHeld else { return }
    isHeld = false
    guard pendingCount == 0 else { return } // 남은 발화의 utteranceEnded가 비활성화를 맡는다
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
}

func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate) // didCancel 델리게이트가 pendingCount를 정리한다
}
```

`utteranceEnded()`의 비활성화 조건도 갱신: `guard pendingCount == 0, isHeld == false else { return }`.

- [x] **Step 3: 검증** — 어댑터는 시스템 프레임워크 경계라 기존에도 단위 테스트가 없다(RunAudioCoachTests는 페이크 사용). 전체 스위트 그린 + 빌드·린트로 확인. rate 체감은 사이클 QA 항목.

- [x] **Step 4: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: VoiceAnnouncer 세션 hold/stop 확장과 발화 속도 조정

- 카운트다운 덕킹 1회 유지를 위한 holdAudioSession/releaseAudioSession 추가
- 카운트다운 취소용 stopSpeaking 추가, 프로토콜 기본 no-op 제공
- 발화 rate 0.45 초깃값(실기기 QA 튜닝 대상) 적용" -- Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift
```

---

### Task 3: RunSession — prepareStart / beginTracking / cancelPreparation 분해

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift`
- Test: `TraceTests/RunSessionTests.swift` (기존 파일의 페이크 스트림 재사용)

**Interfaces:**
- Consumes: 기존 `RunLocationStreamProtocol` (`currentAccuracy()`, `requestSessionFullAccuracy()`, `startUpdates()`, `stopUpdates()`)
- Produces (Task 4가 사용):
  - `prepareStart(goal: RunGoal = .open) async -> Bool` — 정확도 게이트(프롬프트 포함) + 스트림 예열. 성공 시 true, 실패 시 `lastStartFailure` 설정 후 false. 상태는 `.idle` 유지
  - `beginTracking(now: Date = Date())` — `startedAt = now`, `state = .acquiring` (RunAudioCoach의 idle→acquiring 전이가 시작 발화를 담당)
  - `cancelPreparation()` — 스트림 정지, idle 필드 리셋
  - `start(goal:)`은 `prepareStart` + `beginTracking` 합성으로 유지(기존 테스트·호환)

- [x] **Step 1: 실패하는 테스트 작성** — `RunSessionTests.swift`에 추가. 기존 파일의 픽스처를 그대로 쓴다: `stream: MockRunLocationStream`(`yield(_:)`/`finish()`/`stopped`), `sample(at:latOffsetMeters:hAcc:)` 헬퍼, `waitUntil`(조건 폴링)·`drainNoOp`(부수효과 없음 전용 대기):

```swift
func test_prepareStart_예열중_샘플은_적산되지_않는다() async {
    let prepared = await session.prepareStart()
    XCTAssertTrue(prepared)
    stream.yield(sample(at: Date()))
    await drainNoOp() // 예열 샘플은 관측 가능한 상태 변화가 없어야 한다
    XCTAssertEqual(session.state, .idle)
    XCTAssertTrue(session.track.samples.isEmpty)
    XCTAssertNil(session.startedAt)
}

func test_beginTracking_이후_첫_유효샘플로_tracking_전이() async {
    _ = await session.prepareStart()
    session.beginTracking()
    XCTAssertEqual(session.state, .acquiring)
    stream.yield(sample(at: Date().addingTimeInterval(1)))
    await waitUntil { self.session.state == .tracking }
    XCTAssertEqual(session.track.samples.count, 1)
}

func test_beginTracking_전_시각의_샘플은_시작후에도_버린다() async {
    _ = await session.prepareStart()
    session.beginTracking(now: Date())
    stream.yield(sample(at: Date(timeIntervalSinceNow: -5))) // 카운트다운 중 캐시된 옛 샘플
    await drainNoOp()
    XCTAssertEqual(session.state, .acquiring) // 전이 없음
    XCTAssertTrue(session.track.samples.isEmpty)
}

func test_cancelPreparation_스트림정지_idle유지() async {
    _ = await session.prepareStart()
    session.cancelPreparation()
    XCTAssertTrue(stream.stopped)
    XCTAssertEqual(session.state, .idle)
    session.beginTracking() // 취소 후에는 no-op이어야 한다
    XCTAssertEqual(session.state, .idle)
    XCTAssertNil(session.startedAt)
}

func test_prepareStart_정확도부족이면_false와_실패사유() async {
    stream.accuracy = .reduced
    stream.accuracyAfterRequest = .reduced
    let prepared = await session.prepareStart()
    XCTAssertFalse(prepared)
    XCTAssertEqual(session.lastStartFailure, .reducedAccuracy)
    XCTAssertEqual(session.state, .idle)
}
```

- [x] **Step 2: 테스트 실행 — 실패 확인** (`prepareStart` 미정의 컴파일 에러)

- [x] **Step 3: 구현** — `RunSession.swift`. `start(goal:)` 본문을 분해:

```swift
/// 예열 단계 여부 — prepareStart~beginTracking 사이(카운트다운 중)에만 true
private var isPreparing = false

/// 카운트다운 전 단계(스펙 §1.1): 정확도 게이트(시스템 프롬프트 포함)와 GPS 예열만 수행한다.
/// 상태는 idle 유지·startedAt 미설정 — 스트림 태스크의 startedAt 가드가 예열 샘플을 버린다.
func prepareStart(goal: RunGoal = .open) async -> Bool {
    guard state == .idle, isPreparing == false else { return false }
    lastStartFailure = nil

    var accuracy = locationStream.currentAccuracy()
    if accuracy == .reduced {
        accuracy = await locationStream.requestSessionFullAccuracy()
    }
    guard accuracy == .full else {
        lastStartFailure = .reducedAccuracy
        return false
    }

    track = RunTrack()
    startedAt = nil
    #if DEBUG
    dumpEntries = []
    #endif
    self.goal = goal
    goalHalfReached = false
    goalAchieved = false
    isPreparing = true

    let stream = locationStream.startUpdates()
    streamTask = Task { [weak self] in
        for await sample in stream {
            guard let self, let sessionStart = self.startedAt else { continue } // 예열 샘플 폐기
            self.ingest(sample, sessionStart: sessionStart)
        }
        guard Task.isCancelled == false else { return }
        self?.streamEnded()
    }
    return true
}

/// 카운트다운 종료 시점 — 여기부터가 세션 시작(활동 시간·거리 적산 기준, 스펙 §1.1)
func beginTracking(now: Date = Date()) {
    guard isPreparing, state == .idle else { return }
    isPreparing = false
    guard lastStartFailure == nil else { stopStream(); return } // 예열 중 스트림 사망(권한 회수)
    startedAt = now
    state = .acquiring
}

/// 카운트다운 취소 — 예열 스트림을 내리고 대기 상태로 되돌린다
func cancelPreparation() {
    guard isPreparing else { return }
    isPreparing = false
    stopStream()
    startedAt = nil
    goal = .open
    goalHalfReached = false
    goalAchieved = false
}

func start(goal: RunGoal = .open) async {
    guard await prepareStart(goal: goal) else { return }
    beginTracking()
}
```

`streamEnded()` 맨 앞에 예열 중 종료 처리 추가:

```swift
private func streamEnded() {
    if isPreparing { // 예열 중 스트림 사망(권한 회수 등) — beginTracking이 시작을 거부하게 표시
        isPreparing = false
        locationStream.stopUpdates()
        lastStartFailure = .permissionDenied
        return
    }
    guard isActive else { return }
    // … 기존 본문 유지
}
```

주의: 기존 `start()`의 `let sessionStart = Date()` 캡처 방식이 `self.startedAt` 참조로 바뀌므로, 기존 테스트가 전부 그린인지 확인한다(동작 동일: start()는 prepare 직후 begin이라 차이 없음).

- [x] **Step 4: 테스트 실행 — 통과 확인** (신규 + 기존 RunSessionTests·RunSessionGoalTests 전부)

- [x] **Step 5: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: RunSession 시작을 예열/개시 2단계로 분해

- prepareStart: 정확도 게이트+GPS 예열, 상태 idle 유지(예열 샘플 폐기)
- beginTracking: 카운트다운 종료 시점을 세션 시작 기준으로 설정
- cancelPreparation·예열 중 스트림 사망 가드 추가, start()는 합성으로 호환 유지" -- Trace/Application/RunTracking/RunSession.swift TraceTests/RunSessionTests.swift
```

---

### Task 4: 시작 카운트다운 — ViewModel 오케스트레이션 + UI + DI 배선

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift`
- Modify: `Trace/App/DependencyContainer.swift` (voiceAnnouncer 공유 프로퍼티)
- Modify: `Trace/App/TraceApp.swift:35` (RunPage init 인자 추가)
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `RunAnnouncementBuilder.countdown`, Task 2 `holdAudioSession()/releaseAudioSession()/stopSpeaking()`, Task 3 `prepareStart/beginTracking/cancelPreparation`
- Produces:
  - `RunPageViewModel.init(session:announcer:defaults:sleeper:)` — `announcer: VoiceAnnouncerProtocol`, `sleeper: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }` (테스트는 즉시 리턴 주입)
  - `RunPageViewModel.countdown: Int?` — 3→2→1, nil이면 카운트다운 아님 (View가 표시)
  - `RunPageViewModel.cancelCountdown()`
  - `DependencyContainer.voiceAnnouncer: VoiceAnnouncerProtocol` — coach와 RunPage가 같은 인스턴스 공유

- [x] **Step 1: 실패하는 테스트 작성** — `RunPageViewModelTests.swift` (기존 파일의 세션 구성 헬퍼 재사용, 페이크 announcer 신설):

```swift
@MainActor
final class RecordingVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    var holds = 0, releases = 0, stops = 0
    func announce(_ text: String) { announced.append(text) }
    func holdAudioSession() { holds += 1 }
    func releaseAudioSession() { releases += 1 }
    func stopSpeaking() { stops += 1 }
}

// 기존 필드 `private lazy var viewModel = RunPageViewModel(session: session)` 는
// announcer·sleeper 주입 형태로 교체한다 (파일의 기존 session/stream 픽스처는 유지):
private let announcer = RecordingVoiceAnnouncer()
private lazy var viewModel = RunPageViewModel(
    session: session,
    announcer: announcer,
    sleeper: { _ in } // 즉시 리턴 — 카운트다운을 동기적으로 소진
)

func test_시작탭_카운트다운_삼이일_발화후_세션시작() async {
    await viewModel.startTapped()
    XCTAssertEqual(announcer.announced, ["삼", "이", "일"])
    XCTAssertEqual(announcer.holds, 1)
    XCTAssertEqual(announcer.releases, 1)
    XCTAssertNil(viewModel.countdown)
    XCTAssertEqual(viewModel.session.state, .acquiring)
}

func test_카운트다운_취소시_발화중단_세션정리() async {
    // 첫 sleep에서 무기한 대기하는 sleeper — cancelCountdown이 개입할 틈을 만든다
    let (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
    let vm = RunPageViewModel(
        session: session,
        announcer: announcer,
        sleeper: { _ in for await _ in gate {} }
    )
    let startTask = Task { await vm.startTapped() }
    while vm.countdown == nil { await Task.yield() } // 카운트다운 진입 대기
    vm.cancelCountdown()
    XCTAssertEqual(announcer.stops, 1)
    XCTAssertNil(vm.countdown)
    XCTAssertEqual(session.state, .idle)
    gateContinuation.finish() // sleeper 해제 — 깨어난 루프는 countdownActive 가드로 종료
    await startTask.value
    XCTAssertEqual(session.state, .idle) // beginTracking 미호출 확인
}

func test_정확도부족이면_카운트다운_시작안함() async {
    stream.accuracy = .reduced
    stream.accuracyAfterRequest = .reduced
    await viewModel.startTapped()
    XCTAssertTrue(announcer.announced.isEmpty)
    XCTAssertNil(viewModel.countdown)
    XCTAssertTrue(viewModel.showsAccuracyAlert)
}
```

기존 테스트 메서드들은 새 `viewModel` 픽스처를 그대로 쓰므로 개별 수정이 없어야 정상이다 —
컴파일이 깨지는 테스트가 있으면 생성부만 고치고 검증 로직은 유지한다.

- [x] **Step 2: 테스트 실행 — 실패 확인**

- [x] **Step 3: ViewModel 구현** — `RunPageViewModel.swift`:

```swift
private let announcer: VoiceAnnouncerProtocol
private let sleeper: (Duration) async throws -> Void
/// 카운트다운 표시값(3→2→1). nil = 카운트다운 아님. 스펙 §1.1
private(set) var countdown: Int?
/// 취소 감지 플래그 — cancelCountdown()이 내리면 진행 중인 startTapped 루프가 중단된다
private var countdownActive = false

init(
    session: RunSession,
    announcer: VoiceAnnouncerProtocol,
    defaults: UserDefaults = .standard,
    sleeper: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) {
    self.session = session
    self.announcer = announcer
    self.defaults = defaults   // Task 6에서 사용(목표 프리필). Task 4 시점에는 저장만 미사용
    self.sleeper = sleeper
}

func startTapped() async {
    guard countdown == nil else { return }
    guard await session.prepareStart(goal: composedGoal) else {
        presentStartFailure()
        return
    }
    announcer.holdAudioSession() // 덕킹 1회: 카운트다운~시작 발화까지 유지(스펙 §1.1)
    countdownActive = true
    for (index, word) in RunAnnouncementBuilder.countdown.enumerated() {
        guard countdownActive else { return } // 취소됨 — cancelCountdown()이 정리 완료
        countdown = RunAnnouncementBuilder.countdown.count - index
        announcer.announce(word)
        do { try await sleeper(.seconds(1)) } catch { return }
    }
    guard countdownActive else { return }
    countdownActive = false
    countdown = nil
    session.beginTracking()
    // 시작 발화(RunAudioCoach, idle→acquiring)가 큐에 남아 있는 동안 release —
    // 어댑터는 큐 소진 시점에 비활성화하므로 덕킹 플랩이 없다(스펙 §1.1)
    announcer.releaseAudioSession()
    guard session.lastStartFailure == nil else {
        presentStartFailure()
        return
    }
    displayedCoordinates = []
    polylineThrottle = PolylineThrottle()
    summaryElapsedSeconds = nil
    recenter()
}

/// 카운트다운 중 화면 탭 → 취소(스펙 §1.1). 백그라운드 진입은 취소가 아니다 — 계속 진행.
func cancelCountdown() {
    guard countdownActive else { return }
    countdownActive = false
    countdown = nil
    announcer.stopSpeaking()
    announcer.releaseAudioSession()
    session.cancelPreparation()
}

private func presentStartFailure() {
    switch session.lastStartFailure {
    case .reducedAccuracy: showsAccuracyAlert = true
    case .permissionDenied: showsPermissionAlert = true
    case nil: break
    }
}
```

기존 `startTapped()`의 switch 분기는 `presentStartFailure()` + 성공 경로로 대체된다. `defaults` 저장 프로퍼티는 이번 태스크에서 추가만 해 둔다(`private let defaults: UserDefaults`).

- [x] **Step 4: UI + DI 배선** — `RunPage.swift`:

```swift
// init에 announcer 전달
init(session: RunSession, recordRepository: RunRecordRepositoryProtocol, announcer: VoiceAnnouncerProtocol) {
    _viewModel = State(initialValue: RunPageViewModel(session: session, announcer: announcer))
    _historyViewModel = State(initialValue: RunHistoryViewModel(repository: recordRepository))
}

// body의 ZStack에 오버레이 + 햅틱 추가
.overlay {
    if let count = viewModel.countdown {
        countdownOverlay(count: count)
    }
}
.onChange(of: viewModel.countdown) { _, newValue in
    guard newValue != nil else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 숫자마다 햅틱(스펙 §1.1)
}

private func countdownOverlay(count: Int) -> some View {
    ZStack {
        Color.black.opacity(0.55).ignoresSafeArea()
        Text("\(count)")
            .font(.system(size: 160, weight: .heavy, design: .rounded))
            .foregroundStyle(DesignToken.Color.accent)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: count)
    }
    .contentShape(Rectangle())
    .onTapGesture { viewModel.cancelCountdown() } // 취소 = 화면 탭(스펙 §1.1)
    .accessibilityIdentifier("run.countdownOverlay")
}
```

`DependencyContainer.swift`: `let voiceAnnouncer: VoiceAnnouncerProtocol` 프로퍼티 추가, `live()`는 `SpeechVoiceAnnouncer()` 하나를 만들어 coach와 컨테이너에 공유, `uiTesting()`은 `NoopVoiceAnnouncer()` 공유. `TraceApp.swift:35`는 `announcer: container.voiceAnnouncer` 인자 추가.

- [x] **Step 5: 테스트 실행 — 통과 확인** (신규 + 기존 RunPageViewModelTests — 기존 테스트의 VM 생성부에 `announcer: RecordingVoiceAnnouncer()` 주입 필요)

- [x] **Step 6: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 시작 3-2-1 카운트다운 추가

- 시작 탭 → 권한/정확도 게이트 → 삼/이/일 발화+햅틱 → 세션 시작
- GPS 예열이 카운트다운 3초에 흡수, 화면 탭으로 취소, 백그라운드에도 계속
- 덕킹 1회 유지(hold/release), DependencyContainer에 announcer 공유 배선" -- Trace/Pages/RunPage/RunPageViewModel.swift Trace/Pages/RunPage/RunPage.swift Trace/App/DependencyContainer.swift Trace/App/TraceApp.swift TraceTests/RunPageViewModelTests.swift
```

---

### Task 5: 종료 홀드 진행 링

**Files:**
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (`endButton`, 현재 `onLongPressGesture(minimumDuration: 1.0)` 부근)

**Interfaces:**
- Consumes: 기존 `isPressingEnd: Bool` @State, `viewModel.endRun()`
- Produces: UI 전용 — 다른 태스크가 의존하지 않음

- [x] **Step 1: 구현** — 기존 `endButton`을 진행 링 포함으로 교체 (동작 시간 1.0초 유지 — 스펙 §1.2):

```swift
private var endButton: some View {
    Text("길게 눌러 종료")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(DesignToken.Color.danger, in: Capsule())
        .overlay {
            // 누르는 동안 1초에 걸쳐 테두리를 따라 차오르는 진행 링(스펙 §1.2)
            Capsule()
                .trim(from: 0, to: isPressingEnd ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .animation(
                    isPressingEnd ? .linear(duration: 1.0) : .easeOut(duration: 0.2),
                    value: isPressingEnd
                )
        }
        .scaleEffect(isPressingEnd ? 0.95 : 1)
        .onLongPressGesture(minimumDuration: 1.0) {
            UINotificationFeedbackGenerator().notificationOccurred(.success) // 완료 햅틱
            viewModel.endRun()
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) { isPressingEnd = pressing }
        }
}
```

- [x] **Step 2: 시뮬레이터 확인** — XcodeBuildMCP로 빌드·실행 후 트래킹 화면에서: 누르는 동안 링이 차오르고, 1초 유지 시 종료, 중간에 떼면 링이 되감기는지 확인 (UI 전용이라 단위 테스트 없음 — 스크린샷으로 확인)

- [x] **Step 3: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: 종료 버튼 홀드 진행 링 추가

- 길게 누르는 1초 동안 캡슐 테두리를 따라 차오르는 진행 링 표시
- 중간에 떼면 되감기, 완료 시 성공 햅틱 — 홀드 시간 1초는 유지
- 눌림 피드백 부재로 종료 여부를 알 수 없던 실사용 불편 해소" -- Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift
```

---

### Task 6: 목표 거리·시간 직접 입력

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` (피커 Int 상태 → 텍스트 입력 상태)
- Modify: `Trace/Pages/RunPage/RunPage.swift` (`goalPicker`의 wheel 피커 2개 → 입력 필드)
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: Task 4의 `defaults: UserDefaults` (init 주입 완료 상태)
- Produces:
  - `goalDistanceInput: String`, `goalTimeInput: String` (View 바인딩)
  - `parsedGoalDistanceKm: Double?`, `parsedGoalTimeMinutes: Int?`
  - `isGoalInputValid: Bool` (시작 버튼 활성 조건), `goalInputErrorText: String?` (인라인 안내)
  - UserDefaults 키: `"run.goal.lastDistanceKm"`(Double), `"run.goal.lastTimeMinutes"`(Int)

- [x] **Step 1: 실패하는 테스트 작성** — `RunPageViewModelTests.swift` (defaults는 `UserDefaults(suiteName: #function)` 주입 + `removePersistentDomain`으로 격리):

```swift
func test_거리입력_파싱과_검증() {
    // "5.5" → parsedGoalDistanceKm == 5.5, isGoalInputValid(distance 모드) == true
    // "0" / "-1" / "abc" / "" → parsed nil, invalid, 에러 텍스트는 빈 입력일 때만 nil
}

func test_시간입력_정수만_허용() {
    // "30" → 30, "30.5" → nil, "0" → nil
}

func test_composedGoal_입력값_반영() {
    // distance 모드 + "5.5" → .distance(meters: 5500)
    // time 모드 + "45" → .time(seconds: 2700)
}

func test_직전목표_프리필() {
    // defaults에 lastDistanceKm=7.5 저장 후 VM 생성 → goalDistanceInput == "7.5"
    // 저장값 없으면 "" (플레이스홀더 노출 상태)
}

func test_시작성공시_목표값_저장() async {
    // distance 모드 + "3.0" → startTapped(즉시 sleeper) → defaults에 3.0 기록
}
```

- [x] **Step 2: 테스트 실행 — 실패 확인**

- [x] **Step 3: ViewModel 구현** — `goalDistanceKm`/`goalTimeMinutes`(Int 피커 상태) 제거 후:

```swift
static let lastDistanceKey = "run.goal.lastDistanceKm"
static let lastTimeKey = "run.goal.lastTimeMinutes"

var goalDistanceInput: String
var goalTimeInput: String

// init에서 프리필(스펙 §1.4: 직전값, 최초 사용 시에만 플레이스홀더)
// (init 본문에 추가)
goalDistanceInput = (defaults.object(forKey: Self.lastDistanceKey) as? Double)
    .map(Self.formatKm) ?? ""
goalTimeInput = (defaults.object(forKey: Self.lastTimeKey) as? Int)
    .map(String.init) ?? ""

var parsedGoalDistanceKm: Double? {
    let normalized = goalDistanceInput.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
    return value
}

var parsedGoalTimeMinutes: Int? {
    guard let value = Int(goalTimeInput), value > 0 else { return nil }
    return value
}

var isGoalInputValid: Bool {
    switch goalMode {
    case .open: true
    case .distance: parsedGoalDistanceKm != nil
    case .time: parsedGoalTimeMinutes != nil
    }
}

/// 비정상 입력 인라인 안내(스펙 §1.4) — 빈 입력은 플레이스홀더가 안내하므로 에러 아님
var goalInputErrorText: String? {
    switch goalMode {
    case .open: nil
    case .distance:
        goalDistanceInput.isEmpty || parsedGoalDistanceKm != nil ? nil : "0보다 큰 숫자를 입력하세요"
    case .time:
        goalTimeInput.isEmpty || parsedGoalTimeMinutes != nil ? nil : "0보다 큰 정수(분)를 입력하세요"
    }
}

var composedGoal: RunGoal {
    switch goalMode {
    case .open: .open
    case .distance: parsedGoalDistanceKm.map { .distance(meters: $0 * 1000) } ?? .open
    case .time: parsedGoalTimeMinutes.map { .time(seconds: TimeInterval($0 * 60)) } ?? .open
    }
}

private func persistGoalInputs() {
    if let km = parsedGoalDistanceKm { defaults.set(km, forKey: Self.lastDistanceKey) }
    if let minutes = parsedGoalTimeMinutes { defaults.set(minutes, forKey: Self.lastTimeKey) }
}

/// 7.0 → "7", 7.5 → "7.5" — 입력 필드 프리필 표기
private static func formatKm(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
}
```

`startTapped()`의 prepareStart 성공 직후에 `persistGoalInputs()` 호출 추가. 시작 가드에 `guard isGoalInputValid else { return }`도 추가.

- [x] **Step 4: UI 구현** — `RunPage.swift`의 `goalPicker`에서 wheel `Picker` 2개를 교체:

```swift
@FocusState private var goalFieldFocused: Bool

// goalPicker의 switch 분기 교체
case .distance:
    goalInputField(text: $viewModel.goalDistanceInput, unit: "km",
                   placeholder: "5.0", keyboard: .decimalPad)
case .time:
    goalInputField(text: $viewModel.goalTimeInput, unit: "분",
                   placeholder: "30", keyboard: .numberPad)

// switch 아래(공통)에 인라인 에러
if let error = viewModel.goalInputErrorText {
    Text(error)
        .font(DesignToken.Typography.chipError)
        .foregroundStyle(DesignToken.Color.danger)
}

private func goalInputField(
    text: Binding<String>, unit: String, placeholder: String, keyboard: UIKeyboardType
) -> some View {
    HStack(spacing: 8) {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused($goalFieldFocused)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .frame(maxWidth: 140)
        Text(unit) // 단위 상시 표시(스펙 §1.4, 사용자 요구)
            .font(DesignToken.Typography.subtitle)
            .foregroundStyle(DesignToken.Color.ink2)
    }
    .frame(maxWidth: .infinity)
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("완료") { goalFieldFocused = false } // 명시적 dismiss(스펙 §1.4)
        }
    }
}
```

`startButton`에 `.disabled(viewModel.isGoalInputValid == false)`와 비활성 시 `.opacity(0.5)` 추가. 시작 직전 `goalFieldFocused = false`로 키보드를 내린다.

- [x] **Step 5: 시뮬레이터 확인** — 키보드가 떠 있는 동안 시작 버튼이 가려지지 않는지 확인 (SwiftUI 기본 keyboard avoidance가 하단 VStack을 밀어올림). 만약 지도(Map)가 키보드에 눌려 점프하면 `runMap`에만 `.ignoresSafeArea(.keyboard)` 적용 — 근거: `docs/solutions/design-patterns/swiftui-keyboard-avoidance-shrinks-representable.md`

- [x] **Step 6: 테스트 실행 — 통과 확인** (기존 RunPageViewModelTests의 `goalDistanceKm` 참조 테스트는 새 입력 API로 갱신)

- [x] **Step 7: 검증 & 커밋** — 공통 절차 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 목표 거리·시간 직접 입력으로 교체

- 휠 피커 → 텍스트 입력(km 소수/분 정수), 단위 라벨 상시 표시
- 검증 실패 시 인라인 안내+시작 버튼 비활성, 키보드 완료 툴바
- 직전 사용 목표값 프리필(UserDefaults, 모드별 기억)" -- Trace/Pages/RunPage/RunPageViewModel.swift Trace/Pages/RunPage/RunPage.swift TraceTests/RunPageViewModelTests.swift
```

---

## 사이클 마무리 체크 (마지막 태스크 후)

- [x] 전체 테스트 스위트 그린 확인(294/294, Task 6 커밋 기준) + 스펙 §1 대비 커버리지 확인 — §1.1 카운트다운(Task 4)·§1.2 홀드 링(Task 5)·§1.3 문안/rate(Task 1·2)·§1.4 목표 입력(Task 6) 전부 매핑 확인
- [x] 실기기 QA 체크리스트 작성: `docs/qa/2026-07-18-run-detail-polish-device-checklist.md` (시나리오 10개 — 카운트다운 발화/잠금 지속/취소 탭/콜드 스타트, 홀드 링, rate 체감, 목표 입력 프리필·에러·키보드, 기존 플로우 회귀, 이월 2건)
- [x] rate 튜닝 결과를 스펙 §1.3에 기록 — 2026-07-18 실기기 QA 완료: 카운트다운 예열 문제(hold를 prepareStart 이전으로 이동) + 정보성 문구 속도 분리(brisk 0.45 / measured 0.40) 반영, 커밋 50c5fd9
