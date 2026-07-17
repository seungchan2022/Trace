# run-pause-resume (MVP14 사이클 1) Implementation Plan

> **완료(소급 확인):** Task 1~7 전부 구현·리뷰·검증 완료(커밋 `6c8ad94`..`2e418e5`, 최종 브랜치
> 리뷰(opus) Ready to merge: Yes), 실기기 QA 통과(2026-07-16, 시나리오 1~6 전부 통과, 커밋
> `8c12c6d`). 아래 체크박스는 실행 당시 갱신되지 않았으나 `docs/roadmap.md`의 완료 기록과
> git 히스토리로 완료가 확인되어 소급 복원하지 않는다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러닝 수동 일시정지/재개 — 멈춘 시간을 시간·페이스·기록에서 제외하고, 일시정지 구간을 저장하며, 트래킹 UI와 잠금화면(Live Activity)에 일시정지 상태를 표시한다.

**Architecture:** `RunSession` 상태기계에 `paused`를 추가한다(스트림은 유지, 샘플만 무시). 시간의 정의를 "벽시계 경과"에서 "활동 시간(벽시계 − 일시정지 합)"으로 바꾸고, 일시정지 구간(`RunPauseInterval`)을 세션이 기록해 저장 payload(DTO v2, additive)에 포함한다. UI 타이머와 Live Activity는 "보정된 시작 시각(timerStart)" 기법으로 정지·재개를 표현한다.

**Tech Stack:** Swift 6(기본 nonisolated + UI/상태 타입 명시 `@MainActor`), SwiftUI, Observation, ActivityKit, SwiftData(payload blob만 변경 — 모델 컬럼 변경 없음), XCTest.

**스펙:** `docs/superpowers/specs/2026-07-15-run-experience-design.md` §3.1, §4 — 결정 2(수동만)·결정 8(진입점은 앱 내 버튼만)·장시간 일시정지 무대응.

## Global Constraints

- 브랜치: `feature/run-pause-resume` (main에서 분기). 커밋은 `scripts/trace-commit.sh`로 경로 명시 스테이징. `git add -A`/`git push` 금지.
- 커밋 전 3종 통과 + 스탬프 갱신 필수(`docs/agent-rules/testing.md`): build/test/lint 각각 성공 후 `.git/trace-verify-{build,test,lint}.ok` touch. 테스트는 반드시 `-parallel-testing-enabled NO`, iOS 26.5 시뮬레이터 하나만 사용(세션 중 교체 금지), XcodeBuildMCP `test_sim` 금지.
- 검증 명령 (아래 각 Task의 "Run"은 이 형식을 따른다. `$SIM_UDID`는 세션 시작 시 한 번 결정):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:TraceTests/<TestClass> test
swiftlint
```

- force unwrap/cast/try 금지(린트 에러), IUO(`var x: T!`) 금지 — 테스트 픽스처는 `private let` + `lazy var` 필드 초기화 패턴(RunSessionTests 참고).
- 값 타입은 `Equatable, Sendable`. 도메인/DTO에 SwiftData·UIKit import 금지. 필요 없는 곳에 어노테이션을 남기지 않는다.
- 커밋 메시지: `tag: 한국어 제목` + 본문 3~4줄(한국어), Co-Authored-By 금지.
- **이 사이클 범위 밖(구현 금지):** 자동 일시정지, 잠금화면 인터랙티브 버튼(결정 8), 오디오 발화(사이클 2), km 스플릿(사이클 2), 장시간 일시정지 리마인더/자동 종료(무대응이 스펙).

---

### Task 1: Domain — `RunPauseInterval` + `RunTrack.markGap()`

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunPauseInterval.swift`
- Modify: `Trace/Domain/RunTracking/Entity/RunTrack.swift` (append에 gap 억제 추가)
- Test: `TraceTests/RunTrackTests.swift` (추가), `TraceTests/RunPauseIntervalTests.swift` (신규)

**Interfaces:**
- Consumes: 기존 `RunTrack.append(_:)`, `RunSample`
- Produces:
  - `struct RunPauseInterval: Equatable, Sendable { let start: Date; let end: Date; var duration: TimeInterval }`
  - `RunTrack.markGap()` — 다음 `append` 1회에 한해 직전 샘플과의 거리 가산을 건너뜀 (Task 2·3·4가 사용)

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunPauseIntervalTests.swift` 신규:

```swift
import XCTest
@testable import Trace

final class RunPauseIntervalTests: XCTestCase {
    func test_duration은_끝에서_시작을_뺀_초다() {
        let start = Date(timeIntervalSince1970: 1_000)
        let interval = RunPauseInterval(start: start, end: start.addingTimeInterval(90))
        XCTAssertEqual(interval.duration, 90, accuracy: 0.001)
    }
}
```

`TraceTests/RunTrackTests.swift`에 추가 (기존 헬퍼 `sample(...)` 관례를 따르되, 이 파일의 기존 샘플 생성 방식을 그대로 재사용):

```swift
    func test_markGap_후_첫_샘플은_거리를_가산하지_않는다() {
        var track = RunTrack()
        let base = Date()
        track.append(sampleAt(latOffsetMeters: 0, at: base))
        track.append(sampleAt(latOffsetMeters: 100, at: base.addingTimeInterval(30)))
        let beforeGap = track.totalDistanceMeters
        track.markGap()
        // 일시정지 중 500m 이동했다고 가정 — 이 구간은 거리에 안 들어가야 한다
        track.append(sampleAt(latOffsetMeters: 600, at: base.addingTimeInterval(300)))
        XCTAssertEqual(track.totalDistanceMeters, beforeGap, accuracy: 1.0)
        // gap 다음 샘플부터는 다시 정상 가산
        track.append(sampleAt(latOffsetMeters: 700, at: base.addingTimeInterval(330)))
        XCTAssertEqual(track.totalDistanceMeters, beforeGap + 100, accuracy: 2.0)
    }

    private func sampleAt(latOffsetMeters: Double, at date: Date) -> RunSample {
        RunSample(
            timestamp: date,
            latitude: 37.5666 + latOffsetMeters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 5
        )
    }
```

(주의: `RunTrackTests.swift`에 이미 같은 이름의 샘플 헬퍼가 있으면 그것을 쓰고 위 `sampleAt`은 추가하지 않는다.)

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunTrackTests -only-testing:TraceTests/RunPauseIntervalTests test`
Expected: FAIL — `RunPauseInterval` 타입 없음 / `markGap` 없음 (컴파일 에러)

- [ ] **Step 3: 최소 구현**

`Trace/Domain/RunTracking/Entity/RunPauseInterval.swift` 신규:

```swift
import Foundation

/// 일시정지 구간 — 시각 쌍. GPS 공백과 구분 불가하므로 파생하지 않고 명시 기록한다(스펙 §4).
struct RunPauseInterval: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
```

`Trace/Domain/RunTracking/Entity/RunTrack.swift` 수정 — 프로퍼티 추가 + `append` 교체:

```swift
    // 재개 직후 첫 샘플의 거리 가산 억제 플래그(일시정지 경계 순간이동 방지 — 스펙 §3.1)
    private var pendingGap = false

    /// 다음 append 1회에 한해 직전 샘플과의 거리를 가산하지 않는다 — 일시정지 재개 시 호출.
    mutating func markGap() {
        pendingGap = true
    }

    mutating func append(_ sample: RunSample) {
        if let previous = samples.last, pendingGap == false {
            totalDistanceMeters += previous.coordinate.distanceMeters(to: sample.coordinate)
        }
        pendingGap = false
        accumulateElevation(from: sample)
        samples.append(sample)
    }
```

- [ ] **Step 4: 통과 확인**

Run: Step 2와 동일 명령. Expected: PASS (RunTrackTests 기존 테스트 포함 전부)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 일시정지 구간 타입과 RunTrack 거리 gap 억제 추가

- RunPauseInterval(시작·끝 시각 쌍) 도메인 타입 신설
- RunTrack.markGap(): 재개 직후 첫 샘플의 거리 가산 1회 억제
- 일시정지 중 이동 거리가 기록에 들어가지 않게 하는 기반(스펙 §3.1)" \
  -- Trace/Domain/RunTracking/Entity/RunPauseInterval.swift Trace/Domain/RunTracking/Entity/RunTrack.swift TraceTests/RunPauseIntervalTests.swift TraceTests/RunTrackTests.swift
```

---

### Task 2: `RunSession` 일시정지 상태기계

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift`
- Test: `TraceTests/RunSessionTests.swift` (추가)

**Interfaces:**
- Consumes: Task 1의 `RunPauseInterval`, `RunTrack.markGap()`
- Produces (Task 4·5·6이 사용):
  - `RunSession.State`에 `case paused` 추가
  - `func pause(now: Date = Date())` — `tracking`에서만 동작
  - `func resume(now: Date = Date())` — `paused`에서만 동작, 닫힌 구간을 `completedPauses`에 적재 + `track.markGap()`
  - `private(set) var completedPauses: [RunPauseInterval]`
  - `var isPaused: Bool`
  - `func totalPausedSeconds(now: Date = Date()) -> TimeInterval` — 닫힌 구간 합 + 열린 구간(진행 중이면)
  - `func activeElapsedSeconds(now: Date = Date()) -> TimeInterval?` — 벽시계 경과 − 일시정지 합
  - `var displayTimerStart: Date?` — `startedAt + totalPausedSeconds()` (타이머 표시용 보정 시작 시각)
  - `isActive`가 `paused`를 포함 (일시정지 = 세션 진행 중)

**상태 전이표 (스펙 리뷰 이연 질문의 확정):**

| 현재 | 이벤트 | 다음 | 부수효과 |
|---|---|---|---|
| tracking | `pause()` | paused | 열린 구간 시작(`pausedAt`) |
| paused | `resume()` | tracking | 구간 닫아 적재, `track.markGap()` |
| paused | `finish()` | summary | 열린 구간을 종료 시각으로 닫고 저장 |
| paused | 스트림 외부 종료(권한 회수) | summary | 위와 동일 (`streamEnded()` 경로) |
| paused | 샘플 도착 | paused | **통째로 무시** — 적산·덤프·약신호 갱신 없음 |
| acquiring | `pause()` | acquiring | 무시 (유효 샘플 전이라 일시정지 개념 없음) |

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunSessionTests.swift`에 추가 (기존 `sample(at:latOffsetMeters:hAcc:)`·`waitUntil`·`drainNoOp` 헬퍼 재사용):

```swift
    func test_트래킹중_일시정지하면_paused_상태가_되고_세션은_계속_활성이다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        session.pause()
        XCTAssertEqual(session.state, .paused)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isPaused)
    }

    func test_신호확보중에는_일시정지가_무시된다() async {
        await session.start()
        session.pause()
        XCTAssertEqual(session.state, .acquiring)
    }

    func test_일시정지중_샘플은_통째로_무시된다() async {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.track.samples.count == 1 }
        session.pause()
        stream.yield(sample(at: base.addingTimeInterval(5), latOffsetMeters: 50))
        await drainNoOp()
        XCTAssertEqual(session.track.samples.count, 1)
        #if DEBUG
        XCTAssertEqual(session.dumpEntries.count, 1)
        #endif
        XCTAssertFalse(session.isSignalWeak)
    }

    func test_재개하면_닫힌_일시정지구간이_기록되고_경계_거리는_가산되지_않는다() async {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 30))
        await waitUntil { session.track.samples.count == 2 }
        let distanceBeforePause = session.track.totalDistanceMeters

        let pauseStart = base.addingTimeInterval(20)
        session.pause(now: pauseStart)
        session.resume(now: pauseStart.addingTimeInterval(60))

        XCTAssertEqual(session.state, .tracking)
        XCTAssertEqual(session.completedPauses.count, 1)
        XCTAssertEqual(session.completedPauses[0].duration, 60, accuracy: 0.001)

        // 일시정지 동안 200m 떨어진 곳에서 재개 — 그 구간 거리는 미가산
        stream.yield(sample(at: pauseStart.addingTimeInterval(61), latOffsetMeters: 230))
        await waitUntil { session.track.samples.count == 3 }
        XCTAssertEqual(session.track.totalDistanceMeters, distanceBeforePause, accuracy: 1.0)
    }

    func test_활동시간은_일시정지_시간을_제외한다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        guard let startedAt = session.startedAt else { return XCTFail("startedAt 없음") }

        let pauseStart = startedAt.addingTimeInterval(100)
        session.pause(now: pauseStart)
        session.resume(now: pauseStart.addingTimeInterval(40))

        let now = startedAt.addingTimeInterval(200)
        XCTAssertEqual(session.totalPausedSeconds(now: now), 40, accuracy: 0.001)
        XCTAssertEqual(session.activeElapsedSeconds(now: now) ?? -1, 160, accuracy: 0.001)
        XCTAssertEqual(
            session.displayTimerStart?.timeIntervalSince(startedAt) ?? -1, 40, accuracy: 0.001
        )
    }

    func test_일시정지중_활동시간은_고정된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        guard let startedAt = session.startedAt else { return XCTFail("startedAt 없음") }

        session.pause(now: startedAt.addingTimeInterval(100))
        let atT150 = session.activeElapsedSeconds(now: startedAt.addingTimeInterval(150))
        let atT300 = session.activeElapsedSeconds(now: startedAt.addingTimeInterval(300))
        XCTAssertEqual(atT150 ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(atT300 ?? -1, 100, accuracy: 0.001)
    }

    func test_일시정지중_종료하면_열린_구간이_닫히고_요약으로_간다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        session.pause()
        session.finish()
        XCTAssertEqual(session.state, .summary)
        XCTAssertEqual(session.completedPauses.count, 1)
        XCTAssertTrue(stream.stopped)
    }

    func test_요약을_닫으면_일시정지_기록도_초기화된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        session.pause()
        session.finish()
        session.dismissSummary()
        XCTAssertTrue(session.completedPauses.isEmpty)
        XCTAssertEqual(session.totalPausedSeconds(), 0, accuracy: 0.001)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunSessionTests test`
Expected: FAIL — `paused`/`pause()`/`completedPauses` 미정의 (컴파일 에러)

- [ ] **Step 3: 최소 구현**

`Trace/Application/RunTracking/RunSession.swift` 수정:

`State`에 케이스 추가:

```swift
    enum State: Equatable {
        case idle
        case acquiring
        case tracking
        case paused
        case summary
    }
```

프로퍼티·계산값 추가/교체 (`isActive` 교체, 나머지는 추가):

```swift
    /// 닫힌 일시정지 구간들 — 저장 payload에 그대로 들어간다(스펙 §4)
    private(set) var completedPauses: [RunPauseInterval] = []
    /// 열린 일시정지의 시작 시각 — paused 상태에서만 non-nil
    private var pausedAt: Date?

    var isActive: Bool { state == .acquiring || state == .tracking || state == .paused }
    var isPaused: Bool { state == .paused }

    /// 닫힌 구간 합 + (일시정지 중이면) 열린 구간까지 — "지금까지 멈춘 총 시간"
    func totalPausedSeconds(now: Date = Date()) -> TimeInterval {
        let completed = completedPauses.reduce(0) { $0 + $1.duration }
        let open = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return completed + open
    }

    /// 활동 시간 = 벽시계 경과 − 일시정지 합. 시간·페이스·기록의 새 기준(스펙 §3.1).
    func activeElapsedSeconds(now: Date = Date()) -> TimeInterval? {
        guard let startedAt else { return nil }
        return now.timeIntervalSince(startedAt) - totalPausedSeconds(now: now)
    }

    /// 타이머 UI용 보정 시작 시각 — 여기서부터 지금까지가 곧 활동 시간이 되도록 민 값.
    /// 트래킹 중에는 열린 구간이 없어 고정값이다(Text(timerInterval:)의 기준으로 안전).
    var displayTimerStart: Date? {
        guard let startedAt else { return nil }
        return startedAt.addingTimeInterval(totalPausedSeconds())
    }
```

전이 메서드 추가:

```swift
    func pause(now: Date = Date()) {
        guard state == .tracking else { return }
        pausedAt = now
        state = .paused
    }

    func resume(now: Date = Date()) {
        guard state == .paused, let pausedAt else { return }
        completedPauses.append(RunPauseInterval(start: pausedAt, end: now))
        self.pausedAt = nil
        track.markGap()
        state = .tracking
    }

    private func closeOpenPause(at date: Date) {
        guard let pausedAt else { return }
        completedPauses.append(RunPauseInterval(start: pausedAt, end: date))
        self.pausedAt = nil
    }
```

`finish()` 교체 (열린 구간 닫기):

```swift
    func finish() {
        guard isActive else { return }
        stopStream()
        let end = Date()
        closeOpenPause(at: end)
        endedAt = end
        state = .summary
        startRecordSave()
    }
```

`streamEnded()`의 else 분기에서 `endedAt = Date()` 직전에 `closeOpenPause(at:)` 호출 (같은 시각 사용):

```swift
        } else {
            let end = Date()
            closeOpenPause(at: end)
            endedAt = end
            state = .summary
            startRecordSave()
        }
```

`ingest(_:sessionStart:)`의 `guard isActive` 바로 다음에 추가:

```swift
        // 일시정지 중 샘플은 통째로 무시 — 적산·덤프·약신호 갱신 없음(스펙 §3.1 전이표)
        guard state != .paused else { return }
```

`dismissSummary()`와 `finishAcquiringCancelled()`의 초기화 블록에 추가:

```swift
        completedPauses = []
        pausedAt = nil
```

- [ ] **Step 4: 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunSessionTests test`
Expected: PASS (기존 테스트 포함 전부 — `isActive` 의미 확장으로 기존 테스트가 깨지면 안 됨)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: RunSession 수동 일시정지/재개 상태기계 추가

- State.paused 신설: tracking↔paused, paused→summary(열린 구간 자동 닫기)
- 일시정지 중 샘플 통째 무시(적산·덤프·약신호 없음), 재개 시 markGap으로 경계 거리 미가산
- 활동 시간(activeElapsedSeconds)·보정 타이머 기준(displayTimerStart) 도입 — 스펙 §3.1" \
  -- Trace/Application/RunTracking/RunSession.swift TraceTests/RunSessionTests.swift
```

---

### Task 3: 저장 스키마 — `SavedRun.pauses` + DTO v2 (하위호환)

**Files:**
- Modify: `Trace/Domain/RunTracking/Entity/SavedRun.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift`
- Test: `TraceTests/SwiftDataRunRecordRepositoryTests.swift` (추가·갱신)

**Interfaces:**
- Consumes: Task 1의 `RunPauseInterval`
- Produces (Task 4가 사용):
  - `SavedRun`에 `let pauses: [RunPauseInterval]` + `init(summary:samples:pauses:)` (기본값 `[]` — 기존 호출부 무수정)
  - `RunPersistenceDTO.currentVersion = 2`, `RunPersistenceDTO.Pause`, `Run.pauses: [Pause]?`
  - `SwiftDataRunRecordRepository.decodeRunPayload(_:) -> (samples: [SavedRunSample], pauses: [RunPauseInterval])?` — 기존 `decodeRunSamples`를 대체
- `RunRecordModel`(SwiftData 컬럼)은 **변경 없음** — pauses는 payload blob에만 들어간다(마이그레이션 리스크 0, 스펙 §4).

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SwiftDataRunRecordRepositoryTests.swift`에 추가 (기존 in-memory 리포지토리 생성·SavedRun 픽스처 관례 재사용):

```swift
    func test_일시정지_구간이_저장_후_그대로_복원된다() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let pauses = [
            RunPauseInterval(start: start.addingTimeInterval(100), end: start.addingTimeInterval(160)),
            RunPauseInterval(start: start.addingTimeInterval(400), end: start.addingTimeInterval(430)),
        ]
        let run = makeRun(startedAt: start, pauses: pauses) // 기존 픽스처 헬퍼에 pauses 파라미터 추가
        try await repository.save(run)

        let fetched = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(fetched?.pauses, pauses)
    }

    func test_v1_payload는_빈_일시정지로_해독된다() {
        // pauses 필드가 없던 기존(v1) blob — 하위호환 확인
        let v1JSON = """
        {"version":1,"samples":[{"t":700000000,"lat":37.5,"lon":127.0,"alt":10,"spd":3}]}
        """
        guard let data = v1JSON.data(using: .utf8) else { return XCTFail("픽스처 인코딩 실패") }
        let decoded = SwiftDataRunRecordRepository.decodeRunPayload(data)
        XCTAssertEqual(decoded?.samples.count, 1)
        XCTAssertEqual(decoded?.pauses, [])
    }
```

주의: `"t":700000000`은 JSONDecoder 기본 Date 전략(secondsSinceReferenceDate)의 숫자 표현이다 — 기존 v1 blob이 실제로 이 전략으로 저장돼 있으므로 픽스처도 같은 형식을 쓴다. 기존 테스트 중 `decodeRunSamples`를 호출하는 곳은 전부 `decodeRunPayload`로 바꾸고 `.samples`를 읽도록 갱신한다.

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests test`
Expected: FAIL — `pauses`/`decodeRunPayload` 미정의 (컴파일 에러)

- [ ] **Step 3: 최소 구현**

`SavedRun.swift`의 `SavedRun` 교체:

```swift
/// 저장된 러닝 기록 전체 — 상세 화면 단건 조회 전용(스펙 §2).
struct SavedRun: Equatable, Sendable {
    let summary: SavedRunSummary
    let samples: [SavedRunSample]
    /// 일시정지 구간(시각 쌍) — 샘플 간격에서 파생 불가(GPS 끊김과 구분 안 됨)라 명시 저장(MVP14 §4)
    let pauses: [RunPauseInterval]

    init(summary: SavedRunSummary, samples: [SavedRunSample], pauses: [RunPauseInterval] = []) {
        self.summary = summary
        self.samples = samples
        self.pauses = pauses
    }
}
```

`RunPersistenceDTO.swift` 수정:

```swift
enum RunPersistenceDTO: Sendable {
    // v2: pauses 추가(additive). v1 blob은 pauses 부재 → 빈 배열로 해독(하위호환).
    static let currentVersion = 2

    struct Sample: Codable {
        let t: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double
    }

    struct Pause: Codable {
        let s: Date
        let e: Date
    }

    struct Run: Codable {
        let version: Int
        let samples: [Sample]
        let pauses: [Pause]?
    }
}
```

매핑 확장에 추가:

```swift
extension RunPersistenceDTO.Pause {
    init(_ interval: RunPauseInterval) {
        self.init(s: interval.start, e: interval.end)
    }

    var domain: RunPauseInterval {
        RunPauseInterval(start: s, end: e)
    }
}
```

`SwiftDataRunRecordRepository.swift` 수정 — `save`의 DTO 생성:

```swift
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: run.samples.map(RunPersistenceDTO.Sample.init),
            pauses: run.pauses.map(RunPersistenceDTO.Pause.init)
        )
```

`decodeRunSamples`를 `decodeRunPayload`로 교체:

```swift
    static func decodeRunPayload(
        _ data: Data
    ) -> (samples: [SavedRunSample], pauses: [RunPauseInterval])? {
        guard let dto = try? JSONDecoder().decode(RunPersistenceDTO.Run.self, from: data),
              dto.version <= RunPersistenceDTO.currentVersion else { return nil }
        return (dto.samples.map(\.domain), (dto.pauses ?? []).map(\.domain))
    }
```

`fetchRun(id:)`의 해독부 교체:

```swift
        guard let payload = Self.decodeRunPayload(record.payload) else { return nil }
        return SavedRun(
            summary: SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            ),
            samples: payload.samples,
            pauses: payload.pauses
        )
```

- [ ] **Step 4: 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests -only-testing:TraceTests/SavedRunTests test`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 러닝 기록에 일시정지 구간 저장 (DTO v2, additive)

- SavedRun.pauses 추가(기본값 []로 기존 호출부 무수정), DTO에 Pause(s,e)와 버전 2 도입
- v1 blob은 pauses 부재를 빈 배열로 해독 — 하위호환 테스트 포함
- SwiftData 모델 컬럼 변경 없음(payload에만 저장) — 마이그레이션 리스크 0, 스펙 §4" \
  -- Trace/Domain/RunTracking/Entity/SavedRun.swift Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift TraceTests/SwiftDataRunRecordRepositoryTests.swift
```

---

### Task 4: 저장 통합 — 기록 duration을 활동 시간으로 + pauses 포함

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift` (`startRecordSave`)
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` (`endRun`의 요약 시간 캡처)
- Test: `TraceTests/RunSessionTests.swift`, `TraceTests/RunPageViewModelTests.swift` (추가)

**Interfaces:**
- Consumes: Task 2 `activeElapsedSeconds`/`completedPauses`, Task 3 `SavedRun(pauses:)`
- Produces: 저장되는 `SavedRunSummary.duration` = 활동 시간(일시정지 제외). `RunPageViewModel.summaryElapsedSeconds`도 활동 시간 기준. `SavedRunSummary.averagePaceSecondsPerKm`는 기존 정의(거리/duration) 그대로 — duration 의미 변경으로 자동으로 활동 기준 페이스가 된다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunSessionTests.swift`에 추가 (기존 저장 검증 테스트가 쓰는 `recordRepository.savedRuns` 관례 재사용 — 실제 프로퍼티명은 MockRunRecordRepository 정의를 따른다):

```swift
    func test_저장되는_기록의_duration은_일시정지를_제외하고_pauses를_포함한다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        guard let startedAt = session.startedAt else { return XCTFail("startedAt 없음") }

        let pauseStart = startedAt.addingTimeInterval(60)
        session.pause(now: pauseStart)
        session.resume(now: pauseStart.addingTimeInterval(30))
        session.finish()
        await waitUntil { session.saveStatus == .saved }

        guard let saved = recordRepository.savedRuns.first else { return XCTFail("저장 없음") }
        XCTAssertEqual(saved.pauses.count, 1)
        XCTAssertEqual(saved.pauses[0].duration, 30, accuracy: 0.001)
        // 벽시계 경과보다 정확히 30초 짧아야 한다
        guard let endedWall = saved.pauses.first.map({ _ in Date() }) else { return }
        _ = endedWall // finish 시각을 직접 알 수 없으므로 관계식으로 검증:
        // duration + 일시정지합 ≈ 벽시계 경과(오차 1초 이내 — finish까지의 실행 지연)
        let wallElapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual(saved.summary.duration + 30, wallElapsed, accuracy: 1.0)
    }
```

`TraceTests/RunPageViewModelTests.swift`에 추가 (기존 세션·VM 픽스처 관례 재사용):

```swift
    func test_종료시_요약_시간은_일시정지를_제외한_활동시간이다() async {
        await viewModel.startTapped()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        guard let startedAt = session.startedAt else { return XCTFail("startedAt 없음") }

        let pauseStart = startedAt.addingTimeInterval(50)
        session.pause(now: pauseStart)
        session.resume(now: pauseStart.addingTimeInterval(20))
        viewModel.endRun()

        let wallElapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual((viewModel.summaryElapsedSeconds ?? -1) + 20, wallElapsed, accuracy: 1.0)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunSessionTests -only-testing:TraceTests/RunPageViewModelTests test`
Expected: FAIL — duration이 벽시계 기준이라 30초/20초 차이 검증 실패 (`saved.pauses` 빈 배열 실패 포함)

- [ ] **Step 3: 최소 구현**

`RunSession.startRecordSave()` 교체:

```swift
    private func startRecordSave() {
        guard let startedAt, let endedAt, track.samples.isEmpty == false else { return }
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(),
                startedAt: startedAt,
                distanceMeters: track.totalDistanceMeters,
                // 활동 시간(벽시계 − 일시정지 합) — 트래킹 화면·요약이 보여주는 시간과 같은 기준(MVP14 §3.1)
                duration: endedAt.timeIntervalSince(startedAt) - totalPausedSeconds(now: endedAt),
                elevationGainMeters: track.elevationGainMeters
            ),
            samples: track.samples.map(SavedRunSample.init),
            pauses: completedPauses
        )
        pendingRun = run
        performSave(run)
    }
```

`RunPageViewModel.endRun()`의 캡처 교체:

```swift
    func endRun() {
        summaryElapsedSeconds = session.activeElapsedSeconds()
        session.finish()
        // (이하 카메라 핏 로직 기존 그대로)
```

`summaryElapsedSeconds` 프로퍼티의 주석도 "활동 시간(일시정지 제외)" 기준으로 갱신한다.

- [ ] **Step 4: 통과 확인**

Run: Step 2와 동일 명령. Expected: PASS (기존 저장 테스트 포함)

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 기록 duration을 활동 시간 기준으로 전환 + 일시정지 구간 저장 연결

- startRecordSave: duration = 벽시계 경과 − 일시정지 합, pauses = completedPauses
- 요약 화면 시간(summaryElapsedSeconds)도 activeElapsedSeconds로 캡처
- 평균 페이스는 duration 의미 변경으로 자동으로 활동 기준이 된다 — 스펙 §3.1·§4" \
  -- Trace/Application/RunTracking/RunSession.swift Trace/Pages/RunPage/RunPageViewModel.swift TraceTests/RunSessionTests.swift TraceTests/RunPageViewModelTests.swift
```

---

### Task 5: 트래킹 UI — 일시정지/재개 버튼 + 타이머 보정

**Files:**
- Modify: `Trace/Pages/RunPage/RunPage.swift` (`controls`의 `.paused` 분기)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (`RunStatsPanel`)
- Test: 로직은 Task 2·4에서 커버 — 이 Task는 뷰 조립이라 신규 단위 테스트 없음. 빌드 + 기존 스위트 그린 + 시뮬레이터 육안 확인.

**Interfaces:**
- Consumes: Task 2의 `state == .paused`, `pause()`/`resume()`, `displayTimerStart`, `activeElapsedSeconds()`, 기존 `RunDurationFormatter.string(seconds:)`
- Produces: 사용자 조작 진입점(결정 8 — 앱 내 버튼만). UI 배치·스타일 세부는 자동 진행 대상(확인 불필요).

- [ ] **Step 1: `RunPage.controls`에 `.paused` 분기 추가**

```swift
        case .tracking, .paused:
            RunStatsPanel(viewModel: viewModel)
```

(기존 `case .tracking:` 라인을 위처럼 교체)

- [ ] **Step 2: `RunStatsPanel` 수정 — 시간 표시를 보정 타이머로 교체**

기존 `if let startedAt = viewModel.session.startedAt { ... Text(startedAt, style: .timer) ... }` 블록을 다음으로 교체:

```swift
                VStack(spacing: 2) {
                    if viewModel.session.isPaused {
                        // 멈춘 시간 고정 표시 — activeElapsedSeconds는 일시정지 중 상수라 안전
                        Text(RunDurationFormatter.string(
                            seconds: viewModel.session.activeElapsedSeconds() ?? 0
                        ))
                        .font(DesignToken.Typography.segmentRowDistance)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink2)
                    } else if let timerStart = viewModel.session.displayTimerStart {
                        Text(timerInterval: timerStart...Date.distantFuture, countsDown: false)
                            .font(DesignToken.Typography.segmentRowDistance)
                            .monospacedDigit()
                    }
                    Text("시간").font(DesignToken.Typography.sectionLabel)
                        .foregroundStyle(DesignToken.Color.ink2)
                }
```

- [ ] **Step 3: 일시정지/재개 버튼 + 상태 라벨 추가**

`endButton` 위에 배치 (VStack 내 `endButton` 호출부를 아래로 교체):

```swift
            if viewModel.session.isPaused {
                Text("일시정지됨")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            HStack(spacing: 12) {
                pauseResumeButton
                endButton
            }
```

버튼 구현 추가:

```swift
    private var pauseResumeButton: some View {
        Button {
            if viewModel.session.isPaused {
                viewModel.session.resume()
            } else {
                viewModel.session.pause()
            }
        } label: {
            Image(systemName: viewModel.session.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 52, height: 52)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .accessibilityIdentifier("run.pauseResumeButton")
    }
```

(`endButton`은 기존 그대로 — HStack에 들어가므로 `maxWidth: .infinity`가 남은 폭을 차지한다.)

- [ ] **Step 4: 빌드 + 전체 테스트 + 시뮬레이터 육안 확인**

Run: 전체 스위트 `xcodebuild ... -parallel-testing-enabled NO test` + `swiftlint`
Expected: PASS / 위반 0. 이어서 XcodeBuildMCP로 시뮬레이터 실행(테스트 실행은 금지, 빌드/런치만) — 러닝 시작 → 일시정지(시간 멈춤·"일시정지됨" 표시) → 재개(시간 이어짐) → 종료(요약 시간이 멈춘 만큼 짧음) 육안 확인.

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 트래킹 화면 일시정지/재개 버튼 + 활동 시간 타이머

- 시간 표시를 보정 시작 시각(displayTimerStart) 기반 timerInterval로 교체, 일시정지 중엔 고정 표시
- 일시정지/재개 토글 버튼(pause/play)과 일시정지됨 라벨 추가, paused 상태도 StatsPanel 유지
- 진입점은 앱 내 버튼만 — 잠금화면 버튼은 이연(스펙 결정 8)" \
  -- Trace/Pages/RunPage/RunPage.swift Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift
```

---

### Task 6: Live Activity — 일시정지 표시 + 타이머 기준 구간 이동

**Files:**
- Modify: `Trace/Domain/RunTracking/RunActivityAttributes.swift` (`ContentState` 확장)
- Modify: `Trace/Application/RunTracking/RunActivityController.swift` (`sync`/`currentState`)
- Modify: `TraceWidgets/RunLiveActivityWidget.swift` (타이머·일시정지 렌더링)
- Test: ActivityKit은 단위 테스트 불가 — 빌드 + 기존 스위트 그린. 동작은 실기기 QA 체크리스트에서 검증(주머니 시나리오).

**Interfaces:**
- Consumes: Task 2의 `isPaused`/`displayTimerStart`/`activeElapsedSeconds()`
- Produces: `ContentState`에 `isPaused: Bool`, `timerStart: Date`, `elapsedSecondsAtPause: Double?` 추가. 위젯 타이머는 고정 `attributes.startedAt` 대신 `state.timerStart`를 쓴다(스펙 §3.1 — 리뷰에서 확정된 방식). `attributes.startedAt`은 생성 메타데이터로 유지.

- [ ] **Step 1: `ContentState` 확장**

```swift
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
        var isPaused: Bool
        /// 보정된 타이머 시작 시각(시작 + 누적 일시정지) — Text(timerInterval:)의 기준.
        /// 고정 Attributes.startedAt으로는 정지·재개를 표현할 수 없어 상태로 옮겼다(스펙 §3.1).
        var timerStart: Date
        /// 일시정지 중 고정 표시할 활동 경과(초) — isPaused일 때만 non-nil
        var elapsedSecondsAtPause: Double?
    }

    var startedAt: Date
}
```

- [ ] **Step 2: 컨트롤러 갱신 — `sync`에 `.paused` 편입 + `currentState` 확장**

`sync()`의 switch 교체:

```swift
        switch session.state {
        case .tracking, .paused:
            if activity == nil {
                startActivity()
            } else {
                updateActivity()
            }
        case .idle, .acquiring, .summary:
            endActivityIfNeeded()
        }
```

`currentState()` 교체:

```swift
    private func currentState() -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            distanceMeters: session.track.totalDistanceMeters,
            paceSecondsPerKm: session.track.currentPaceSecondsPerKm,
            isPaused: session.isPaused,
            timerStart: session.displayTimerStart ?? session.startedAt ?? Date(),
            elapsedSecondsAtPause: session.isPaused ? session.activeElapsedSeconds() : nil
        )
    }
```

`observeOnce()`의 관찰 대상은 `session.state` + `session.track.totalDistanceMeters`로 이미 충분하다(일시정지/재개는 state 변경으로 발화) — 수정 없음.

- [ ] **Step 3: 위젯 렌더링 — 시간 뷰 교체 + 일시정지 배지**

`RunLiveActivityWidget.swift`에 시간 뷰 헬퍼 추가:

```swift
    @ViewBuilder
    private func timeView(
        _ context: ActivityViewContext<RunActivityAttributes>, fontSize: CGFloat
    ) -> some View {
        VStack(spacing: 2) {
            if context.state.isPaused {
                Text(pausedElapsedText(context))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            Text(context.state.isPaused ? "일시정지" : "시간")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // 주의: 앱 타깃의 RunDurationFormatter와 로직이 동일해야 한다 — 위젯 타깃은 앱 타깃
    // 타입을 볼 수 없어 여기 중복 정의한다(paceText와 같은 이유). 원본을 고치면 같이 고칠 것.
    private func pausedElapsedText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        let total = Int(context.state.elapsedSecondsAtPause ?? 0)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
```

(중복 정의 전에 앱 타깃 `RunDurationFormatter.string(seconds:)`의 실제 포맷을 확인해 동일하게 맞춘다.)

Dynamic Island center의 기존 `VStack { Text(timerInterval: context.attributes.startedAt...) ... }`을 `timeView(context, fontSize: 22)`로, 잠금화면 `lockScreenView`의 시간 VStack을 `timeView(context, fontSize: 20)`으로 교체한다. 잠금화면 좌측 아이콘은 일시정지 상태를 반영한다:

```swift
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                .font(.title2)
```

compact/minimal 영역은 기존 그대로(거리 표시 유지).

- [ ] **Step 4: 빌드 + 전체 테스트**

Run: 전체 스위트 + `swiftlint` (위젯 타깃 포함 빌드 확인: 스킴 빌드에 TraceWidgets가 포함되는지 확인, 안 되면 `xcodebuild -project Trace.xcodeproj -scheme Trace build`에 더해 위젯 스킴도 빌드)
Expected: PASS / 위반 0. Live Activity 실동작(일시정지 배지·시간 정지·재개 후 이어짐)은 실기기 QA 항목으로 남긴다 — 시뮬레이터에서는 잠금화면 카드 표시 여부만 확인.

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: Live Activity 일시정지 표시 + 타이머 기준을 ContentState로 이동

- ContentState에 isPaused·timerStart(보정 시작)·elapsedSecondsAtPause 추가
- 위젯 타이머를 고정 Attributes.startedAt에서 state.timerStart 기반으로 교체, 일시정지 시 고정 시간+배지
- paused 상태에서도 Activity 유지·갱신(끝내지 않음) — 스펙 §3.1" \
  -- Trace/Domain/RunTracking/RunActivityAttributes.swift Trace/Application/RunTracking/RunActivityController.swift TraceWidgets/RunLiveActivityWidget.swift
```

---

### Task 7: 사이클 마무리 — 전체 검증 + 문서 갱신

**Files:**
- Modify: `docs/roadmap.md` (마일스톤 체크는 실기기 QA 통과 후 — 여기서는 하지 않음)
- Create: `docs/qa/2026-07-XX-run-pause-resume-device-checklist.md` (시나리오 카드 형식, `docs/agent-rules/testing.md` 템플릿)

**Interfaces:**
- Consumes: Task 1~6 전체
- Produces: 머지 가능 상태의 브랜치 + 실기기 QA 체크리스트

- [ ] **Step 1: 전체 스위트 + 린트 최종 실행**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```

Expected: 전체 테스트 PASS(기존 228개 + 신규), 린트 위반 0. 성공 시 스탬프 3종 갱신.

- [ ] **Step 2: 실기기 QA 체크리스트 작성**

시나리오 카드 형식(처음 쓰는 유저 기준 평이한 언어, 전문 용어 금지). 필수 시나리오: ① 뛰다가 일시정지 → 시간이 멈추는지 ② 멈춘 채 이동 후 재개 → 이동 거리가 안 늘었는지 ③ 재개 후 종료 → 요약 시간이 멈춘 만큼 짧은지 ④ 화면 끈 채(주머니) 일시정지 상태 유지 → 잠금화면 카드에 "일시정지" 표시·시간 고정 ⑤ 일시정지 중 바로 종료 ⑥ 기록 목록·상세의 시간·페이스가 활동 기준인지 ⑦ (동반 수행) MVP13 밀린 확인: 강제종료 잠금화면 카드 정리·20분+ 배터리 체감.

- [ ] **Step 3: 커밋 전 코드리뷰 요청 (superpowers:requesting-code-review)**

리뷰 통과 후 마지막 커밋. 실기기 QA는 사용자 수행 — 통과 보고를 받으면 `docs/roadmap.md`의 `run-pause-resume`을 `[x]`로 갱신하고 통합(rebase + `--ff-only`)은 사용자 지시 시 `scripts/trace-integrate.sh`로.

---

## Self-Review 결과 (플랜 작성 후 점검)

- **스펙 커버리지**: §3.1 일시정지 문단의 모든 문장이 Task에 매핑됨 — 상태 확장(T2), 스트림 유지·미적산(T2), 경계 거리 미가산(T1+T2), 활동 시간(T2+T4), 진입점 버튼(T5), 장시간 무대응(구현할 것 없음 — T2의 "무기한 paused 허용"이 곧 구현), Live Activity 타이머 기준 이동(T6), §4 스키마 1·2번 항목(T3+T4). §4의 목표 저장(3번)은 사이클 3, 스플릿(4번)은 사이클 2 — 이 플랜 범위 아님.
- **플레이스홀더 스캔**: "구현 중 확인" 성격의 지시 2건(RunTrackTests 헬퍼 중복 방지, RunDurationFormatter 포맷 일치)은 의도된 조사 지시로 유지 — 코드 부재가 아니라 기존 코드와의 정합 확인 지점.
- **타입 일관성**: `RunPauseInterval(start:end:)`·`completedPauses`·`activeElapsedSeconds(now:)`·`displayTimerStart`·`decodeRunPayload`·`ContentState(isPaused:timerStart:elapsedSecondsAtPause:)` — Task 간 시그니처 상호 참조 확인 완료.
