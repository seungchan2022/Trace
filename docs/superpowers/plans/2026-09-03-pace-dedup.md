# pace-dedup 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`(권장) 또는
> `superpowers:executing-plans`로 Task 단위로 실행한다. 체크박스(`- [ ]`)가 진행 채널이다.

**Goal:** 평균 페이스 계산식과 페이스 표기 규칙을 각각 한 자리로 모으고, 그 과정에서 요약 화면의
시간과 평균 페이스가 같은 출처를 쓰게 한다.

**Architecture:** `RunSession`이 평균 페이스 계산을 소유한다. 진입점은 둘 — 러닝 중을 위한
`averagePaceSecondsPerKm(now:)`와 종료 후를 위한 `summaryAveragePaceSecondsPerKm`이며, 계산식
자체는 두 진입점이 공유하는 `private` 헬퍼 한 곳에만 둔다. 페이스 표기는 `RunPaceFormatter`를
위젯 타깃에 편입해 앱·위젯이 같은 구현을 쓴다.

**Tech Stack:** Swift · SwiftUI · `@Observable` · XCTest · ActivityKit(위젯)

**설계 문서:** [`2026-09-03-pace-dedup-design.md`](../specs/2026-09-03-pace-dedup-design.md)

## Global Constraints

- **검증 명령은 `docs/agent-rules/testing.md`의 Baseline을 따른다.** 이 문서에 복사하지 않는다.
- **커밋 메시지는 `tag: 한국어 제목`(50자 이하) + 비어 있지 않은 본문 3~4줄**이다. `.githooks/commit-msg`가
  강제하며, `Co-Authored-By:`는 차단된다.
- **plan 체크박스는 그 Task의 코드 변경과 같은 커밋에 담는다.** 체크박스만 고치는 커밋을 만들지 않는다.
- **`RunSession.swift`는 SwiftLint `type_body_length` 303/300으로 이미 경고 상태다.** Task 2가 이를
  더 밀어 올린다. 실측해서 넘치는 폭이 크면 사용자에게 보고한다 — 경고 해소 자체는 이 사이클의 범위가 아니다.
- 값이 바뀌면 안 되는 자리와 바뀌어야 하는 자리가 섞여 있다. **Task 3의 권한 회수 경로만 동작이
  달라지고, 나머지는 전부 값이 그대로여야 한다.**

---

### Task 1: 트래킹 화면과 발화의 평균 페이스를 세션 계산에 위임

값이 바뀌지 않는 자리다. 세 곳 모두 `session.activeElapsedSeconds()`를 재료로 같은 식을 각자
적고 있었고, 목적지가 그와 **글자 그대로 같은 계산**을 이미 한다.

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift:106-114`
- Modify: `Trace/Application/RunTracking/RunAudioCoach.swift:98-103`, `:112-117`
- Test: 새로 쓰지 않는다 — `TraceTests/RunPageViewModelTests.swift`의
  `test_라이브_평균_페이스는_활동_시간_기준이다`와 `TraceTests/RunAudioCoachTests.swift`가 가드다.

**Interfaces:**
- Consumes: `RunSession.averagePaceSecondsPerKm(now:) -> Double?` (이미 존재)
- Produces: 없음 — 소비 지점만 바꾼다.

- [x] **Step 1: 기존 테스트가 통과하는 상태를 먼저 확인한다**

Baseline의 테스트 명령을 그대로 실행한다(`testing.md`). 여기서 실패가 있으면 이 계획을 시작하기 전
문제이므로 멈추고 보고한다.

- [x] **Step 2: 트래킹 화면 평균 페이스를 위임으로 바꾼다**

`RunPageViewModel.swift`의 `liveAveragePaceSecondsPerKm`을 통째로 교체한다.

```swift
    /// 트래킹 화면 평균 페이스 — 기준과 계산식은 `RunSession.averagePaceSecondsPerKm(now:)`가 갖는다.
    var liveAveragePaceSecondsPerKm: Double? {
        session.averagePaceSecondsPerKm()
    }
```

- [x] **Step 3: km 발화와 목표 달성 발화를 위임으로 바꾼다**

`RunAudioCoach.swift`의 `announceKilometerIfNeeded()`에서 인자 한 줄만 바꾼다.

```swift
        announcer.announce(RunAnnouncementBuilder.kilometer(
            km: km,
            totalSeconds: elapsed,
            averagePaceSecondsPerKm: session.averagePaceSecondsPerKm()
        ), pace: .measured, kind: .data)
```

`announceGoalIfNeeded()`에서도 같은 자리를 바꾼다.

```swift
            announcer.announce(RunAnnouncementBuilder.goalAchieved(
                distanceMeters: session.track.totalDistanceMeters,
                totalSeconds: elapsed,
                averagePaceSecondsPerKm: session.averagePaceSecondsPerKm()
            ), pace: .measured, kind: .data)
```

⚠️ `let elapsed = session.activeElapsedSeconds() ?? 0` 줄은 **지우지 않는다** — `totalSeconds:`가
그대로 쓴다. `private func averagePace(elapsed:)`도 아직 남는다(Task 3에서 마지막 소비자가 사라질 때 지운다).

- [x] **Step 4: 빌드·테스트·린트를 돌린다**

Baseline 세 명령을 순서대로 실행하고 스탬프를 남긴다(`testing.md`). 값이 바뀌지 않는 변경이므로
**기존 테스트가 전부 그대로 통과해야 한다.** 하나라도 실패하면 위임이 등가가 아니라는 뜻이므로 멈추고 조사한다.

- [x] **Step 5: 커밋**

```bash
git add Trace/Pages/RunPage/RunPageViewModel.swift \
        Trace/Application/RunTracking/RunAudioCoach.swift \
        docs/superpowers/plans/2026-09-03-pace-dedup.md
git commit -F- <<'MSG'
refactor: 트래킹·발화의 평균 페이스를 세션 계산에 위임한다

- 세 곳이 활동 시간 ÷ 거리를 각자 적고 있었고 목적지와 글자 그대로 같은 계산이라 값이 바뀌지 않는다
- 요약 경로는 종료 시각에 고정된 활동 시간을 쓰므로 이 Task에서 건드리지 않는다
- 기존 테스트가 그대로 통과하는 것으로 등가를 확인했다
MSG
```

---

### Task 2: `RunSession`에 요약용 평균 페이스를 만들고 계산식을 한 자리로 모은다

요약 화면과 종료 발화는 **종료 시각에 고정된** 활동 시간을 쓴다. 지금 목적지는 「지금 시각」
기준 하나뿐이라 그대로는 받을 수 없다. 진입점을 하나 더 두고, 계산식은 둘이 공유한다.

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift:117-129`
- Test: `TraceTests/RunSessionTests.swift` (파일 끝의 `test_거리가_없으면_평균페이스는_nil이다` 뒤에 추가)

**Interfaces:**
- Consumes: `RunSession.summaryActiveElapsedSeconds -> TimeInterval?` · `RunTrack.totalDistanceMeters` (이미 존재)
- Produces: `RunSession.summaryAveragePaceSecondsPerKm -> Double?` — Task 3의 뷰모델과 오디오 코치가 쓴다.

- [x] **Step 1: 실패하는 테스트를 쓴다**

`RunSessionTests.swift`의 `test_거리가_없으면_평균페이스는_nil이다` 바로 뒤, 클래스 닫는 괄호 앞에 넣는다.

```swift
    /// 요약용 평균 페이스는 종료 시각에 고정된 활동 시간 기준이라, 종료 후 시간이 흘러도 자라지 않는다.
    /// 트래킹 중에는 아직 끝나지 않았으므로 nil이다(pace-dedup 설계 §1).
    func test_요약_평균페이스는_종료시각에_고정된다() async throws {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 100))
        await waitUntil { session.track.totalDistanceMeters > 50 }

        XCTAssertNil(session.summaryAveragePaceSecondsPerKm, "트래킹 중에는 값이 없어야 한다")

        session.finish()
        stream.finish() // 스트림 태스크를 확실히 끝낸다 — 아래 비교 중에 거리가 변하지 않게
        let distanceAtFinish = session.track.totalDistanceMeters
        let first = try XCTUnwrap(session.summaryAveragePaceSecondsPerKm)
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms — 종료 후 시간이 흐르게 둔다

        // 거리가 변하면 아래 비교가 「자라지 않는다」를 검증하지 못하므로 먼저 못박는다
        XCTAssertEqual(session.track.totalDistanceMeters, distanceAtFinish, accuracy: 0.0001)
        let second = try XCTUnwrap(session.summaryAveragePaceSecondsPerKm)

        XCTAssertEqual(first, second, accuracy: 0.0001, "종료 후에는 값이 자라면 안 된다")
    }

    /// 일시정지한 시간은 요약 평균 페이스에서도 빠진다 — 종료 발화·요약 화면이 같은 기준이어야 한다.
    func test_요약_평균페이스도_일시정지를_제외한다() async throws {
        await session.start()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 100))
        await waitUntil { session.track.totalDistanceMeters > 50 }

        let started = try XCTUnwrap(session.startedAt)
        session.pause(now: started.addingTimeInterval(1))
        session.resume(now: started.addingTimeInterval(61)) // 60초 정지
        session.finish()

        let withPause = try XCTUnwrap(session.summaryAveragePaceSecondsPerKm)
        let elapsed = try XCTUnwrap(session.summaryActiveElapsedSeconds)
        let expected = elapsed / (session.track.totalDistanceMeters / 1000)

        XCTAssertEqual(withPause, expected, accuracy: 0.0001)
    }
```

- [x] **Step 2: 실패를 확인한다**

Baseline의 테스트 명령을 실행한다. **컴파일 실패**가 예상 결과다 —
`value of type 'RunSession' has no member 'summaryAveragePaceSecondsPerKm'`.

- [x] **Step 3: 계산식을 한 자리로 모으고 진입점 둘을 만든다**

`RunSession.swift`에서 기존 `averagePaceSecondsPerKm(now:)` 블록(주석 포함)을 아래로 통째로 교체한다.

```swift
    /// 평균 페이스(초/km) — 활동 시간(일시정지 제외) ÷ 거리. 러닝이 진행 중일 때 쓴다.
    /// 발화(`RunAudioCoach`)·요약 화면·저장된 기록과 **같은 기준**이다(MVP14 §3.1).
    /// `RunTrack.averagePaceSecondsPerKm`는 GPS 샘플 구간(일시정지 포함) 기준이라 값이 다르므로
    /// 화면·발화용으로 쓰지 않는다.
    func averagePaceSecondsPerKm(now: Date = Date()) -> Double? {
        paceSecondsPerKm(activeSeconds: activeElapsedSeconds(now: now))
    }

    /// 요약 화면·종료 발화용 평균 페이스 — 종료 시각에 고정된 활동 시간 기준이라 종료 후에도 자라지 않는다.
    /// 아직 끝나지 않은 러닝에서는 nil이다(`summaryActiveElapsedSeconds`가 nil이므로).
    var summaryAveragePaceSecondsPerKm: Double? {
        paceSecondsPerKm(activeSeconds: summaryActiveElapsedSeconds)
    }

    /// 페이스 계산식이 사는 유일한 자리 — 위 두 진입점이 재료(활동 시간)만 달리해서 쓴다.
    private func paceSecondsPerKm(activeSeconds: TimeInterval?) -> Double? {
        let distanceMeters = track.totalDistanceMeters
        guard distanceMeters > 0, let activeSeconds, activeSeconds > 0 else { return nil }
        return activeSeconds / (distanceMeters / 1000)
    }
```

⚠️ 기존 주석 중 *"같은 식이 지금 네 곳에 복사돼 있고, 다음 사이클 `pace-dedup`이 그것들을 이
자리로 모은다"* 문단은 **삭제한다** — 지금 그 사이클을 하고 있으므로 예고가 아니라 거짓말이 된다.

- [x] **Step 4: 통과를 확인한다**

Baseline 세 명령을 실행하고 스탬프를 남긴다. 새 테스트 둘이 통과하고 기존 테스트가 전부 그대로여야 한다.

- [x] **Step 5: `type_body_length` 수치를 확인해 아래 「구현 중 기록」에 적는다**

린트 출력에서 `RunSession.swift`의 `type_body_length` 줄 수를 읽어 적는다. 300을 크게 넘으면
그 사실을 사용자에게 보고한다(해소는 이 사이클의 범위가 아니다 — 백로그에 별도 항목이 있다).

- [x] **Step 6: 커밋**

```bash
git add Trace/Application/RunTracking/RunSession.swift \
        TraceTests/RunSessionTests.swift \
        docs/superpowers/plans/2026-09-03-pace-dedup.md
git commit -F- <<'MSG'
refactor: 평균 페이스 계산식을 세션 안 한 자리로 모은다

- 진입점을 둘로 나눈다 — 러닝 중은 지금 시각 기준, 요약은 종료 시각에 고정된 활동 시간 기준이다
- 계산식 자체는 private 헬퍼 한 곳에만 두고 두 진입점이 재료만 달리해 쓴다
- 요약용 진입점이 종료 후 자라지 않는 것과 일시정지를 제외하는 것을 테스트로 건다
MSG
```

---

### Task 3: 요약 화면과 종료 발화를 세션 값으로 바꾼다 (유일한 동작 변화)

요약 화면의 **시간**은 지금 뷰모델이 종료 순간에 떠 둔 스냅샷을 쓰고, 그 값이 없으면 GPS 구간
시간으로 폴백한다. 평균 페이스도 같은 스냅샷에서 나온다. 둘 다 세션에서 읽게 바꾼다.

**이 Task만 사용자에게 보이는 것이 달라진다** — 위치 권한이 회수돼 종료 버튼을 거치지 않고 끝난
러닝의 요약에서, 시간이 활동 시간 기준이 되고 평균 페이스가 값을 갖는다.

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift` — `:41-43`(선언) · `:116-124`(요약 페이스) ·
  `:181`(초기화) · `:213`(스냅샷)
- Modify: `Trace/Application/RunTracking/RunAudioCoach.swift:65-71`, `:124-129`
- Modify: `Trace/Domain/RunTracking/Entity/RunTrack.swift:30`(주석만)
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: `RunSession.summaryAveragePaceSecondsPerKm`(Task 2) · `RunSession.summaryActiveElapsedSeconds`
- Produces: `RunPageViewModel.summaryElapsedSeconds`가 저장 프로퍼티에서 **계산 프로퍼티**로 바뀐다.
  타입(`TimeInterval?`)과 이름은 그대로라 화면 코드는 손대지 않는다.

- [x] **Step 1: 실패하는 테스트를 쓴다**

`RunPageViewModelTests.swift`의 `test_요약_평균_페이스는_일시정지를_제외한_활동시간_기준이다` 뒤에 넣는다.

```swift
    /// 위치 권한이 회수돼 종료 버튼 없이 끝난 러닝에서도 요약의 시간·평균 페이스가 채워져야 한다.
    /// 종료 버튼 경로와 같은 기준(활동 시간)을 써야 같은 화면의 두 값이 어긋나지 않는다.
    /// 바꾸기 전에는 스냅샷이 채워지지 않아 페이스가 nil이고 시간은 GPS 구간 값으로 폴백됐다
    /// (pace-dedup 설계 §2).
    func test_권한회수로_끝난_러닝도_요약_시간과_페이스가_채워진다() async throws {
        await viewModel.startTapped()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 100))
        await waitUntil { session.track.totalDistanceMeters > 50 }

        stream.finish() // 권한 회수 등으로 스트림 종료 — endRun()을 거치지 않는다
        await waitUntil { session.state == .summary }

        let elapsed = try XCTUnwrap(viewModel.summaryElapsedSeconds)
        let pace = try XCTUnwrap(viewModel.summaryAveragePaceSecondsPerKm)
        XCTAssertEqual(pace, elapsed / (session.track.totalDistanceMeters / 1000), accuracy: 0.0001)
    }

    /// 요약 화면의 시간과 평균 페이스가 같은 출처에서 나온다 — 하나만 세션으로 옮기면
    /// 두 값이 서로 다른 기준을 쓰게 되고, 그것이 MVP14 §3.1이 잡은 불일치다.
    func test_요약의_시간과_평균페이스는_같은_출처를_쓴다() async throws {
        await viewModel.startTapped()
        let base = Date()
        stream.yield(sample(at: base))
        await waitUntil { session.state == .tracking }
        stream.yield(sample(at: base.addingTimeInterval(10), latOffsetMeters: 100))
        await waitUntil { session.track.totalDistanceMeters > 50 }

        let started = try XCTUnwrap(session.startedAt)
        session.pause(now: started.addingTimeInterval(1))
        session.resume(now: started.addingTimeInterval(61)) // 60초 정지
        viewModel.endRun()

        let elapsed = try XCTUnwrap(viewModel.summaryElapsedSeconds)
        let pace = try XCTUnwrap(viewModel.summaryAveragePaceSecondsPerKm)
        XCTAssertEqual(pace, elapsed / (session.track.totalDistanceMeters / 1000), accuracy: 0.0001)
        XCTAssertEqual(elapsed, session.summaryActiveElapsedSeconds ?? -1, accuracy: 0.0001)
    }
```

- [x] **Step 2: 실패를 확인한다**

Baseline의 테스트 명령을 실행한다. 예상 결과는 `test_권한회수로_끝난_러닝도_...`가
`XCTUnwrap` 실패로 떨어지는 것이다 — 스냅샷이 채워지지 않아 평균 페이스가 nil이다.

- [x] **Step 3: 뷰모델의 스냅샷을 세션 위임으로 바꾼다**

`RunPageViewModel.swift`에서 저장 프로퍼티 선언(주석 세 줄 포함)을 지운다.

```swift
    /// 요약 화면에 보여줄 활동 시간(일시정지 제외) — 트래킹 화면·Live Activity가 보여준 시간과 같은 기준(MVP14 §3.1).
    /// `RunTrack.duration`(GPS 샘플 구간)과는 다른 측정치라 별도로 종료 시점에 캡처해 둔다.
    private(set) var summaryElapsedSeconds: TimeInterval?
```

그리고 `liveAveragePaceSecondsPerKm` 아래, 요약 페이스 자리에 계산 프로퍼티 둘을 둔다.
기존 `summaryAveragePaceSecondsPerKm` 블록은 주석까지 통째로 교체한다.

```swift
    /// 요약 화면에 보여줄 활동 시간(일시정지 제외) — 세션이 종료 시각 기준으로 고정해 둔 값이다.
    /// 종료 버튼을 거치지 않고 끝난 러닝(권한 회수 등)에서도 같은 기준으로 채워진다.
    var summaryElapsedSeconds: TimeInterval? {
        session.summaryActiveElapsedSeconds
    }

    /// 요약 화면 평균 페이스 — 기준과 계산식은 `RunSession.summaryAveragePaceSecondsPerKm`가 갖는다.
    /// 위 시간과 **같은 출처**여서 한 화면의 두 값이 어긋나지 않는다(MVP14 §3.1).
    var summaryAveragePaceSecondsPerKm: Double? {
        session.summaryAveragePaceSecondsPerKm
    }
```

- [x] **Step 4: 스냅샷을 쓰고 지우던 두 줄을 없앤다**

`endRun()`에서 이 줄을 지운다.

```swift
        summaryElapsedSeconds = session.activeElapsedSeconds()
```

`startTapped()` 끝에서 이 줄을 지운다.

```swift
        summaryElapsedSeconds = nil
```

⚠️ 두 줄은 **스냅샷 방식이라서 필요했던 방어 코드**다. 세션에서 직접 읽으면 `dismissSummary()`가
`endedAt`을 지울 때 값이 함께 사라지므로 낡은 값이 다음 러닝에 새지 않는다.

**「요약을 닫지 않고 다음 러닝을 시작하면 낡은 값이 남지 않나」는 코드가 이미 막고 있다**
(2026-09-03 확인) — `prepareStart()`가 `guard state == .idle`로 시작하고, `.summary`에서 `.idle`로
가는 유일한 경로가 `dismissSummary()`이며 거기서 `endedAt = nil`이 된다. 그래도 이 논리에 기대지
말고 `test_다음_러닝을_시작하면_이전_요약_경과시간이_초기화된다`가 통과하는 것으로 확인한다.

- [x] **Step 5: 종료 발화를 세션 값으로 바꾸고 죽은 헬퍼를 지운다**

`RunAudioCoach.swift`의 `.summary` 분기에서 인자를 바꾼다.

```swift
        case (_, .summary):
            let elapsed = session.summaryActiveElapsedSeconds ?? 0
            announcer.announce(RunAnnouncementBuilder.finish(
                distanceMeters: session.track.totalDistanceMeters,
                totalSeconds: elapsed,
                averagePaceSecondsPerKm: session.summaryAveragePaceSecondsPerKm
            ))
```

마지막 소비자가 사라졌으므로 `private func averagePace(elapsed:)`를 **주석까지 통째로 지운다**.

- [x] **Step 6: `RunTrack`의 대조군 프로퍼티에 존재 이유를 적는다**

`RunTrack.swift`의 `averagePaceSecondsPerKm` 위에 주석을 단다.

```swift
    /// GPS 샘플 구간(첫~마지막 타임스탬프, 일시정지 **포함**) 기준 평균 페이스.
    ///
    /// **프로덕션 화면·발화는 이 값을 쓰지 않는다** — 그쪽은 활동 시간 기준인
    /// `RunSession.averagePaceSecondsPerKm(now:)`를 쓴다(MVP14 §3.1).
    /// **그렇다고 지우지 말 것**: `RunPageViewModelTests`가 이 값을 `buggyPace` 대조군으로 삼아
    /// 「뷰모델이 GPS 구간 기준을 쓰지 않는다」를 증명한다. 지우면 그 회귀 가드가 함께 사라진다.
    var averagePaceSecondsPerKm: Double? {
```

- [x] **Step 7: 통과를 확인한다**

Baseline 세 명령을 실행하고 스탬프를 남긴다. 새 테스트 둘이 통과하고, **기존 요약 테스트 다섯
개가 그대로 통과해야 한다** — `test_종료하면_시작시각부터의_벽시계_경과시간을_캡처한다` ·
`test_시작하지_않은_상태에서_종료해도_크래시_없이_nil로_남는다` ·
`test_다음_러닝을_시작하면_이전_요약_경과시간이_초기화된다` ·
`test_종료시_요약_시간은_일시정지를_제외한_활동시간이다` ·
`test_요약_평균_페이스는_일시정지를_제외한_활동시간_기준이다`. 여기가 회귀를 잡는 자리다.

- [x] **Step 8: 커밋**

```bash
git add Trace/Pages/RunPage/RunPageViewModel.swift \
        Trace/Application/RunTracking/RunAudioCoach.swift \
        Trace/Domain/RunTracking/Entity/RunTrack.swift \
        TraceTests/RunPageViewModelTests.swift \
        docs/superpowers/plans/2026-09-03-pace-dedup.md
git commit -F- <<'MSG'
refactor: 요약 화면의 시간과 페이스를 세션 한 출처로 묶는다

- 뷰모델이 종료 순간에 뜨던 스냅샷을 없애고 세션의 종료 시각 기준 값을 읽는다
- 권한 회수로 끝난 러닝의 요약에서 시간 기준이 바뀌고 평균 페이스가 보이게 된다(유일한 동작 변화)
- 스냅샷이라서 필요했던 낡은 값 방어 두 줄이 함께 사라진다
- RunTrack의 GPS 구간 기준 페이스는 테스트 대조군이라 지우지 말라고 주석에 못박는다
MSG
```

---

### Task 4: 페이스 포맷터를 위젯 타깃과 공유하고 60분 상한 근거를 남긴다

초/km를 `5'42"`로 바꾸는 규칙이 앱과 위젯에 따로 있고, 양쪽 주석이 *"고치면 같이 고칠 것"*이라고
경고하는 상태로 유지되고 있다. 프로젝트가 폴더 동기화 방식이라 위젯 타깃 편입은 경로 한 줄이다.

**Files:**
- Modify: `Trace.xcodeproj/project.pbxproj` — `EC23B82B30053246005A586D`의 `membershipExceptions`
- Modify: `TraceWidgets/RunLiveActivityWidget.swift:161-175`
- Modify: `Trace/DesignSystem/Formatter/RunPaceFormatter.swift`
- Test: 새로 쓰지 않는다 — `TraceTests/RunPaceFormatterTests.swift`가 이제 두 타깃의 유일한 구현을 덮는다.

**Interfaces:**
- Consumes: `RunPaceFormatter.string(secondsPerKm:) -> String` (이미 존재, 시그니처 변경 없음)
- Produces: 없음.

- [x] **Step 1: 프로젝트 파일에 위젯 타깃 멤버십을 더한다**

`project.pbxproj`의 `Exceptions for "Trace" folder in "TraceWidgetsExtension" target` 블록에서
`membershipExceptions` 목록에 한 줄을 더한다.

```
			membershipExceptions = (
				App/MarkRunWaypointIntent.swift,
				DesignSystem/Formatter/RunPaceFormatter.swift,
				Domain/RunTracking/RunActivityAttributes.swift,
			);
```

🔴 **경로는 동기화 루트 그룹(`Trace`) 기준 상대 경로다.** 앞에 `Trace/`를 붙이면 오류 없이 조용히
아무 일도 일어나지 않는다. 기존 두 줄과 같은 형태인지 눈으로 확인한다.

- [x] **Step 2: 위젯의 복사본 둘을 공유 구현 호출로 바꾼다**

`RunLiveActivityWidget.swift`에서 두 함수를 주석까지 통째로 교체한다.

```swift
    private func paceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        RunPaceFormatter.string(secondsPerKm: context.state.paceSecondsPerKm)
    }

    private func averagePaceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        RunPaceFormatter.string(secondsPerKm: context.state.averagePaceSecondsPerKm)
    }
```

⚠️ 바로 위의 `pausedElapsedText`와 그 주석은 **건드리지 않는다** — `RunDurationFormatter`의 같은
중복이지만 이번 범위가 아니다(설계 「범위 밖」).

- [x] **Step 3: 포맷터에 상한 근거와 공유 사실을 적는다**

`RunPaceFormatter.swift`의 주석 블록을 교체한다. 본문 로직은 그대로 둔다.

```swift
import Foundation

enum RunPaceFormatter {
    /// 초/km → `5'32"`. nil·0 이하·60분/km 초과는 `--'--"`.
    ///
    /// **앱 타깃과 위젯 타깃이 이 구현을 공유한다** — 위젯 멤버십은 프로젝트 파일의
    /// `TraceWidgetsExtension` 예외 목록에 있다(`pace-dedup`, 2026-09-03).
    ///
    /// 60분/km 상한의 근거는 **도입 시점에 기록되지 않았다.** 도입 커밋 `685ea3c`는 러닝 탭
    /// 4상태 UI를 한꺼번에 만든 커밋이라 이 값을 설명하지 않는다. 걷기도 보통 10~15분/km이므로
    /// 넉넉한 sanity bound로 보이며, 실사용에서 상한에 닿은 적은 관측되지 않았다.
    /// 아주 느린 활동(하이킹 등)을 지원하게 되면 이 값을 다시 정해야 한다.
    static func string(secondsPerKm: Double?) -> String {
        guard let seconds = secondsPerKm, seconds > 0, seconds < 3600 else { return "--'--\"" }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d'%02d\"", minutes, remainder)
    }
}
```

- [x] **Step 4: 두 타깃을 각각 빌드해서 확인한다**

🔴 **읽어서 판정하지 않는다.** 유닛 테스트는 타깃 멤버십 변경을 전혀 덮지 않는다.

먼저 Baseline의 빌드 명령으로 앱 스킴(`Trace`)을 빌드한다. 앱이 위젯 확장을 임베드하므로 보통
함께 컴파일되지만 **거기에 기대지 않고 위젯 스킴도 따로 빌드한다** — 이 프로젝트에는 스킴이
`Trace`와 `TraceWidgetsExtension` 둘 있다(2026-09-03 확인). 이 사이클에만 쓰는 명령이라 여기 적는다:

```bash
xcodebuild -project Trace.xcodeproj -scheme TraceWidgetsExtension \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
```

`SIM_UDID`는 `testing.md`의 「기준 시뮬레이터 선택 절차」에서 고정한 값을 쓴다.
위젯 쪽에서 `cannot find 'RunPaceFormatter' in scope`가 나오면 Step 1의 경로가 틀린 것이다.

- [x] **Step 5: 테스트·린트를 돌린다**

Baseline의 나머지 두 명령을 실행하고 스탬프를 남긴다. `RunPaceFormatterTests`가 그대로 통과해야 한다.

- [x] **Step 6: 커밋**

⚠️ `.xcodeproj` 변경이 포함되므로 pre-commit이 검증 스탬프 세 개를 모두 요구한다(`testing.md`).
Step 4·5를 건너뛰면 커밋이 막힌다.

```bash
git add Trace.xcodeproj/project.pbxproj \
        TraceWidgets/RunLiveActivityWidget.swift \
        Trace/DesignSystem/Formatter/RunPaceFormatter.swift \
        docs/superpowers/plans/2026-09-03-pace-dedup.md
git commit -F- <<'MSG'
refactor: 페이스 포맷터를 앱과 위젯이 공유하게 한다

- 위젯 타깃이 앱 파일을 볼 수 있게 프로젝트의 멤버십 예외 목록에 경로 한 줄을 더한다
- 위젯에 복사돼 있던 표기 규칙 둘을 지우고 공유 구현을 부르게 해 기존 테스트가 두 타깃을 덮는다
- 60분/km 상한은 도입 커밋에 근거가 없다는 사실과 넉넉한 상한이라는 관측을 주석에 남긴다
MSG
```

---

## 구현 중 기록

Task 2 완료:
- `RunSession.swift` type_body_length: 308줄 (이전 303줄, +5줄)
- **finish() 메서드에 now: Date 파라미터 추가** — 선언 스코프 117-129를 벗어나는 변경. 원인: 테스트의 일시정지 재개 로직(60초 정지 간격을 pause/resume 호출로 표현)이 실제 벽시계 시간(밀리초)과 맞지 않으면 summaryActiveElapsedSeconds가 깊게 음수가 되어 activeSeconds > 0 가드를 통과하지 못하고 XCTUnwrap이 throw한다. 안전성: 기존 규칙(pause(now:) · resume(now:) · totalPausedSeconds(now:) · activeElapsedSeconds(now:))을 따르고, 모든 다른 호출처(RunPageViewModel.swift:214 · 테스트 ~20곳)는 인자 없이 호출하므로 기본값 도입이 역호환성을 보존하며, 비파괴 확인됨.
- 두 새 테스트 모두 통과

Task 3 완료:
- **`test_요약의_시간과_평균페이스는_같은_출처를_쓴다`의 종료 호출을 `viewModel.endRun()`에서
  `session.finish(now: started.addingTimeInterval(70))`로 바꿈** — 브리프 Step 1이 준 테스트 코드의
  리터럴을 한 줄 벗어나는 변경(파일은 이미 Test 선언 스코프인 `TraceTests/RunPageViewModelTests.swift`
  안). 원인: Task 2와 같은 패턴의 지연 버그. 이 테스트가 만드는 60초짜리 가상 정지 구간
  (`started+1` ~ `started+61`)은 `viewModel.endRun()`이 인자 없이 부르는 `session.finish()`가
  기본값 `Date()`(실제 벽시계, 테스트 실행 중 수 ms)를 종료 시각으로 쓰기 때문에, 종료 시각이 정지
  구간보다 훨씬 앞서 활동 시간이 깊은 음수가 된다 — `RunSession.paceSecondsPerKm`의
  `activeSeconds > 0` 가드에 걸려 `summaryAveragePaceSecondsPerKm`이 nil이 되고 `XCTUnwrap`이
  던진다(2줄 위 `summaryElapsedSeconds` unwrap은 통과 — 음수도 non-nil이라서 실패 지점이 갈린다).
  안전성: `RunPageViewModel.endRun()`은 이번 Task가 시그니처를 바꾸지 않았고(브리프 범위 준수),
  `RunSession`은 이미 모든 시간 관련 API(`pause(now:)`·`resume(now:)`·`finish(now:)`·
  `activeElapsedSeconds(now:)`)가 `now:` 주입을 지원하므로 테스트에서 `session`(뷰모델의 공개
  프로퍼티)을 통해 직접 `finish(now:)`를 부르는 것은 기존 관례를 그대로 따른 것이다. 커밋
  `5f57684`·`3c42e33`이 `RunSessionTests.test_요약_평균페이스도_일시정지를_제외한다`에서 같은
  `+1`/`+61` 오프셋을 `finish(now: started.addingTimeInterval(70))`로 고친 것과 동일한 대응이며,
  값(+70)도 그대로 맞췄다. `endRun()`은 이 Task의 Step 4로 스냅샷 대입 두 줄만 사라졌을 뿐 이미
  인자를 받지 않았으므로 프로덕션 시그니처 변경은 없다.
  **리뷰어가 판단할 지점**: `viewModel.endRun()` 대신 `session.finish(now:)`로 직접 종료시키는
  방식이 이 테스트의 의도(뷰모델의 두 프로퍼티가 같은 출처를 쓰는지 확인)를 그대로 담는지 여부.
- 새 테스트 둘, 기존 요약 회귀 테스트 다섯 개(`test_종료하면_시작시각부터의_벽시계_경과시간을_캡처한다`·
  `test_시작하지_않은_상태에서_종료해도_크래시_없이_nil로_남는다`·
  `test_다음_러닝을_시작하면_이전_요약_경과시간이_초기화된다`·
  `test_종료시_요약_시간은_일시정지를_제외한_활동시간이다`·
  `test_요약_평균_페이스는_일시정지를_제외한_활동시간_기준이다`) 모두 통과, 전체 385개 유닛 테스트 +
  UI 테스트 8개 무실패

## 종료

절차 본문은 `docs/agent-rules/workflow.md`의 「마일스톤 종료 절차」가 정본이다. 대상 지정만 적는다.

- [ ] 실기기 QA — **조건부 면제**(설계 「실기기 QA」 절의 판단). 체크리스트를 새로 쓰지 않는다.
- [ ] 잠금화면 페이스 표시 확인을 **백로그의 실주행 확인 항목으로 올린다.** `pace-definition`이
      남긴 「10초로 줄인 현재 페이스 창의 표시 안정성」 **바로 옆에 둔다** — 둘 다 한 번 달릴 때
      함께 확인되는 것이라 흩어 두면 다음에 또 찾아 모아야 한다.
      🔴 **사이클 종료는 이 확인을 기다리지 않는다.** 닫기 위해 일부러 달려야 하는 항목으로
      만들지 않는다(2026-09-03 사용자 지시). 실제로 달릴 수 있을 때 확인되고, 이상하면 그때 듣는다.
- [ ] `docs/roadmap.md` — 「진행 중」의 `pace-dedup` 항목을 「완료 · MVP 밖 독립 사이클」로 옮기고
      결과·검증·예상이 빗나간 지점을 남긴다.
- [ ] `docs/current-mvp.md` — 현재 상태와 다음에 착수할 수 있는 것을 갱신한다.
- [ ] `docs/backlog.md` 3건(평균 페이스 식 복사 · 60분 상한 근거 · 포맷터 이중 구현)을
      `docs/backlog-archive.md`로 옮기고, 새로 발견한 셋을 백로그에 올린다 — 저장 경로에 남는 식 두 자리 ·
      `SavedRun.swift:10`의 낡은 `duration` 주석 · `RunDurationFormatter`의 앱·위젯 이중 구현.
- [ ] `docs/workflow-audit.md` §6의 「다음에 관찰할 것」 둘을 판정한다 — §5-9 처방(이 「종료」 절
      체크박스)이 작동했는지, §5-10의 처방 후보 셋이 실제로 필요한 만큼인지.
