# run-waypoints 구현 플랜 (MVP15 사이클 ②)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 달리는 중 버튼(앱 내 + 잠금화면 Live Activity)으로 포인트를 찍으면 직전 포인트부터의 구간 거리를 발화·표시하고, 포인트 스트림을 기록에 additive로 저장해 기록 상세에서 번호 마커·구간 표·개별 삭제를 제공한다.

**Architecture:** 포인트는 `RunSession`(Application)의 상태로 쌓이고 — 좌표는 마지막 유효 샘플, 거리는 기존 총거리 적산의 스냅샷 차분(새 거리 계산 없음) — 발화는 기존 `RunAudioCoach` 관찰 경로가, 잠금화면 갱신은 기존 `RunActivityController` 관찰 경로가 맡는다. 입력 채널(앱 버튼·잠금화면 인텐트)은 전부 `session.markWaypoint()` 한 연산으로 수렴한다(미래 워치 버튼도 같은 지점에 연결 — 스펙 §2.1). 저장은 `RunPersistenceDTO` v4 additive 확장.

**Tech Stack:** Swift 6(클래식 격리 + 명시 `@MainActor`), SwiftUI, XCTest, SwiftData(별도 러닝 스토어), ActivityKit + AppIntents(`LiveActivityIntent`), AVSpeechSynthesizer.

**스펙:** `docs/superpowers/specs/2026-07-17-run-detail-waypoints-design.md` §2 (발화 문안은 §1.3 표)

## Global Constraints

- Swift 6 언어 모드, 격리 기본값은 클래식(기본 nonisolated) + UI/상태 타입에 명시적 `@MainActor`. 새 타입 중 main-thread 상태를 다루는 것에만 `@MainActor`를 붙인다.
- 최소 iOS 17.0. 새 외부 의존성 금지(네이티브 API만).
- `Trace/Infrastructure/Persistence/SwiftData/` 밖에서 `import SwiftData` 금지.
- 커밋 태그: `feat`/`fix`/`docs`/`refactor`/`test`/`chore` 중 하나 + 한국어 요약. 파일은 경로로 명시적 스테이징(`git add -A`/`git add .` 금지). 푸시 금지.
- 테스트 실행은 반드시 raw `xcodebuild` + `-parallel-testing-enabled NO` (XcodeBuildMCP `test_sim` 금지 — `docs/agent-rules/testing.md`). 시뮬레이터는 iOS 26.5 하나로 고정하고 세션 내내 바꾸지 않는다:

  ```bash
  # 최초 1회: 기준 시뮬레이터 UDID 고정 (iOS 26.5, testing.md 절차)
  SIM_UDID=$(xcrun simctl list devices available | grep -A 20 'iOS 26.5' | grep -m1 -oE '[0-9A-F-]{36}')
  # 태스크별 테스트 (예: TraceTests의 특정 클래스만)
  xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -parallel-testing-enabled NO -only-testing:TraceTests/<클래스명> test
  ```
- 발화 문안은 스펙 §1.3 표가 단일 출처: 포인트 발화는 정확히 `"포인트 2, 0.87킬로미터"` 형식.
- 이 프로젝트는 Xcode 동기화 폴더(`PBXFileSystemSynchronizedRootGroup`)를 쓴다 — `Trace/` 아래 새 `.swift` 파일은 자동으로 앱 타깃에 포함된다. **위젯 타깃에도 넣어야 하는 파일만** `project.pbxproj`의 `membershipExceptions` 수정이 필요하다(Task 5에 정확한 편집 내용 있음).

---

### Task 1: RunWaypoint 엔티티 + RunSession.markWaypoint

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunWaypoint.swift`
- Modify: `Trace/Application/RunTracking/RunSession.swift`
- Test: `TraceTests/RunSessionWaypointTests.swift` (신규)

**Interfaces:**
- Consumes: `RunSession.State`, `RunTrack.totalDistanceMeters`/`samples`, `CourseCoordinate` (기존)
- Produces (이후 태스크가 의존):
  - `struct RunWaypoint: Equatable, Sendable { let timestamp: Date; let latitude: Double; let longitude: Double; let totalDistanceMeters: Double; var coordinate: CourseCoordinate }`
  - `extension [RunWaypoint] { var lastSegmentMeters: Double? }`
  - `RunSession.waypoints: [RunWaypoint]` (private(set))
  - `RunSession.canMarkWaypoint: Bool`
  - `@discardableResult RunSession.markWaypoint(now: Date = Date()) -> RunWaypoint?`

- [ ] **Step 1: 엔티티 파일 작성**

`Trace/Domain/RunTracking/Entity/RunWaypoint.swift` 생성:

```swift
import Foundation

/// 러닝 중 사용자가 찍은 포인트(스펙 §2.4) — 타임스탬프(원본 사실) + 좌표(지도 마커용,
/// 탭 시점의 마지막 유효 샘플 스냅샷) + 그 시점 누적 거리(표시용 캐시).
/// 구간 거리는 별도 계산 없이 누적 거리의 차분으로 파생된다 — 일시정지 제외·정확도 필터 등
/// 기존 적산 규칙을 자동 상속(스펙 §2.2).
struct RunWaypoint: Equatable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let totalDistanceMeters: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }
}

extension [RunWaypoint] {
    /// 마지막 포인트의 구간 거리(직전 포인트, 없으면 시작 기준) — 발화·카드·Live Activity 공용
    var lastSegmentMeters: Double? {
        guard let last else { return nil }
        return last.totalDistanceMeters - (dropLast().last?.totalDistanceMeters ?? 0)
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`TraceTests/RunSessionWaypointTests.swift` 생성 (헬퍼는 `RunSessionTests`와 동일 패턴 — `MockRunLocationStream`/`MockRunRecordRepository`는 같은 모듈의 기존 타입 재사용):

```swift
import XCTest
@testable import Trace

@MainActor
final class RunSessionWaypointTests: XCTestCase {
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)

    private func sample(at date: Date, latOffsetMeters: Double = 0, hAcc: Double = 5) -> RunSample {
        RunSample(
            timestamp: date,
            latitude: 37.5666 + latOffsetMeters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3,
            horizontalAccuracyMeters: hAcc,
            verticalAccuracyMeters: 5
        )
    }

    /// 조건이 참이 될 때까지 짧은 간격으로 폴링한다(RunSessionTests와 동일 패턴)
    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            if Date() >= deadline {
                XCTFail("timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// 시작 → 지정 오프셋 지점 샘플 수용(tracking 진입)까지 진행
    private func startTracking(at start: Date) async {
        await session.start()
        stream.yield(sample(at: start))
        await waitUntil { self.session.state == .tracking }
    }

    func test_신호확보전에는_포인트를_찍을수없다() async {
        await session.start()
        XCTAssertEqual(session.state, .acquiring)
        XCTAssertFalse(session.canMarkWaypoint)
        XCTAssertNil(session.markWaypoint())
        XCTAssertTrue(session.waypoints.isEmpty)
    }

    func test_트래킹중_포인트를_찍으면_좌표와_누적거리_스냅샷이_남는다() async {
        let start = Date()
        await startTracking(at: start)
        stream.yield(sample(at: start.addingTimeInterval(60), latOffsetMeters: 200))
        await waitUntil { self.session.track.totalDistanceMeters > 199 }

        let tapTime = start.addingTimeInterval(65)
        let waypoint = session.markWaypoint(now: tapTime)

        XCTAssertNotNil(waypoint)
        XCTAssertEqual(session.waypoints.count, 1)
        XCTAssertEqual(waypoint?.timestamp, tapTime)
        // 좌표는 마지막 유효 샘플 스냅샷
        XCTAssertEqual(waypoint?.latitude ?? 0, 37.5666 + 200 / 111_320.0, accuracy: 1e-9)
        XCTAssertEqual(waypoint?.totalDistanceMeters ?? 0,
                       session.track.totalDistanceMeters, accuracy: 0.001)
    }

    func test_두번째_포인트의_구간거리는_직전_포인트_기준이다() async {
        let start = Date()
        await startTracking(at: start)
        stream.yield(sample(at: start.addingTimeInterval(60), latOffsetMeters: 300))
        await waitUntil { self.session.track.totalDistanceMeters > 299 }
        session.markWaypoint()

        stream.yield(sample(at: start.addingTimeInterval(120), latOffsetMeters: 800))
        await waitUntil { self.session.track.totalDistanceMeters > 799 }
        session.markWaypoint()

        XCTAssertEqual(session.waypoints.count, 2)
        XCTAssertEqual(session.waypoints.lastSegmentMeters ?? 0, 500, accuracy: 1.0)
    }

    func test_일시정지중에는_포인트를_찍을수없다() async {
        let start = Date()
        await startTracking(at: start)
        session.pause()
        XCTAssertFalse(session.canMarkWaypoint)
        XCTAssertNil(session.markWaypoint())
        session.resume()
        XCTAssertTrue(session.canMarkWaypoint)
    }

    func test_GPS공백중_탭은_마지막_유효샘플_기준이고_공백거리는_다음구간에_귀속된다() async {
        // 스펙 §2.2 귀속 규칙이 이 테스트의 오라클: 공백 중 스냅샷은 마지막 유효 샘플 기준,
        // 공백이 끝날 때 한꺼번에 가산되는 직선 거리는 다음 구간으로 들어간다.
        let start = Date()
        await startTracking(at: start)
        stream.yield(sample(at: start.addingTimeInterval(60), latOffsetMeters: 200))
        await waitUntil { self.session.track.totalDistanceMeters > 199 }

        // 정확도 불량 샘플 = 공백 시작 (적산 없음)
        stream.yield(sample(at: start.addingTimeInterval(90), latOffsetMeters: 400, hAcc: 99))
        // 공백 '중' 탭 — 스냅샷은 200m 시점
        let distanceAtTap = session.track.totalDistanceMeters
        session.markWaypoint()
        XCTAssertEqual(session.waypoints[0].totalDistanceMeters, distanceAtTap, accuracy: 0.001)

        // 공백 종료 — 직선 거리(200→600m 지점, 400m)가 한꺼번에 가산됨
        stream.yield(sample(at: start.addingTimeInterval(150), latOffsetMeters: 600))
        await waitUntil { self.session.track.totalDistanceMeters > 599 }
        session.markWaypoint()
        // 공백 거리 전부가 두 번째 구간에 귀속
        XCTAssertEqual(session.waypoints.lastSegmentMeters ?? 0, 400, accuracy: 1.0)
    }

    func test_일시정지를_사이에_둔_포인트_구간거리는_멈춘_동안을_가산하지_않는다() async {
        // 스펙 §3 "일시정지 낀 경우": 스냅샷 차분 방식이라 기존 markGap 규칙(재개 직후 첫 샘플
        // 거리 미가산)이 그대로 상속되는지 확인한다
        let start = Date()
        await startTracking(at: start)
        stream.yield(sample(at: start.addingTimeInterval(60), latOffsetMeters: 300))
        await waitUntil { self.session.track.totalDistanceMeters > 299 }
        session.markWaypoint()

        session.pause(now: start.addingTimeInterval(70))
        session.resume(now: start.addingTimeInterval(190)) // 2분 정지
        // 재개 직후 첫 샘플(500m 지점)은 markGap으로 거리 미가산 — 순간이동 방지
        stream.yield(sample(at: start.addingTimeInterval(200), latOffsetMeters: 500))
        await waitUntil { self.session.track.samples.count == 3 }
        stream.yield(sample(at: start.addingTimeInterval(260), latOffsetMeters: 700))
        await waitUntil { self.session.track.totalDistanceMeters > 499 }
        session.markWaypoint()

        // 300m(포인트1) → 정지 → gap 미가산 → +200m = 총 500m: 구간 거리는 200m
        XCTAssertEqual(session.waypoints.lastSegmentMeters ?? 0, 200, accuracy: 1.0)
    }

    func test_요약을_닫으면_포인트가_비워진다() async {
        let start = Date()
        await startTracking(at: start)
        session.markWaypoint()
        session.finish()
        session.dismissSummary()
        XCTAssertTrue(session.waypoints.isEmpty)
    }

    func test_새_러닝을_준비하면_이전_포인트가_비워진다() async {
        let start = Date()
        await startTracking(at: start)
        session.markWaypoint()
        session.finish()
        // dismissSummary 없이 곧바로 다음 러닝을 준비해도 잔존하지 않아야 한다
        _ = await session.prepareStart()
        XCTAssertTrue(session.waypoints.isEmpty)
        session.cancelPreparation()
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunSessionWaypointTests test` (Global Constraints의 명령)
Expected: **컴파일 실패** — `RunSession`에 `waypoints`/`canMarkWaypoint`/`markWaypoint` 없음

- [ ] **Step 4: RunSession 구현**

`Trace/Application/RunTracking/RunSession.swift` 수정.

(a) 프로퍼티 추가 — `private(set) var goalAchieved = false` (59행 부근) 아래에:

```swift
    /// 이번 러닝에서 찍은 포인트들(스펙 §2) — 저장 payload에 그대로 들어간다
    private(set) var waypoints: [RunWaypoint] = []
```

(b) `isPaused` 아래에 활성 조건 + 마킹 연산 추가:

```swift
    /// 포인트 버튼 활성 조건(스펙 §2.2): 일시정지 아님 + 첫 유효 샘플 확보됨 = tracking 상태.
    /// (acquiring은 유효 샘플 이전, paused는 거리가 안 쌓이는 상태 — 둘 다 비활성)
    var canMarkWaypoint: Bool { state == .tracking }

    /// 포인트 찍기 — 좌표는 마지막 유효 샘플, 거리는 총거리 적산 스냅샷(스펙 §2.2·§2.4).
    /// tracking 상태는 유효 샘플 ≥ 1을 보장하므로 좌표는 항상 존재한다.
    /// 연타 방지 임계값 없음 — 0m 구간도 허용(스펙 §2.2).
    @discardableResult
    func markWaypoint(now: Date = Date()) -> RunWaypoint? {
        guard canMarkWaypoint, let lastSample = track.samples.last else { return nil }
        let waypoint = RunWaypoint(
            timestamp: now,
            latitude: lastSample.latitude,
            longitude: lastSample.longitude,
            totalDistanceMeters: track.totalDistanceMeters
        )
        waypoints.append(waypoint)
        return waypoint
    }
```

(c) 리셋 경로 3곳에 `waypoints = []` 추가 — 각각 `goalAchieved = false` 리셋이 있는 지점 바로 아래:
- `prepareStart(goal:)` (127행 부근 `goalAchieved = false` 다음)
- `finishAcquiringCancelled()` (209행 부근)
- `dismissSummary()` (227행 부근)

- [ ] **Step 5: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunSessionWaypointTests test`
Expected: PASS (7개 테스트)

- [ ] **Step 6: 커밋**

```bash
git add Trace/Domain/RunTracking/Entity/RunWaypoint.swift Trace/Application/RunTracking/RunSession.swift TraceTests/RunSessionWaypointTests.swift
git commit -m "feat: 러닝 세션 포인트 마킹 - RunWaypoint 엔티티 + 스냅샷 기반 markWaypoint"
```

---

### Task 2: 포인트 발화 — AnnouncementKind 도입 + 즉시성(끼어들기) + RunAudioCoach 연결

**Files:**
- Modify: `Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift`
- Modify: `Trace/Application/RunTracking/RunAnnouncementBuilder.swift`
- Modify: `Trace/Application/RunTracking/RunAudioCoach.swift`
- Modify: `Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift`
- Modify: `Trace/App/DependencyContainer.swift` (NoopVoiceAnnouncer 시그니처)
- Modify: `TraceTests/RunAudioCoachTests.swift` (FakeVoiceAnnouncer 시그니처)
- Modify: `TraceTests/RunPageViewModelTests.swift` (RecordingVoiceAnnouncer 시그니처)
- Test: `TraceTests/RunAnnouncementBuilderTests.swift`, `TraceTests/RunAudioCoachTests.swift`

**Interfaces:**
- Consumes: Task 1의 `RunSession.waypoints`, `[RunWaypoint].lastSegmentMeters`
- Produces:
  - `enum AnnouncementKind { case status, data, waypoint }`
  - 프로토콜 요구사항이 `announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind)`로 변경 (기존 1·2 인자 호출은 extension 기본값으로 유지 — `kind` 기본 `.status`)
  - `RunAnnouncementBuilder.waypoint(index: Int, segmentMeters: Double) -> String`
  - `RunAnnouncementBuilder.spokenWaypointDistance(_ meters: Double) -> String`

- [ ] **Step 1: 실패하는 테스트 작성 — 문안**

`TraceTests/RunAnnouncementBuilderTests.swift` 끝(클래스 닫는 `}` 앞)에 추가:

```swift
    // MARK: - 포인트 발화 (스펙 §1.3 표 + §2.2)

    func test_포인트_발화_문안() {
        XCTAssertEqual(
            RunAnnouncementBuilder.waypoint(index: 2, segmentMeters: 870),
            "포인트 2, 0.87킬로미터"
        )
    }

    func test_포인트_구간거리_낭독_형식() {
        XCTAssertEqual(RunAnnouncementBuilder.spokenWaypointDistance(870), "0.87킬로미터")
        XCTAssertEqual(RunAnnouncementBuilder.spokenWaypointDistance(1500), "1.5킬로미터")
        XCTAssertEqual(RunAnnouncementBuilder.spokenWaypointDistance(2000), "2킬로미터")
        XCTAssertEqual(RunAnnouncementBuilder.spokenWaypointDistance(0), "0킬로미터")
    }
```

- [ ] **Step 2: 실패하는 테스트 작성 — 코치 발화**

`TraceTests/RunAudioCoachTests.swift`의 `FakeVoiceAnnouncer`(236행 부근)를 새 시그니처로 교체:

```swift
@MainActor
final class FakeVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    var announcedPaces: [AnnouncementPace] = []
    var announcedKinds: [AnnouncementKind] = []
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {
        announced.append(text)
        announcedPaces.append(pace)
        announcedKinds.append(kind)
    }
}
```

클래스 끝에 테스트 추가:

```swift
    func test_포인트를_찍으면_구간거리를_waypoint_종류로_즉시_발화() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(60), metersNorth: 500))
        await waitUntil { session.track.totalDistanceMeters > 499 }
        coach.sync()
        announcer.announced.removeAll()
        announcer.announcedKinds.removeAll()

        session.markWaypoint()
        coach.sync()

        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("포인트 1, "))
        XCTAssertEqual(announcer.announcedKinds, [.waypoint])

        // 같은 상태로 다시 sync — 중복 발화 없음
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
    }

    func test_km와_목표_발화는_data_종류로_상태전환은_status로_분류된다() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announcedKinds, [.data]) // km 안내

        announcer.announcedKinds.removeAll()
        session.pause()
        coach.sync()
        XCTAssertEqual(announcer.announcedKinds, [.status]) // 일시정지
    }
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunAnnouncementBuilderTests -only-testing:TraceTests/RunAudioCoachTests test`
Expected: **컴파일 실패** — `AnnouncementKind` 미정의

- [ ] **Step 4: 프로토콜 확장**

`Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift` — `AnnouncementPace` enum 아래에 추가하고 프로토콜·extension을 다음으로 교체:

```swift
/// 발화 종류 — 포인트 발화 즉시성 규칙 판정용(스펙 §2.2): 포인트는 데이터 낭독(km·목표)이
/// 재생 중이면 중단시키고 바로 재생하되, 상태 전환 발화(시작·일시정지 등)보다는 후순위(대기)다.
enum AnnouncementKind {
    case status
    case data
    case waypoint
}

/// 음성 안내 포트 — Domain은 AVFoundation을 모른다(스펙 §3.3).
/// 발화는 fire-and-forget: 호출자는 완료를 기다리지 않고, 직렬화(큐)는 구현체 책임이다.
@MainActor
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind)
    /// 발화 묶음(카운트다운 등) 동안 오디오 세션을 잡아 덕킹을 1회로 유지한다(스펙 §1.1)
    func holdAudioSession()
    /// hold 해제 — 남은 발화가 끝나는 시점(큐 소진)에 실제 비활성화된다
    func releaseAudioSession()
    /// 진행 중·대기 중 발화 즉시 중단(카운트다운 취소용)
    func stopSpeaking()
}

extension VoiceAnnouncerProtocol {
    /// pace·kind 미지정 호출부 호환용 — 기본값은 measured(느린 속도) + status(상태 전환)
    func announce(_ text: String) { announce(text, pace: .measured, kind: .status) }
    func announce(_ text: String, pace: AnnouncementPace) { announce(text, pace: pace, kind: .status) }
    func holdAudioSession() {}
    func releaseAudioSession() {}
    func stopSpeaking() {}
}
```

- [ ] **Step 5: 빌더 문안 추가**

`Trace/Application/RunTracking/RunAnnouncementBuilder.swift` — `goalHalf` 아래에 추가:

```swift
    /// "포인트 2, 0.87킬로미터" (스펙 §1.3 표·§2.2) — 구간 거리는 직전 포인트 기준
    static func waypoint(index: Int, segmentMeters: Double) -> String {
        "포인트 \(index), \(spokenWaypointDistance(segmentMeters))"
    }

    /// 870 → "0.87킬로미터", 1500 → "1.5킬로미터", 2000 → "2킬로미터" — 구간 거리는 짧아
    /// 0.1km 반올림(spokenDistance)이 뭉개므로 소수 둘째 자리까지, 후행 0은 떼고 읽는다
    static func spokenWaypointDistance(_ meters: Double) -> String {
        var text = String(format: "%.2f", meters / 1000)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text)킬로미터"
    }
```

- [ ] **Step 6: 다른 conformer 시그니처 갱신**

(a) `Trace/App/DependencyContainer.swift`의 `NoopVoiceAnnouncer`(88행 부근):

```swift
@MainActor
private final class NoopVoiceAnnouncer: VoiceAnnouncerProtocol {
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {}
}
```

(b) `TraceTests/RunPageViewModelTests.swift`의 `RecordingVoiceAnnouncer`(5행 부근) — `announce` 시그니처만 교체:

```swift
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {
        announced.append(text)
        announcedPaces.append(pace)
    }
```

- [ ] **Step 7: SpeechVoiceAnnouncer 끼어들기 구현**

`Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift` 수정.

(a) `private var isHeld = false` 아래에 추가:

```swift
    /// 대기열에 있는 발화들의 종류(FIFO) — 첫 원소가 현재 재생 중인 발화의 종류다.
    /// 포인트 발화 즉시성(스펙 §2.2) 판정에 쓴다.
    private var queuedKinds: [AnnouncementKind] = []
```

(b) `announce(_:pace:)`를 새 시그니처로 교체:

```swift
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {
        // 포인트 발화 즉시성(스펙 §2.2): 데이터 낭독(km·목표)이 재생 중이면 중단하고 바로 말한다.
        // 상태 전환 발화가 재생 중이면 그대로 큐에 붙는다(후순위). stopSpeaking은 큐 전체를
        // 비우지만, 데이터 낭독은 단발 발화라 실질적으로 그 발화 하나만 끊긴다.
        if kind == .waypoint, queuedKinds.first == .data {
            synthesizer.stopSpeaking(at: .immediate) // didCancel 델리게이트가 카운트를 정리한다
        }
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
        queuedKinds.append(kind)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = pace == .measured ? Self.measuredSpeechRate : Self.speechRate
        synthesizer.speak(utterance)
    }
```

(c) `utteranceEnded()`에 큐 정리 한 줄 추가 (`pendingCount` 감소 다음):

```swift
    private func utteranceEnded() {
        pendingCount = max(0, pendingCount - 1)
        if queuedKinds.isEmpty == false { queuedKinds.removeFirst() }
        guard pendingCount == 0, isHeld == false else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
```

- [ ] **Step 8: RunAudioCoach 연결**

`Trace/Application/RunTracking/RunAudioCoach.swift` 수정.

(a) `private var goalAchievedAnnounced = false` 아래에 추가:

```swift
    private var lastWaypointCount = 0
```

(b) `observeOnce()`의 관찰 블록에 한 줄 추가:

```swift
            _ = session.waypoints.count
```

(c) `sync()`를 다음으로 교체 — 포인트를 km보다 먼저 처리(같은 틱에 겹치면 포인트가 먼저 말해지고 km가 뒤에 붙는다 — 포인트가 km를 끊어 km 정보가 유실되는 역순보다 낫다):

```swift
    /// 관찰 콜백의 유일한 진입점 — 테스트가 직접 호출해 발화 결정을 검증한다.
    func sync() {
        announceStateTransitionIfNeeded()
        announceWaypointIfNeeded()
        announceKilometerIfNeeded()
        announceGoalIfNeeded()
        lastState = session.state
    }
```

(d) `announceStateTransitionIfNeeded()`의 `case (.idle, .acquiring):` 리셋 묶음에 추가:

```swift
            lastWaypointCount = 0
```

(e) 새 메서드 추가 (`announceKilometerIfNeeded` 앞):

```swift
    private func announceWaypointIfNeeded() {
        let count = session.waypoints.count
        guard count > lastWaypointCount else {
            lastWaypointCount = count // 새 러닝 준비 등으로 줄어든 경우 동기화만
            return
        }
        lastWaypointCount = count
        guard let segmentMeters = session.waypoints.lastSegmentMeters else { return }
        // 발화가 주(잠금화면에선 유일) 확인 채널 — 즉시성 우선 kind(스펙 §2.2)
        announcer.announce(
            RunAnnouncementBuilder.waypoint(index: count, segmentMeters: segmentMeters),
            pace: .measured, kind: .waypoint
        )
    }
```

(f) km·목표 발화 호출 3곳에 `kind: .data` 명시:
- `announceKilometerIfNeeded()`: `announcer.announce(RunAnnouncementBuilder.kilometer(...), pace: .measured, kind: .data)`
- `announceGoalIfNeeded()`의 달성: `announcer.announce(RunAnnouncementBuilder.goalAchieved(...), pace: .measured, kind: .data)`
- `announceGoalIfNeeded()`의 절반: `announcer.announce(RunAnnouncementBuilder.goalHalf, pace: .measured, kind: .data)`

(시작·종료·일시정지·재개·카운트다운은 기존 호출 유지 — extension 기본값 `.status`.)

- [ ] **Step 9: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunAnnouncementBuilderTests -only-testing:TraceTests/RunAudioCoachTests -only-testing:TraceTests/RunPageViewModelTests test`
Expected: PASS (기존 + 신규 전부)

- [ ] **Step 10: 커밋**

```bash
git add Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift Trace/Application/RunTracking/RunAnnouncementBuilder.swift Trace/Application/RunTracking/RunAudioCoach.swift Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift Trace/App/DependencyContainer.swift TraceTests/RunAudioCoachTests.swift TraceTests/RunPageViewModelTests.swift TraceTests/RunAnnouncementBuilderTests.swift
git commit -m "feat: 포인트 발화 - AnnouncementKind 분류 + 데이터 낭독 끼어들기 + 코치 관찰 연결"
```

---

### Task 3: 저장 스키마 v4 — SavedRun.waypoints + DTO + 리포지토리 + 세션 저장 연결

**Files:**
- Modify: `Trace/Domain/RunTracking/Entity/SavedRun.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift`
- Modify: `Trace/Application/RunTracking/RunSession.swift` (startRecordSave 1줄)
- Test: `TraceTests/SwiftDataRunRecordRepositoryTests.swift`, `TraceTests/RunSessionWaypointTests.swift`

**Interfaces:**
- Consumes: Task 1의 `RunWaypoint`, `RunSession.waypoints`
- Produces:
  - `SavedRun.waypoints: [RunWaypoint]` (init 기본값 `[]` — 기존 호출부 호환)
  - `RunPersistenceDTO.currentVersion == 4`, `RunPersistenceDTO.Waypoint { t, lat, lon, d }`
  - `SwiftDataRunRecordRepository.decodeRunPayload(_:)` 반환 튜플에 `waypoints: [RunWaypoint]` 추가

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SwiftDataRunRecordRepositoryTests.swift` 클래스 끝에 추가 (기존 테스트들의 SavedRun 생성 헬퍼가 있으면 재사용, 없으면 아래처럼 직접 생성):

```swift
    // MARK: - 포인트 스트림 (v4, 스펙 §2.4)

    private func waypointRun(id: UUID = UUID(), waypoints: [RunWaypoint]) -> SavedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return SavedRun(
            summary: SavedRunSummary(
                id: id, startedAt: start, distanceMeters: 2000,
                duration: 600, elevationGainMeters: 5
            ),
            samples: [
                SavedRunSample(timestamp: start, latitude: 37.5, longitude: 127.0,
                               altitudeMeters: 10, speedMetersPerSecond: 3),
                SavedRunSample(timestamp: start.addingTimeInterval(600), latitude: 37.51, longitude: 127.0,
                               altitudeMeters: 10, speedMetersPerSecond: 3)
            ],
            waypoints: waypoints
        )
    }

    func test_포인트가_있는_기록_저장_왕복() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let waypoints = [
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        latitude: 37.505, longitude: 127.0, totalDistanceMeters: 870),
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_400),
                        latitude: 37.508, longitude: 127.0, totalDistanceMeters: 1500)
        ]
        let run = waypointRun(waypoints: waypoints)
        try await repository.save(run)

        let loaded = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(loaded?.waypoints, waypoints)
    }

    func test_포인트가_없는_기록_저장_왕복() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let run = waypointRun(waypoints: [])
        try await repository.save(run)
        let loaded = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(loaded?.waypoints, [])
    }

    func test_v3_blob은_포인트가_빈배열로_해독된다() throws {
        // 과거 기록 호환(스펙 §2.4): v3 payload에는 waypoints 키 자체가 없다
        let v3JSON = """
        {"version":3,"samples":[{"t":700000000,"lat":37.5,"lon":127.0,"alt":10,"spd":3}]}
        """
        let decoded = SwiftDataRunRecordRepository.decodeRunPayload(Data(v3JSON.utf8))
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.waypoints, [])
    }
```

`TraceTests/RunSessionWaypointTests.swift` 클래스 끝에 추가:

```swift
    func test_종료시_포인트가_기록에_저장된다() async {
        let start = Date()
        await startTracking(at: start)
        stream.yield(sample(at: start.addingTimeInterval(60), latOffsetMeters: 300))
        await waitUntil { self.session.track.totalDistanceMeters > 299 }
        session.markWaypoint()
        let expected = session.waypoints

        session.finish()
        await waitUntil { self.session.saveStatus == .saved }
        let saved = await recordRepository.savedRuns.first
        XCTAssertEqual(saved?.waypoints, expected)
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests -only-testing:TraceTests/RunSessionWaypointTests test`
Expected: **컴파일 실패** — `SavedRun`에 `waypoints` 없음

- [ ] **Step 3: SavedRun 확장**

`Trace/Domain/RunTracking/Entity/SavedRun.swift`의 `SavedRun`을 다음으로 교체:

```swift
/// 저장된 러닝 기록 전체 — 상세 화면 단건 조회 전용(스펙 §2).
struct SavedRun: Equatable, Sendable {
    let summary: SavedRunSummary
    let samples: [SavedRunSample]
    /// 일시정지 구간(시각 쌍) — 샘플 간격에서 파생 불가(GPS 끊김과 구분 안 됨)라 명시 저장(MVP14 §4)
    let pauses: [RunPauseInterval]
    /// 이번 러닝의 목표 — 상세 화면 "목표 5 km" 표시용(스펙 §4-3). 자유 러닝은 .open
    let goal: RunGoal
    /// 달리며 찍은 포인트 스트림(MVP15 §2.4, additive) — 과거 기록은 빈 배열
    let waypoints: [RunWaypoint]

    init(
        summary: SavedRunSummary, samples: [SavedRunSample],
        pauses: [RunPauseInterval] = [], goal: RunGoal = .open,
        waypoints: [RunWaypoint] = []
    ) {
        self.summary = summary
        self.samples = samples
        self.pauses = pauses
        self.goal = goal
        self.waypoints = waypoints
    }
}
```

- [ ] **Step 4: DTO v4**

`Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift` 수정.

(a) 버전 주석·상수 교체:

```swift
    // v4: waypoints 추가(additive). v3 이하 blob은 waypoints 부재 → 빈 배열로 해독(하위호환).
    // v3: goal 추가(additive). v2 이하 blob은 goal 부재 → .open으로 해독(하위호환).
    static let currentVersion = 4
```

(b) `Goal` struct 아래에 추가:

```swift
    struct Waypoint: Codable {
        let t: Date
        let lat: Double
        let lon: Double
        /// 탭 시점 누적 거리(m) — 표시용 캐시(스펙 §2.4)
        let d: Double
    }
```

(c) `Run`에 필드 추가:

```swift
    struct Run: Codable {
        let version: Int
        let samples: [Sample]
        let pauses: [Pause]?
        let goal: Goal?
        let waypoints: [Waypoint]?
    }
```

(d) 파일 끝에 매핑 extension 추가:

```swift
extension RunPersistenceDTO.Waypoint {
    init(_ waypoint: RunWaypoint) {
        self.init(t: waypoint.timestamp, lat: waypoint.latitude,
                  lon: waypoint.longitude, d: waypoint.totalDistanceMeters)
    }

    var domain: RunWaypoint {
        RunWaypoint(timestamp: t, latitude: lat, longitude: lon, totalDistanceMeters: d)
    }
}
```

- [ ] **Step 5: 리포지토리 반영**

`Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift` 수정.

(a) `save(_:)`의 DTO 생성에 waypoints 추가:

```swift
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: run.samples.map(RunPersistenceDTO.Sample.init),
            pauses: run.pauses.map(RunPersistenceDTO.Pause.init),
            goal: RunPersistenceDTO.Goal(run.goal),
            waypoints: run.waypoints.map(RunPersistenceDTO.Waypoint.init)
        )
```

(b) `decodeRunPayload(_:)` 교체:

```swift
    static func decodeRunPayload(
        _ data: Data
    ) -> (samples: [SavedRunSample], pauses: [RunPauseInterval], goal: RunGoal, waypoints: [RunWaypoint])? {
        guard let dto = try? JSONDecoder().decode(RunPersistenceDTO.Run.self, from: data),
              dto.version <= RunPersistenceDTO.currentVersion else { return nil }
        return (
            dto.samples.map(\.domain), (dto.pauses ?? []).map(\.domain),
            dto.goal?.domain ?? .open, (dto.waypoints ?? []).map(\.domain)
        )
    }
```

(c) `fetchRun(id:)`의 SavedRun 생성에 `waypoints: payload.waypoints` 추가:

```swift
        return SavedRun(
            summary: SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            ),
            samples: payload.samples,
            pauses: payload.pauses,
            goal: payload.goal,
            waypoints: payload.waypoints
        )
```

- [ ] **Step 6: 세션 저장 연결**

`Trace/Application/RunTracking/RunSession.swift`의 `startRecordSave()` — SavedRun 생성에 한 줄 추가:

```swift
            pauses: completedPauses,
            goal: goal,
            waypoints: waypoints
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests -only-testing:TraceTests/RunSessionWaypointTests -only-testing:TraceTests/SavedRunTests test`
Expected: PASS (신규 4개 + 기존 전부 — `SavedRun` init 기본값 덕에 기존 호출부 무수정)

- [ ] **Step 8: 커밋**

```bash
git add Trace/Domain/RunTracking/Entity/SavedRun.swift Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift Trace/Application/RunTracking/RunSession.swift TraceTests/SwiftDataRunRecordRepositoryTests.swift TraceTests/RunSessionWaypointTests.swift
git commit -m "feat: 포인트 스트림 저장 - DTO v4 additive 확장 + 과거 기록 호환"
```

---

### Task 4: 트래킹 화면 포인트 버튼 + 화면 카드

**Files:**
- Modify: `Trace/Pages/RunPage/RunPageViewModel.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`
- Test: `TraceTests/RunPageViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1의 `session.markWaypoint()`/`canMarkWaypoint`/`waypoints`, `[RunWaypoint].lastSegmentMeters`
- Produces:
  - `struct WaypointCard: Equatable { let index: Int; let segmentMeters: Double }` (RunPageViewModel.swift 내 파일 스코프)
  - `RunPageViewModel.waypointCard: WaypointCard?` (private(set))
  - `RunPageViewModel.markWaypointTapped()`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunPageViewModelTests.swift` 클래스 끝에 추가. 주의: 이 파일의 기존 `viewModel`은 `sleeper: { _ in }`(즉시 리턴)이라 카드 자동 소멸 검증에는 수동 게이트 sleeper로 별도 VM을 만든다:

```swift
    // MARK: - 포인트 카드 (스펙 §2.2)

    private func startTrackingForWaypoint(_ vm: RunPageViewModel, at start: Date) async {
        await vm.startTapped()
        stream.yield(RunSample(
            timestamp: start, latitude: 37.5666, longitude: 126.9784,
            altitudeMeters: 10, speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5, verticalAccuracyMeters: 5
        ))
        await waitUntil { self.session.state == .tracking }
    }

    func test_포인트를_찍으면_카드가_표시된다() async {
        let start = Date()
        await startTrackingForWaypoint(viewModel, at: start)

        viewModel.markWaypointTapped()

        XCTAssertEqual(viewModel.waypointCard?.index, 1)
        XCTAssertEqual(viewModel.waypointCard?.segmentMeters ?? -1,
                       session.waypoints.lastSegmentMeters ?? -2, accuracy: 0.001)
    }

    func test_트래킹이_아니면_카드가_생기지_않는다() async {
        viewModel.markWaypointTapped() // idle 상태
        XCTAssertNil(viewModel.waypointCard)
        XCTAssertTrue(session.waypoints.isEmpty)
    }

    func test_카드는_잠시후_자동으로_사라진다() async {
        // 게이트 sleeper(MockRunLocationStream.gateAccuracyRequest와 동일 패턴 — 가변 캡처 없음):
        // 카운트다운 sleep(1초)은 즉시 통과시키고, 카드 소멸 sleep(3초)만 잡아둔다
        let (cardGate, releaseCard) = AsyncStream.makeStream(of: Void.self)
        let vm = RunPageViewModel(
            session: session, announcer: announcer,
            sleeper: { duration in
                guard duration == .seconds(3) else { return } // 카운트다운 "삼·이·일"은 통과
                for await _ in cardGate { break } // releaseCard가 풀어줄 때까지 대기
            }
        )
        let start = Date()
        await startTrackingForWaypoint(vm, at: start)

        vm.markWaypointTapped()
        XCTAssertNotNil(vm.waypointCard)

        releaseCard.yield()
        await waitUntil { vm.waypointCard == nil }
    }
```

(`waitUntil` 헬퍼는 이 파일에 이미 있다(43행 부근) — 그대로 재사용.)

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunPageViewModelTests test`
Expected: **컴파일 실패** — `markWaypointTapped`/`waypointCard` 없음

- [ ] **Step 3: ViewModel 구현**

`Trace/Pages/RunPage/RunPageViewModel.swift` 수정.

(a) 파일 스코프(클래스 밖, `RunGoalMode` 아래)에 추가:

```swift
/// 포인트 확인용 화면 카드(보조 채널 — 주 채널은 발화, 스펙 §2.2)
struct WaypointCard: Equatable {
    let index: Int
    let segmentMeters: Double
}
```

(b) 클래스 프로퍼티 추가 (`summaryElapsedSeconds` 아래):

```swift
    /// 몇 초 표시 후 사라지는 포인트 확인 카드 — nil = 표시 안 함(스펙 §2.2)
    private(set) var waypointCard: WaypointCard?
    private var waypointCardDismissTask: Task<Void, Never>?
```

(c) 메서드 추가 (`cancelCountdown()` 아래):

```swift
    /// 포인트 버튼 탭 — 마킹은 세션, 발화는 RunAudioCoach(관찰), 여기는 화면 카드만 담당
    func markWaypointTapped() {
        guard session.markWaypoint() != nil else { return }
        guard let segmentMeters = session.waypoints.lastSegmentMeters else { return }
        waypointCard = WaypointCard(index: session.waypoints.count, segmentMeters: segmentMeters)
        waypointCardDismissTask?.cancel()
        waypointCardDismissTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleeper(.seconds(3)) } catch { return } // 취소 = 새 카드가 대체
            waypointCard = nil
        }
    }
```

(d) `endRun()` 첫머리에 카드 정리 추가:

```swift
        waypointCardDismissTask?.cancel()
        waypointCard = nil
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunPageViewModelTests test`
Expected: PASS

- [ ] **Step 5: 트래킹 패널 UI**

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`의 `RunStatsPanel` 수정.

(a) `body`의 버튼 행을 교체:

```swift
            HStack(spacing: 12) {
                pauseResumeButton
                waypointButton
                endButton
            }
```

(b) `body`의 약신호 표시 아래(첫 `HStack(spacing: 24)` 위)에 카드 추가:

```swift
            if let card = viewModel.waypointCard {
                Text("포인트 \(card.index) · \(String(format: "%.2f", card.segmentMeters / 1000)) km")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.accent)
                    .transition(.opacity)
                    .accessibilityIdentifier("run.waypointCard")
            }
```

(c) `pauseResumeButton` 아래에 버튼 추가:

```swift
    private var waypointButton: some View {
        Button { viewModel.markWaypointTapped() } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 52, height: 52)
                .background(DesignToken.Color.accent, in: Circle())
        }
        // 일시정지 중(거리가 안 쌓임) 비활성 + dimmed로 상태를 보이게(스펙 §2.2)
        .disabled(viewModel.session.canMarkWaypoint == false)
        .opacity(viewModel.session.canMarkWaypoint ? 1 : 0.4)
        .accessibilityIdentifier("run.waypointButton")
    }
```

- [ ] **Step 6: 빌드 확인 + 커밋**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
Expected: BUILD SUCCEEDED

```bash
git add Trace/Pages/RunPage/RunPageViewModel.swift Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift TraceTests/RunPageViewModelTests.swift
git commit -m "feat: 트래킹 화면 포인트 버튼 + 자동 소멸 확인 카드"
```

---

### Task 5: 잠금화면 Live Activity 포인트 버튼 (LiveActivityIntent + 무세션 가드)

**Files:**
- Create: `Trace/App/MarkRunWaypointIntent.swift` (앱 + 위젯 양쪽 타깃)
- Create: `Trace/Application/RunTracking/RunWaypointIntentAction.swift`
- Modify: `Trace/Domain/RunTracking/RunActivityAttributes.swift`
- Modify: `Trace/Application/RunTracking/RunActivityController.swift`
- Modify: `Trace/App/TraceApp.swift`
- Modify: `TraceWidgets/RunLiveActivityWidget.swift`
- Modify: `Trace.xcodeproj/project.pbxproj` (위젯 타깃 membershipExceptions)
- Test: `TraceTests/RunWaypointIntentActionTests.swift` (신규)

**Interfaces:**
- Consumes: Task 1의 `session.markWaypoint()`/`isActive`/`waypoints`
- Produces:
  - `RunActivityAttributes.ContentState.LastWaypoint { index: Int; segmentMeters: Double }` + `lastWaypoint: LastWaypoint?`
  - `struct MarkRunWaypointIntent: LiveActivityIntent`
  - `@MainActor enum MarkRunWaypointIntentBridge { static var handler: (@MainActor () async -> Void)?; static func performMark() async }`
  - `@MainActor struct RunWaypointIntentAction { let session: RunSession; let endOrphanedActivities: @MainActor () -> Void; func perform() }`
  - `RunActivityController.endOrphanedActivities()` — private 해제(internal)

- [ ] **Step 1: 실패하는 테스트 작성 — 무세션 가드**

`TraceTests/RunWaypointIntentActionTests.swift` 생성:

```swift
import XCTest
@testable import Trace

@MainActor
final class RunWaypointIntentActionTests: XCTestCase {
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)

    private func sample(at date: Date) -> RunSample {
        RunSample(
            timestamp: date, latitude: 37.5666, longitude: 126.9784,
            altitudeMeters: 10, speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5, verticalAccuracyMeters: 5
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            if Date() >= deadline {
                XCTFail("timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func test_활성세션이_없으면_noop_처리하고_잔여_LiveActivity를_정리한다() {
        // "러닝 중 강제종료 → 잠금화면에 남은 카드의 버튼 탭" 시나리오(스펙 §2.3 무세션 가드)
        var cleanedUp = false
        let action = RunWaypointIntentAction(
            session: session,
            endOrphanedActivities: { cleanedUp = true }
        )
        action.perform()
        XCTAssertTrue(cleanedUp)
        XCTAssertTrue(session.waypoints.isEmpty)
    }

    func test_활성세션이_있으면_포인트를_찍고_정리하지_않는다() async {
        var cleanedUp = false
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.state == .tracking }

        let action = RunWaypointIntentAction(
            session: session,
            endOrphanedActivities: { cleanedUp = true }
        )
        action.perform()
        XCTAssertFalse(cleanedUp)
        XCTAssertEqual(session.waypoints.count, 1)
    }

    func test_일시정지중에는_포인트가_찍히지않고_정리도_하지않는다() async {
        // 일시정지 = 활성 세션 존재 — 무세션 가드 대상 아님, markWaypoint 가드가 거른다(스펙 §2.3)
        var cleanedUp = false
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.state == .tracking }
        session.pause()

        let action = RunWaypointIntentAction(
            session: session,
            endOrphanedActivities: { cleanedUp = true }
        )
        action.perform()
        XCTAssertFalse(cleanedUp)
        XCTAssertTrue(session.waypoints.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunWaypointIntentActionTests test`
Expected: **컴파일 실패** — `RunWaypointIntentAction` 미정의

- [ ] **Step 3: 인텐트 액션 구현**

`Trace/Application/RunTracking/RunWaypointIntentAction.swift` 생성:

```swift
import Foundation

/// 잠금화면 포인트 버튼 인텐트의 실제 동작(스펙 §2.3) — 세션 연산과 입력 채널을 분리해
/// 미래 워치 버튼도 같은 지점에 연결되게 한다(스펙 §2.1). ActivityKit 정리는 클로저로
/// 주입해 무세션 가드를 단위 테스트할 수 있게 한다.
@MainActor
struct RunWaypointIntentAction {
    let session: RunSession
    /// 활성 세션이 없는데 잠금화면 카드가 남은 경우(러닝 중 강제종료 등) 잔여 Activity 정리
    let endOrphanedActivities: @MainActor () -> Void

    func perform() {
        guard session.isActive else {
            endOrphanedActivities() // 무세션 가드: no-op + 잔여 카드 정리(스펙 §2.3)
            return
        }
        // 일시정지·샘플 미확보는 markWaypoint 내부 가드가 거른다(앱 내 버튼과 동일 규칙)
        session.markWaypoint()
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunWaypointIntentActionTests test`
Expected: PASS (3개)

- [ ] **Step 5: 인텐트 + 브리지 (양쪽 타깃 파일)**

`Trace/App/MarkRunWaypointIntent.swift` 생성:

```swift
import AppIntents

/// 잠금화면 Live Activity 버튼 인텐트(스펙 §2.3) — LiveActivityIntent는 앱 프로세스에서
/// 실행되므로(필요 시 백그라운드 런치) 살아 있는 RunSession에 직접 연결된다(IPC 불필요).
/// perform은 앱 시작 시 등록되는 핸들러에 위임한다 — 이 파일은 위젯 타깃에도 컴파일되지만
/// (Button(intent:)가 타입을 알아야 함) 핸들러는 앱 프로세스에서만 등록된다.
struct MarkRunWaypointIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "포인트 찍기"
    /// 잠금화면 버튼 전용 — Shortcuts 앱 노출 불필요
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await MarkRunWaypointIntentBridge.performMark()
        return .result()
    }
}

/// 인텐트 → 앱 세션 연결 지점. TraceApp.init(인텐트로 인한 백그라운드 콜드 런치에서도
/// perform 전에 실행됨)에서 핸들러가 등록된다.
@MainActor
enum MarkRunWaypointIntentBridge {
    static var handler: (@MainActor () async -> Void)?

    static func performMark() async {
        await handler?()
    }
}
```

- [ ] **Step 6: pbxproj — 인텐트 파일을 위젯 타깃에도 포함**

`Trace.xcodeproj/project.pbxproj`에서 아래 편집 (RunActivityAttributes.swift와 같은 예외 목록):

old_string:
```
			membershipExceptions = (
				Domain/RunTracking/RunActivityAttributes.swift,
			);
```
new_string:
```
			membershipExceptions = (
				App/MarkRunWaypointIntent.swift,
				Domain/RunTracking/RunActivityAttributes.swift,
			);
```

- [ ] **Step 7: ContentState 확장 + 컨트롤러 매핑**

(a) `Trace/Domain/RunTracking/RunActivityAttributes.swift`의 `ContentState`에 추가:

```swift
        /// 마지막 포인트 표시용(스펙 §2.3) — 발화를 놓쳐도 눈으로 확인 가능하게.
        /// 첫 포인트 전에는 nil(줄 자체를 숨김)
        struct LastWaypoint: Codable, Hashable {
            var index: Int
            var segmentMeters: Double
        }

        var lastWaypoint: LastWaypoint?
```

(b) `Trace/Application/RunTracking/RunActivityController.swift`:
- `observeOnce()` 관찰 블록에 `_ = session.waypoints.count` 추가.
- `endOrphanedActivities()`의 `private` 제거(인텐트 등록부가 재사용):

```swift
    /// 강제 종료 후 재실행 시 세션은 항상 .idle로 새로 시작하고 이전 세션을 복구하지 않으므로
    /// (스펙 범위 밖), 실행 시점에 남아 있는 Activity는 예외 없이 고아다 — 즉시 정리한다(중요 리뷰 항목).
    /// 잠금화면 인텐트의 무세션 가드(MarkRunWaypointIntentBridge 등록부)도 이 정리를 재사용한다.
    func endOrphanedActivities() {
```
- `currentState()`에 매핑 추가:

```swift
    private func currentState() -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            distanceMeters: session.track.totalDistanceMeters,
            paceSecondsPerKm: session.track.currentPaceSecondsPerKm,
            isPaused: session.isPaused,
            timerStart: session.displayTimerStart ?? session.startedAt ?? Date(),
            elapsedSecondsAtPause: session.isPaused ? session.activeElapsedSeconds() : nil,
            lastWaypoint: session.waypoints.lastSegmentMeters.map {
                .init(index: session.waypoints.count, segmentMeters: $0)
            }
        )
    }
```

- [ ] **Step 8: 핸들러 등록**

`Trace/App/TraceApp.swift`의 `init()` — `container.runAudioCoach.startObserving()` 아래에 추가:

```swift
        let session = container.runSession
        let activityController = container.runActivityController
        MarkRunWaypointIntentBridge.handler = {
            RunWaypointIntentAction(
                session: session,
                endOrphanedActivities: { activityController.endOrphanedActivities() }
            ).perform()
        }
```

- [ ] **Step 9: 위젯 UI — 포인트 줄 + 버튼 행**

`TraceWidgets/RunLiveActivityWidget.swift`의 `lockScreenView(context:)`를 교체 — 기존 지표 행은 유지하고, 별도 행으로 포인트 영역 추가(최소 탭 영역 확보 — 스펙 §2.3):

```swift
    private func lockScreenView(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                    .font(.title2)
                metric(distanceText(context), label: "거리")
                timeView(context, fontSize: 20)
                metric(paceText(context), label: "페이스")
            }
            HStack {
                if let waypoint = context.state.lastWaypoint {
                    // 첫 포인트 전에는 줄 자체를 표시하지 않는다(스펙 §2.3)
                    Text(String(format: "P%d · %.2f km", waypoint.index, waypoint.segmentMeters / 1000))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: MarkRunWaypointIntent()) {
                    Label("포인트", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                // 일시정지 중엔 잠금화면 버튼도 비활성 — 앱 내 버튼과 동일 규칙(스펙 §2.3).
                // Activity 존재 = tracking/paused = 샘플 확보 후이므로 isPaused만 보면 된다.
                .disabled(context.state.isPaused)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.6))
    }
```

(Dynamic Island는 변경 없음 — 스펙 §2.3은 "Live Activity 본문"만 요구. YAGNI.)

- [ ] **Step 10: 전체 빌드 + 전체 테스트**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
Expected: BUILD SUCCEEDED (위젯 익스텐션 포함)

Run: `xcodebuild ... -parallel-testing-enabled NO test` (전체 스위트 — ContentState 필드 추가가 컨트롤러 관련 기존 테스트를 깨지 않는지 확인)
Expected: 전체 PASS

- [ ] **Step 11: 커밋**

```bash
git add Trace/App/MarkRunWaypointIntent.swift Trace/Application/RunTracking/RunWaypointIntentAction.swift Trace/Domain/RunTracking/RunActivityAttributes.swift Trace/Application/RunTracking/RunActivityController.swift Trace/App/TraceApp.swift TraceWidgets/RunLiveActivityWidget.swift Trace.xcodeproj/project.pbxproj TraceTests/RunWaypointIntentActionTests.swift
git commit -m "feat: 잠금화면 포인트 버튼 - LiveActivityIntent + 무세션 가드 + 마지막 포인트 줄"
```

---

### Task 6: 기록 상세 — 포인트 구간 표 + 지도 번호 마커

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunWaypointSegment.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`
- Test: `TraceTests/RunWaypointSegmentsCalculatorTests.swift` (신규)

**Interfaces:**
- Consumes: Task 3의 `SavedRun.waypoints`
- Produces:
  - `struct RunWaypointSegment: Equatable, Sendable { let index: Int; let distanceMeters: Double; let endsAtFinish: Bool }`
  - `RunWaypointSegmentsCalculator.segments(waypoints: [RunWaypoint], totalDistanceMeters: Double) -> [RunWaypointSegment]`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunWaypointSegmentsCalculatorTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class RunWaypointSegmentsCalculatorTests: XCTestCase {
    private func waypoint(cumulativeMeters: Double) -> RunWaypoint {
        RunWaypoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + cumulativeMeters),
            latitude: 37.5, longitude: 127.0, totalDistanceMeters: cumulativeMeters
        )
    }

    func test_포인트가_없으면_빈_목록() {
        XCTAssertEqual(
            RunWaypointSegmentsCalculator.segments(waypoints: [], totalDistanceMeters: 5000),
            []
        )
    }

    func test_포인트_1개는_구간_2개다() {
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: [waypoint(cumulativeMeters: 1240)], totalDistanceMeters: 2000
        )
        XCTAssertEqual(segments, [
            RunWaypointSegment(index: 1, distanceMeters: 1240, endsAtFinish: false),
            RunWaypointSegment(index: 2, distanceMeters: 760, endsAtFinish: true)
        ])
    }

    func test_포인트_n개의_구간_합계는_총거리와_일치한다() {
        // 스펙 §2.5: 마지막 포인트~종료 구간까지 넣어 합계 = 총거리(telescoping)
        let waypoints = [
            waypoint(cumulativeMeters: 1240),
            waypoint(cumulativeMeters: 2110),
            waypoint(cumulativeMeters: 4580)
        ]
        let total = 5000.0
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: waypoints, totalDistanceMeters: total
        )
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.map(\.distanceMeters).reduce(0, +), total, accuracy: 1e-9)
        XCTAssertEqual(segments.last?.endsAtFinish, true)
        XCTAssertEqual(segments.map(\.index), [1, 2, 3, 4])
    }

    func test_연타로_같은_지점에_찍힌_0m_구간도_행으로_유지된다() {
        // 연타 방지 임계값 없음 — 0.00 km 구간 허용(스펙 §2.2)
        let segments = RunWaypointSegmentsCalculator.segments(
            waypoints: [waypoint(cumulativeMeters: 500), waypoint(cumulativeMeters: 500)],
            totalDistanceMeters: 1000
        )
        XCTAssertEqual(segments.map(\.distanceMeters), [500, 0, 500])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunWaypointSegmentsCalculatorTests test`
Expected: **컴파일 실패** — `RunWaypointSegmentsCalculator` 미정의

- [ ] **Step 3: 계산기 구현**

`Trace/Domain/RunTracking/Entity/RunWaypointSegment.swift` 생성:

```swift
import Foundation

/// 기록 상세 포인트 구간 표의 한 행(스펙 §2.5) — "시작→① 1.24 km / ①→② 0.87 km / ③→종료 0.42 km"
struct RunWaypointSegment: Equatable, Sendable {
    /// 1부터 시작하는 구간 번호 — n번 구간 = (n−1)번 포인트(0이면 시작)→n번 포인트(또는 종료)
    let index: Int
    let distanceMeters: Double
    /// 마지막 구간(마지막 포인트→종료) 여부 — 라벨 표기용
    let endsAtFinish: Bool
}

/// 포인트 누적 거리의 차분으로 구간 목록 파생 — 합계는 항상 totalDistanceMeters와
/// 일치한다(telescoping, 스펙 §2.5). 포인트 삭제 후에도 같은 함수로 재계산하면 된다.
enum RunWaypointSegmentsCalculator {
    static func segments(
        waypoints: [RunWaypoint], totalDistanceMeters: Double
    ) -> [RunWaypointSegment] {
        guard waypoints.isEmpty == false else { return [] }
        var result: [RunWaypointSegment] = []
        var previousCumulative: Double = 0
        for (offset, waypoint) in waypoints.enumerated() {
            result.append(RunWaypointSegment(
                index: offset + 1,
                distanceMeters: waypoint.totalDistanceMeters - previousCumulative,
                endsAtFinish: false
            ))
            previousCumulative = waypoint.totalDistanceMeters
        }
        result.append(RunWaypointSegment(
            index: waypoints.count + 1,
            distanceMeters: totalDistanceMeters - previousCumulative,
            endsAtFinish: true
        ))
        return result
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/RunWaypointSegmentsCalculatorTests test`
Expected: PASS (4개)

- [ ] **Step 5: 기록 상세 UI — 마커 + 구간 표**

`Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` 수정.

(a) `RunRecordDetailView.detailMap`의 `Map` 빌더에 번호 마커 추가:

```swift
            Map(initialPosition: RunRecordDetailView.fittedPosition(for: coordinates)) {
                MapPolyline(coordinates: coordinates)
                    .stroke(DesignToken.Color.accent, lineWidth: 5)
                ForEach(Array(loadedRun.waypoints.enumerated()), id: \.offset) { index, waypoint in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: waypoint.latitude, longitude: waypoint.longitude
                    )) {
                        WaypointMarkerBadge(number: index + 1)
                    }
                }
            }
```

(b) `RunRecordDetailView.body`의 `RunSplitsSection` 아래에 섹션 추가:

```swift
                if let loadedRun, loadedRun.waypoints.isEmpty == false {
                    RunWaypointsSection(
                        run: loadedRun,
                        segments: RunWaypointSegmentsCalculator.segments(
                            waypoints: loadedRun.waypoints,
                            totalDistanceMeters: loadedRun.summary.distanceMeters
                        )
                    )
                }
```

(c) 파일 끝에 마커 배지·섹션 뷰 추가:

```swift
/// 지도 궤적 위 포인트 번호 마커(스펙 §2.5)
struct WaypointMarkerBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(DesignToken.Color.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// 포인트 구간 표(스펙 §2.5) — km 스플릿 표와 별도 섹션, 포인트 없는 기록은 섹션 자체가 숨는다
private struct RunWaypointsSection: View {
    let run: SavedRun
    let segments: [RunWaypointSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("포인트 구간")
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
            ForEach(segments, id: \.index) { segment in
                HStack {
                    Text(Self.label(for: segment))
                        .font(DesignToken.Typography.segmentRowTitle)
                        .foregroundStyle(DesignToken.Color.ink)
                    Spacer()
                    Text(String(format: "%.2f km", segment.distanceMeters / 1000))
                        .font(DesignToken.Typography.segmentRowDistance)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                }
            }
        }
        .padding(.horizontal, DesignToken.Size.sheetPadding)
        .padding(.bottom, DesignToken.Size.sheetPadding)
    }

    /// "시작 → ①" / "① → ②" / "③ → 종료"
    static func label(for segment: RunWaypointSegment) -> String {
        let from = segment.index == 1 ? "시작" : circled(segment.index - 1)
        let to = segment.endsAtFinish ? "종료" : circled(segment.index)
        return "\(from) → \(to)"
    }

    /// 1 → "①" … 20 → "⑳" (유니코드 원문자 범위 밖이면 일반 숫자)
    static func circled(_ number: Int) -> String {
        guard (1...20).contains(number),
              let scalar = Unicode.Scalar(0x2460 + number - 1) else { return "\(number)" }
        return String(Character(scalar))
    }
}
```

- [ ] **Step 6: 빌드 확인 + 커밋**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
Expected: BUILD SUCCEEDED

```bash
git add Trace/Domain/RunTracking/Entity/RunWaypointSegment.swift Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift TraceTests/RunWaypointSegmentsCalculatorTests.swift
git commit -m "feat: 기록 상세 포인트 구간 표 + 지도 번호 마커"
```

---

### Task 7: 포인트 개별 삭제

**Files:**
- Modify: `Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift`
- Modify: `Trace/Pages/RunPage/RunHistoryViewModel.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`
- Modify: `TraceTests/MockRunRecordRepository.swift`
- Test: `TraceTests/SwiftDataRunRecordRepositoryTests.swift`, `TraceTests/RunHistoryViewModelTests.swift`

**Interfaces:**
- Consumes: Task 3의 v4 스키마, Task 6의 `RunWaypointSegmentsCalculator`
- Produces:
  - `RunRecordRepositoryProtocol.updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws`
  - `RunHistoryViewModel.deleteWaypoint(from run: SavedRun, at index: Int) async -> SavedRun?`
  - `RunHistoryViewModel.showsWaypointDeleteFailure: Bool`

- [ ] **Step 1: 실패하는 테스트 작성 — 리포지토리**

`TraceTests/SwiftDataRunRecordRepositoryTests.swift` 클래스 끝에 추가 (Task 3의 `waypointRun` 헬퍼 재사용):

```swift
    func test_포인트를_교체하면_재조회에_반영된다() async throws {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        let original = [
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        latitude: 37.505, longitude: 127.0, totalDistanceMeters: 870),
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_400),
                        latitude: 37.508, longitude: 127.0, totalDistanceMeters: 1500)
        ]
        let run = waypointRun(waypoints: original)
        try await repository.save(run)

        // 첫 포인트 삭제 반영
        try await repository.updateWaypoints(runID: run.summary.id, waypoints: [original[1]])

        let loaded = await repository.fetchRun(id: run.summary.id)
        XCTAssertEqual(loaded?.waypoints, [original[1]])
        // 샘플·요약 등 나머지는 불변
        XCTAssertEqual(loaded?.samples, run.samples)
        XCTAssertEqual(loaded?.summary.distanceMeters ?? 0, 2000, accuracy: 0.001)
    }

    func test_없는_기록의_포인트_교체는_에러다() async {
        let repository = SwiftDataRunRecordRepository(inMemory: true)
        do {
            try await repository.updateWaypoints(runID: UUID(), waypoints: [])
            XCTFail("expected error")
        } catch {} // ok
    }
```

- [ ] **Step 2: 실패하는 테스트 작성 — ViewModel**

`TraceTests/RunHistoryViewModelTests.swift` 클래스 끝에 추가 (이 파일의 기존 필드 `repository`(MockRunRecordRepository)·`viewModel` 재사용 — 이름 확인 완료):

```swift
    // MARK: - 포인트 개별 삭제 (스펙 §2.5)

    private func runWithWaypoints(_ waypoints: [RunWaypoint]) -> SavedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: start, distanceMeters: 2000,
                duration: 600, elevationGainMeters: 0
            ),
            samples: [
                SavedRunSample(timestamp: start, latitude: 37.5, longitude: 127.0,
                               altitudeMeters: 10, speedMetersPerSecond: 3)
            ],
            waypoints: waypoints
        )
    }

    func test_포인트를_삭제하면_갱신된_기록을_돌려준다() async throws {
        let waypoints = [
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                        latitude: 37.505, longitude: 127.0, totalDistanceMeters: 870),
            RunWaypoint(timestamp: Date(timeIntervalSince1970: 1_700_000_400),
                        latitude: 37.508, longitude: 127.0, totalDistanceMeters: 1500)
        ]
        let run = runWithWaypoints(waypoints)
        try await repository.save(run)

        let updated = await viewModel.deleteWaypoint(from: run, at: 0)

        XCTAssertEqual(updated?.waypoints, [waypoints[1]])
        XCTAssertFalse(viewModel.showsWaypointDeleteFailure)
    }

    func test_저장소_실패시_실패_플래그가_켜진다() async {
        // 저장된 적 없는 기록 → updateWaypoints가 throw
        let run = runWithWaypoints([
            RunWaypoint(timestamp: Date(), latitude: 37.5, longitude: 127.0, totalDistanceMeters: 500)
        ])
        let updated = await viewModel.deleteWaypoint(from: run, at: 0)
        XCTAssertNil(updated)
        XCTAssertTrue(viewModel.showsWaypointDeleteFailure)
    }
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests -only-testing:TraceTests/RunHistoryViewModelTests test`
Expected: **컴파일 실패** — `updateWaypoints`/`deleteWaypoint` 미정의

- [ ] **Step 4: 프로토콜 + 어댑터 + 목 구현**

(a) `Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift`에 요구사항 추가:

```swift
    /// 포인트 개별 삭제 반영(MVP15 §2.5) — 해당 기록의 포인트 스트림만 교체해 재저장한다.
    /// 캐시 컬럼(거리·시간·고도)은 포인트와 무관하므로 불변. 기록 미존재·해독 실패 시 throw
    func updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws
```

(b) `Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift` — `RepositoryError`에 케이스 추가:

```swift
    enum RepositoryError: Error {
        case storeUnavailable
        case recordUnavailable
    }
```

`deleteRun(id:)` 아래에 구현 추가:

```swift
    func updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == runID }
        )
        guard let record = try context.fetch(descriptor).first,
              let payload = Self.decodeRunPayload(record.payload)
        else { throw RepositoryError.recordUnavailable }
        // 샘플·일시정지·목표는 그대로, 포인트만 교체해 재직렬화(버전은 현재로 승격)
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: payload.samples.map(RunPersistenceDTO.Sample.init),
            pauses: payload.pauses.map(RunPersistenceDTO.Pause.init),
            goal: RunPersistenceDTO.Goal(payload.goal),
            waypoints: waypoints.map(RunPersistenceDTO.Waypoint.init)
        )
        record.payload = try JSONEncoder().encode(dto)
        try context.save()
    }
```

(c) `TraceTests/MockRunRecordRepository.swift`에 구현 추가:

```swift
    func updateWaypoints(runID: UUID, waypoints: [RunWaypoint]) async throws {
        guard let index = savedRuns.firstIndex(where: { $0.summary.id == runID }) else {
            throw MockError.saveFailed
        }
        let run = savedRuns[index]
        savedRuns[index] = SavedRun(
            summary: run.summary, samples: run.samples,
            pauses: run.pauses, goal: run.goal, waypoints: waypoints
        )
    }
```

- [ ] **Step 5: ViewModel 구현**

`Trace/Pages/RunPage/RunHistoryViewModel.swift` 수정.

(a) 프로퍼티 추가 (`showsDeleteFailure` 아래):

```swift
    var showsWaypointDeleteFailure = false
```

(b) 메서드 추가 (`confirmPendingDelete()` 아래):

```swift
    /// 포인트 개별 삭제(스펙 §2.5) — 성공 시 스토어에서 다시 읽은 기록을 돌려준다(재계산은 뷰가
    /// RunWaypointSegmentsCalculator로 수행). 실패 시 nil + 알럿 플래그
    func deleteWaypoint(from run: SavedRun, at index: Int) async -> SavedRun? {
        var waypoints = run.waypoints
        guard waypoints.indices.contains(index) else { return nil }
        waypoints.remove(at: index)
        do {
            try await repository.updateWaypoints(runID: run.summary.id, waypoints: waypoints)
        } catch {
            showsWaypointDeleteFailure = true
            return nil
        }
        return await repository.fetchRun(id: run.summary.id)
    }
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `xcodebuild ... -only-testing:TraceTests/SwiftDataRunRecordRepositoryTests -only-testing:TraceTests/RunHistoryViewModelTests test`
Expected: PASS

- [ ] **Step 7: 상세 화면 삭제 UI**

`Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` 수정.

(a) `RunWaypointsSection`에 삭제 연결 추가 — 뷰를 다음으로 교체 (끝점이 포인트인 행(비-final)에만 삭제 버튼: 그 행의 끝 포인트를 지우면 다음 구간과 병합된다):

```swift
/// 포인트 구간 표(스펙 §2.5) — km 스플릿 표와 별도 섹션, 포인트 없는 기록은 섹션 자체가 숨는다.
/// 비-final 행의 삭제 버튼 = 그 행의 끝 포인트 삭제(다음 구간과 병합) — 오탭 복구 경로
private struct RunWaypointsSection: View {
    let run: SavedRun
    let segments: [RunWaypointSegment]
    let onDeleteWaypoint: (Int) -> Void // 인자: 삭제할 포인트의 0-기반 인덱스

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("포인트 구간")
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
            ForEach(segments, id: \.index) { segment in
                HStack {
                    Text(Self.label(for: segment))
                        .font(DesignToken.Typography.segmentRowTitle)
                        .foregroundStyle(DesignToken.Color.ink)
                    Spacer()
                    Text(String(format: "%.2f km", segment.distanceMeters / 1000))
                        .font(DesignToken.Typography.segmentRowDistance)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                    if segment.endsAtFinish == false {
                        Button {
                            onDeleteWaypoint(segment.index - 1) // 행의 끝 포인트(1-기반 → 0-기반)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DesignToken.Color.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run.deleteWaypoint.\(segment.index)")
                    } else {
                        // final 행은 버튼 없이 폭만 맞춘다(정렬 유지)
                        Image(systemName: "xmark.circle.fill").opacity(0)
                    }
                }
            }
        }
        .padding(.horizontal, DesignToken.Size.sheetPadding)
        .padding(.bottom, DesignToken.Size.sheetPadding)
    }

    /// "시작 → ①" / "① → ②" / "③ → 종료"
    static func label(for segment: RunWaypointSegment) -> String {
        let from = segment.index == 1 ? "시작" : circled(segment.index - 1)
        let to = segment.endsAtFinish ? "종료" : circled(segment.index)
        return "\(from) → \(to)"
    }

    /// 1 → "①" … 20 → "⑳" (유니코드 원문자 범위 밖이면 일반 숫자)
    static func circled(_ number: Int) -> String {
        guard (1...20).contains(number),
              let scalar = Unicode.Scalar(0x2460 + number - 1) else { return "\(number)" }
        return String(Character(scalar))
    }
}
```

(b) `RunRecordDetailView`에 상태 추가:

```swift
    @State private var pendingWaypointDeleteIndex: Int?
```

(c) Task 6에서 넣은 섹션 호출을 교체:

```swift
                if let loadedRun, loadedRun.waypoints.isEmpty == false {
                    RunWaypointsSection(
                        run: loadedRun,
                        segments: RunWaypointSegmentsCalculator.segments(
                            waypoints: loadedRun.waypoints,
                            totalDistanceMeters: loadedRun.summary.distanceMeters
                        ),
                        onDeleteWaypoint: { pendingWaypointDeleteIndex = $0 }
                    )
                }
```

(d) `RunRecordDetailView.body`의 `.task { ... }` 아래에 알럿 2개 추가:

```swift
        .alert(
            "포인트 \((pendingWaypointDeleteIndex ?? 0) + 1)을(를) 삭제할까요?",
            isPresented: Binding(
                get: { pendingWaypointDeleteIndex != nil },
                set: { if $0 == false { pendingWaypointDeleteIndex = nil } }
            )
        ) {
            Button("삭제", role: .destructive) {
                guard let index = pendingWaypointDeleteIndex, let run = loadedRun else { return }
                pendingWaypointDeleteIndex = nil
                Task {
                    if let updated = await viewModel.deleteWaypoint(from: run, at: index) {
                        loadedRun = updated // 구간 표·마커 재계산은 body가 파생(스펙 §2.5)
                    }
                }
            }
            Button("취소", role: .cancel) { pendingWaypointDeleteIndex = nil }
        } message: {
            Text("구간 거리는 앞뒤 구간에 합쳐집니다")
        }
        .alert("포인트를 삭제하지 못했어요", isPresented: Bindable(viewModel).showsWaypointDeleteFailure) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요")
        }
```

- [ ] **Step 8: 전체 테스트 + 커밋**

Run: `xcodebuild ... -parallel-testing-enabled NO test` (전체 스위트)
Expected: 전체 PASS

```bash
git add Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift Trace/Pages/RunPage/RunHistoryViewModel.swift Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift TraceTests/MockRunRecordRepository.swift TraceTests/SwiftDataRunRecordRepositoryTests.swift TraceTests/RunHistoryViewModelTests.swift
git commit -m "feat: 기록 상세 포인트 개별 삭제 - 스트림 교체 저장 + 구간 병합 재계산"
```

---

### Task 8: 실기기 QA 체크리스트 문서

**Files:**
- Create: `docs/qa/2026-07-XX-run-waypoints-device-checklist.md` (작성일 날짜로)

시나리오 카드 형식·평이한 언어·세션 단위 묶기(`docs/agent-rules/testing.md` 템플릿, `docs/qa/2026-07-18-run-detail-polish-device-checklist.md` 형식 승계). GPX 시뮬레이션(`docs/qa/trace-qa-5km-straight.gpx`) 활용 + 반복 재생 점프 주의사항 승계.

- [ ] **Step 1: 체크리스트 작성** — 아래 시나리오를 세션으로 묶어 작성:

**세션 1 — 러닝 중 포인트 찍기 (GPX 가능):**
1. 트래킹 중 포인트 버튼 탭 → "포인트 1, X.XX킬로미터" 발화 + 화면 카드 몇 초 표시 후 소멸
2. 두 번째 포인트 → 구간 거리가 "직전 포인트부터"인지 (총거리 아님)
3. 연타 2회 → 둘 다 찍히고 0.00 km 구간 허용(발화 확인)
4. 일시정지 → 포인트 버튼이 흐려지고(dimmed) 눌러도 무반응, 재개 → 복구
5. km 경계 발화가 나오는 중 포인트 탭 → km 낭독이 끊기고 포인트 발화가 바로 나옴
6. 음악 재생 중 포인트 발화 → 덕킹(음악 작아졌다 복원)

**세션 2 — 잠금화면 버튼 (GPX 가능):**
1. 트래킹 → 화면 잠금 → 잠금화면 Live Activity에 포인트 버튼 표시
2. 잠금 해제 없이 버튼 탭 → 발화로 확인, Live Activity에 "P1 · X.XX km" 줄 등장
3. 첫 포인트 전에는 포인트 줄이 안 보였는지 (버튼만)
4. 일시정지 상태에서 잠금화면 버튼이 비활성(흐림)인지
5. 러닝 중 앱 강제종료 → 잠금화면에 남은 카드의 포인트 버튼 탭 → 아무 일 없이 카드가 사라지는지 (무세션 가드)

**세션 3 — 기록 상세 (이동 불필요):**
1. 세션 1~2에서 만든 기록 진입 → 지도에 번호 마커(①②…) + "포인트 구간" 표 표시
2. 구간 표 합계가 상단 총거리와 일치하는지
3. 포인트 하나 삭제 → 확인 알럿 → 행이 줄고 앞뒤 구간이 합쳐지는지, 지도 마커 번호 재배열
4. 포인트 없는 과거 기록(MVP14 이전) 진입 → 포인트 섹션이 아예 없음 + 나머지 정상 (호환)
5. 앱 재시작 후 같은 기록 재진입 → 삭제가 유지되는지 (저장 확인)

- [ ] **Step 2: 커밋**

```bash
git add docs/qa/<파일명>
git commit -m "docs: run-waypoints 실기기 QA 체크리스트 추가"
```

---

## 마무리 (표준 사이클)

- 전체 테스트 스위트 그린 확인 (`-parallel-testing-enabled NO`, 전체).
- **최종 브랜치 리뷰(opus)** — 표준 사이클 결정(스펙 §0 사이클 정책).
- 실기기 QA(Task 8 체크리스트) → 통과 시 roadmap.md 체크박스·project-decisions.md(신규 결정 발생 시)·backlog(이월 항목) 갱신은 사이클 마무리 세션에서.
