# MVP13 사이클 1 — run-tracking + run-live-activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **완료(소급 확인):** Task 1~10 + 최종 브랜치 리뷰(opus) + 후속 수정 전부 완료, 2026-07-14.
> 브랜치 `feature/run-tracking`, 최종 커밋 `0ce36cf`(fix wave `7440796`까지). 실기기 QA
> (`docs/qa/2026-07-14-run-tracking-device-checklist.md`) 통과. 진행 중 체크박스가 갱신되지
> 않은 채 남아 있던 것으로, 실제 구현 완료 여부와는 무관하다 — 상세 근거는 SDD 진행 로그와
> roadmap의 MVP13 항목 참고.

**Goal:** 코스 없이 그냥 뛰어도 되는 자유 러닝 트래킹(시작→백그라운드 GPS→종료 요약)과 잠금화면 Live Activity를 러닝 탭으로 추가한다. 저장 없음(DEBUG 덤프만).

**Architecture:** 스펙 `docs/superpowers/specs/2026-07-13-run-tracking-design.md` 기준. Domain(`RunSample`/`RunTrack`/포트) → Infrastructure(`RunLocationTracker`, @MainActor CLLocationManager delegate→AsyncStream 브리지) → Application(`RunSession` @Observable, DependencyContainer 소유) → Pages(`RunPage`, SwiftUI Map). Live Activity는 Widget Extension 타깃 + 앱 쪽 `RunActivityController`가 세션을 구독해 갱신.

**Tech Stack:** Swift 6(클래식 격리: 기본 nonisolated + UI/상태 타입만 명시 `@MainActor`), SwiftUI, CoreLocation, ActivityKit/WidgetKit, XCTest.

## Global Constraints

- 브랜치: `feature/run-tracking` (이미 생성됨, 스펙 커밋 `7e9a6ef` 이후 이어서 작업)
- 최소 iOS 17.0, `SWIFT_VERSION = 6.0` (신규 타깃 포함)
- 시뮬레이터: **iOS 26.5 고정** — 세션 시작 시 `docs/agent-rules/testing.md`의 "기준 시뮬레이터 선택 절차"로 `$SIM_UDID` 1회 확정, 실패해도 다른 시뮬레이터로 전환 금지
- 테스트 명령(항상 이 형태, XcodeBuildMCP 테스트 툴 금지):
  `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test`
- 빌드만: 같은 명령에서 `-parallel-testing-enabled NO test` → `build`
- 린트: `swiftlint` (강제 언래핑/캐스트/try는 에러)
- 커밋: `tag: 한국어 제목` + 한국어 본문, Co-Authored-By 금지, `git add`는 경로 명시(`-A`/`.` 금지), push 금지
- 새 소스 파일은 pbxproj 등록 불요(파일시스템 동기화 그룹) — 단 `Trace/` 아래는 앱 타깃, `TraceTests/` 아래는 테스트 타깃으로만 동기화됨
- 페이스 단위 표기: 초/km를 `5'32"` 형태로 포맷
- 상수 기본값(전부 구현 중 튜닝 가능, 스펙 명시): 수평 정확도 필터 30m, 약신호 타임아웃 10초, 현재 페이스 윈도 30초, 고도 임계 3m, 지도 폴리라인 스로틀 3초/20m, distanceFilter 5m

---

### Task 1: Domain — RunSample + RunTrack (파생값 계산)

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunSample.swift`
- Create: `Trace/Domain/RunTracking/Entity/RunTrack.swift`
- Test: `TraceTests/RunTrackTests.swift`

**Interfaces:**
- Consumes: `CourseCoordinate`(기존), `CourseCoordinate.distanceMeters(to:)`(기존 `CourseCoordinate+Geo.swift`)
- Produces: `RunSample(timestamp:latitude:longitude:altitudeMeters:speedMetersPerSecond:horizontalAccuracyMeters:verticalAccuracyMeters:)` + `var coordinate: CourseCoordinate`. `RunTrack`: `mutating func append(_:)`, `samples: [RunSample]`, `totalDistanceMeters: Double`, `elevationGainMeters: Double`, `duration: TimeInterval`, `averagePaceSecondsPerKm: Double?`, `currentPaceSecondsPerKm: Double?`

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunTrackTests.swift`:

```swift
import XCTest
@testable import Trace

final class RunTrackTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// 위도 1도 ≈ 111,320m를 이용해 대략 100m 북쪽 이동 샘플을 만든다.
    private func sample(
        at seconds: TimeInterval,
        latOffsetMeters: Double = 0,
        altitude: Double = 10,
        speed: Double = 3,
        vAcc: Double = 5
    ) -> RunSample {
        RunSample(
            timestamp: base.addingTimeInterval(seconds),
            latitude: 37.5666 + latOffsetMeters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: altitude,
            speedMetersPerSecond: speed,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: vAcc
        )
    }

    func test_거리와_시간이_누적된다() {
        var track = RunTrack()
        track.append(sample(at: 0, latOffsetMeters: 0))
        track.append(sample(at: 10, latOffsetMeters: 30))
        track.append(sample(at: 20, latOffsetMeters: 60))
        XCTAssertEqual(track.totalDistanceMeters, 60, accuracy: 1)
        XCTAssertEqual(track.duration, 20, accuracy: 0.001)
    }

    func test_평균페이스는_전체거리와_시간으로_계산된다() {
        var track = RunTrack()
        track.append(sample(at: 0))
        track.append(sample(at: 60, latOffsetMeters: 200))
        // 200m를 60초 → 1km당 300초
        XCTAssertEqual(track.averagePaceSecondsPerKm ?? -1, 300, accuracy: 5)
    }

    func test_샘플이_하나이하면_평균페이스는_nil() {
        var track = RunTrack()
        XCTAssertNil(track.averagePaceSecondsPerKm)
        track.append(sample(at: 0))
        XCTAssertNil(track.averagePaceSecondsPerKm)
    }

    func test_현재페이스는_최근30초_유효속도의_평균이다() {
        var track = RunTrack()
        track.append(sample(at: 0, speed: 10))            // 윈도 밖(마지막 기준 40초 전)
        track.append(sample(at: 20, speed: -1))           // 음수 속도는 무시
        track.append(sample(at: 30, speed: 2))
        track.append(sample(at: 40, speed: 4))
        // 유효 속도 = [2, 4] → 평균 3m/s → 1000/3 ≈ 333초/km
        XCTAssertEqual(track.currentPaceSecondsPerKm ?? -1, 1000.0 / 3.0, accuracy: 1)
    }

    func test_현재페이스는_유효속도가_없으면_nil() {
        var track = RunTrack()
        track.append(sample(at: 0, speed: -1))
        XCTAssertNil(track.currentPaceSecondsPerKm)
    }

    func test_고도노이즈는_임계값미만이라_상승에_포함되지_않는다() {
        var track = RunTrack()
        // ±2m 진동 — 연속 상승 누적이 3m를 못 넘음
        for (i, alt) in [10.0, 12.0, 10.0, 12.0, 10.0].enumerated() {
            track.append(sample(at: Double(i * 10), altitude: alt))
        }
        XCTAssertEqual(track.elevationGainMeters, 0, accuracy: 0.001)
    }

    func test_임계값을_넘는_연속상승은_상승량에_누적된다() {
        var track = RunTrack()
        // 10 → 12 → 14.5: 연속 상승 4.5m ≥ 3m
        for (i, alt) in [10.0, 12.0, 14.5].enumerated() {
            track.append(sample(at: Double(i * 10), altitude: alt))
        }
        XCTAssertEqual(track.elevationGainMeters, 4.5, accuracy: 0.001)
    }

    func test_수직정확도가_나쁜_샘플은_고도계산에서_제외된다() {
        var track = RunTrack()
        track.append(sample(at: 0, altitude: 10))
        track.append(sample(at: 10, altitude: 100, vAcc: -1))   // 무효
        track.append(sample(at: 20, altitude: 100, vAcc: 50))   // 10m 초과
        XCTAssertEqual(track.elevationGainMeters, 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: 컴파일 에러 — `RunSample`/`RunTrack` 미정의

- [ ] **Step 3: 구현**

`Trace/Domain/RunTracking/Entity/RunSample.swift`:

```swift
import Foundation

/// 러닝 트래킹의 원시 단위 — "기록 = 타임스탬프 샘플 스트림" 원칙(스펙 §2).
/// 정확도 두 필드는 필터 판정 전용(전송용)이며 저장 대상이 아니다.
struct RunSample: Equatable, Sendable, Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    /// CLLocation.speed 그대로 — 유효하지 않으면 음수
    let speedMetersPerSecond: Double
    let horizontalAccuracyMeters: Double
    let verticalAccuracyMeters: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }
}
```

`Trace/Domain/RunTracking/Entity/RunTrack.swift`:

```swift
import Foundation

/// 필터를 통과한 샘플의 누적 + 파생값 계산.
/// 연속으로 버려진 공백 구간은 다음 유효 샘플과의 직선 거리로 자동 가산된다(스펙 §2 공백 규칙).
struct RunTrack: Equatable, Sendable {
    static let elevationRiseThresholdMeters: Double = 3
    static let maxValidVerticalAccuracyMeters: Double = 10
    static let currentPaceWindowSeconds: TimeInterval = 30

    private(set) var samples: [RunSample] = []
    private(set) var totalDistanceMeters: Double = 0
    private(set) var elevationGainMeters: Double = 0
    // 고도 상승 임계값 누적 상태(GPS 고도 노이즈 억제 — 스펙 §2)
    private var lastValidAltitudeMeters: Double?
    private var pendingRiseMeters: Double = 0

    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    var averagePaceSecondsPerKm: Double? {
        guard totalDistanceMeters > 0, duration > 0 else { return nil }
        return duration / (totalDistanceMeters / 1000)
    }

    var currentPaceSecondsPerKm: Double? {
        guard let last = samples.last else { return nil }
        let windowStart = last.timestamp.addingTimeInterval(-Self.currentPaceWindowSeconds)
        let validSpeeds = samples
            .filter { $0.timestamp >= windowStart && $0.speedMetersPerSecond > 0 }
            .map(\.speedMetersPerSecond)
        guard validSpeeds.isEmpty == false else { return nil }
        let averageSpeed = validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        return 1000 / averageSpeed
    }

    mutating func append(_ sample: RunSample) {
        if let previous = samples.last {
            totalDistanceMeters += previous.coordinate.distanceMeters(to: sample.coordinate)
        }
        accumulateElevation(from: sample)
        samples.append(sample)
    }

    private mutating func accumulateElevation(from sample: RunSample) {
        guard sample.verticalAccuracyMeters > 0,
              sample.verticalAccuracyMeters <= Self.maxValidVerticalAccuracyMeters
        else { return }
        defer { lastValidAltitudeMeters = sample.altitudeMeters }
        guard let last = lastValidAltitudeMeters else { return }
        let delta = sample.altitudeMeters - last
        if delta > 0 {
            pendingRiseMeters += delta
            if pendingRiseMeters >= Self.elevationRiseThresholdMeters {
                elevationGainMeters += pendingRiseMeters
                pendingRiseMeters = 0
            }
        } else {
            pendingRiseMeters = 0
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 위 test 명령. Expected: `RunTrackTests` 전부 PASS, 기존 178개 테스트 그린 유지

- [ ] **Step 5: Commit**

```bash
git add Trace/Domain/RunTracking/Entity/RunSample.swift Trace/Domain/RunTracking/Entity/RunTrack.swift TraceTests/RunTrackTests.swift
git commit -m "feat: RunSample/RunTrack 도메인 엔티티 추가

러닝 트래킹의 원시 샘플 단위와 파생값 계산(거리·시간·평균/현재 페이스·
고도 상승)을 도메인에 추가. 현재 페이스는 30초 윈도 평균, 고도는 3m
임계값 누적으로 GPS 노이즈를 억제한다(스펙 §2). 단위 테스트 9건 그린."
```

---

### Task 2: Domain 포트 + Application — RunSession

**Files:**
- Create: `Trace/Domain/RunTracking/Protocol/RunLocationStreamProtocol.swift`
- Create: `Trace/Application/RunTracking/RunSession.swift`
- Test: `TraceTests/RunSessionTests.swift`

**Interfaces:**
- Consumes: `RunSample`, `RunTrack` (Task 1)
- Produces:

```swift
enum RunLocationAccuracy: Sendable { case full, reduced }

@MainActor protocol RunLocationStreamProtocol {
    func currentAccuracy() -> RunLocationAccuracy
    func requestSessionFullAccuracy() async -> RunLocationAccuracy
    func startUpdates() -> AsyncStream<RunSample>
    func stopUpdates()
}
```

`RunSession`(@MainActor @Observable): `state: State`(.idle/.acquiring/.tracking/.summary), `track: RunTrack`, `startedAt: Date?`, `isSignalWeak: Bool`, `lastStartFailure: StartFailure?`(.reducedAccuracy/.permissionDenied), `isActive: Bool`, `func start() async`, `func finish()`, `func dismissSummary()`. DEBUG 한정 `dumpEntries: [RunSampleDumpEntry]`(accepted 플래그 포함, Task 6에서 소비).

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunSessionTests.swift`:

```swift
import XCTest
@testable import Trace

@MainActor
final class RunSessionTests: XCTestCase {
    private var stream: MockRunLocationStream!
    private var session: RunSession!

    override func setUp() async throws {
        stream = MockRunLocationStream()
        session = RunSession(locationStream: stream)
    }

    private func sample(
        at date: Date,
        latOffsetMeters: Double = 0,
        hAcc: Double = 5
    ) -> RunSample {
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

    /// AsyncStream 소비 태스크가 yield를 처리할 틈을 준다
    private func drain() async { await Task.yield(); await Task.yield(); await Task.yield() }

    func test_시작하면_신호확보_상태가_된다() async {
        await session.start()
        XCTAssertEqual(session.state, .acquiring)
        XCTAssertTrue(session.isActive)
    }

    func test_정확한위치가_꺼져있고_임시요청도_거부되면_시작하지_않는다() async {
        stream.accuracy = .reduced
        stream.accuracyAfterRequest = .reduced
        await session.start()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastStartFailure, .reducedAccuracy)
    }

    func test_임시_정밀권한_승인시_시작된다() async {
        stream.accuracy = .reduced
        stream.accuracyAfterRequest = .full
        await session.start()
        XCTAssertEqual(session.state, .acquiring)
    }

    func test_시작이전_타임스탬프의_캐시샘플은_버린다() async {
        await session.start()
        stream.yield(sample(at: Date(timeIntervalSinceNow: -60)))
        await drain()
        XCTAssertEqual(session.state, .acquiring)
        XCTAssertTrue(session.track.samples.isEmpty)
    }

    func test_첫_유효샘플에서_트래킹으로_전이된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await drain()
        XCTAssertEqual(session.state, .tracking)
        XCTAssertEqual(session.track.samples.count, 1)
    }

    func test_수평정확도가_나쁜_샘플은_버린다() async {
        await session.start()
        stream.yield(sample(at: Date(), hAcc: 80))
        await drain()
        XCTAssertTrue(session.track.samples.isEmpty)
    }

    func test_마지막_유효샘플후_10초이상_탈락이_이어지면_약신호로_표시한다() async {
        await session.start()
        let now = Date()
        stream.yield(sample(at: now))
        stream.yield(sample(at: now.addingTimeInterval(12), hAcc: 80))
        await drain()
        XCTAssertTrue(session.isSignalWeak)
        // 신호 회복 시 해제
        stream.yield(sample(at: now.addingTimeInterval(13)))
        await drain()
        XCTAssertFalse(session.isSignalWeak)
    }

    func test_종료하면_요약상태가_되고_스트림을_멈춘다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await drain()
        session.finish()
        XCTAssertEqual(session.state, .summary)
        XCTAssertTrue(stream.stopped)
    }

    func test_요약을_닫으면_데이터가_소멸하고_대기로_돌아간다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await drain()
        session.finish()
        session.dismissSummary()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.track.samples.isEmpty)
        XCTAssertNil(session.startedAt)
    }

    func test_러닝중_스트림이_끊기면_수집분으로_요약을_보여준다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await drain()
        stream.finish() // 권한 회수 등
        await drain()
        XCTAssertEqual(session.state, .summary)
        XCTAssertEqual(session.track.samples.count, 1)
    }

    func test_샘플없이_스트림이_끊기면_대기로_돌아가고_권한거부를_알린다() async {
        await session.start()
        stream.finish()
        await drain()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastStartFailure, .permissionDenied)
    }
}

@MainActor
final class MockRunLocationStream: RunLocationStreamProtocol {
    var accuracy: RunLocationAccuracy = .full
    var accuracyAfterRequest: RunLocationAccuracy = .full
    private(set) var stopped = false
    private var continuation: AsyncStream<RunSample>.Continuation?

    func currentAccuracy() -> RunLocationAccuracy { accuracy }
    func requestSessionFullAccuracy() async -> RunLocationAccuracy { accuracyAfterRequest }

    func startUpdates() -> AsyncStream<RunSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunSample.self)
        self.continuation = continuation
        return stream
    }

    func stopUpdates() {
        stopped = true
        continuation?.finish()
        continuation = nil
    }

    func yield(_ sample: RunSample) { continuation?.yield(sample) }
    func finish() { continuation?.finish() }
}
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러(`RunSession` 미정의) 확인

- [ ] **Step 3: 구현**

`Trace/Domain/RunTracking/Protocol/RunLocationStreamProtocol.swift`:

```swift
import Foundation

enum RunLocationAccuracy: Sendable {
    case full
    case reduced
}

/// 연속 위치 스트림 포트 — Domain은 CoreLocation을 모른다.
/// 스트림 종료(finish)는 "더 이상 위치를 받을 수 없음"(권한 회수·서비스 오프)을 뜻한다.
@MainActor
protocol RunLocationStreamProtocol {
    func currentAccuracy() -> RunLocationAccuracy
    /// "정확한 위치" 꺼짐 상태에서 세션 한정 임시 정밀 권한을 요청한다(스펙 §6).
    func requestSessionFullAccuracy() async -> RunLocationAccuracy
    func startUpdates() -> AsyncStream<RunSample>
    func stopUpdates()
}
```

`Trace/Application/RunTracking/RunSession.swift`:

```swift
import Foundation
import Observation

#if DEBUG
/// QA 러닝의 원시 데이터(필터 판정 포함)를 남기기 위한 DEBUG 전용 기록(스펙 §1 덤프).
struct RunSampleDumpEntry: Equatable, Sendable, Codable {
    let sample: RunSample
    let accepted: Bool
}
#endif

/// 러닝 세션 오케스트레이터 — DependencyContainer가 소유해 탭 전환·뷰 소멸에도 유지된다.
/// 화면·잠금화면·(미래)오디오 안내는 전부 이 세션의 소비자다(스펙 §4).
@MainActor
@Observable
final class RunSession {
    enum State: Equatable {
        case idle
        case acquiring
        case tracking
        case summary
    }

    enum StartFailure: Equatable {
        case reducedAccuracy
        case permissionDenied
    }

    static let maxHorizontalAccuracyMeters: Double = 30
    static let weakSignalTimeoutSeconds: TimeInterval = 10

    private(set) var state: State = .idle
    private(set) var track = RunTrack()
    private(set) var startedAt: Date?
    private(set) var isSignalWeak = false
    private(set) var lastStartFailure: StartFailure?
    #if DEBUG
    private(set) var dumpEntries: [RunSampleDumpEntry] = []
    #endif

    var isActive: Bool { state == .acquiring || state == .tracking }

    private let locationStream: RunLocationStreamProtocol
    private var streamTask: Task<Void, Never>?

    init(locationStream: RunLocationStreamProtocol) {
        self.locationStream = locationStream
    }

    func start() async {
        guard state == .idle else { return }
        lastStartFailure = nil

        var accuracy = locationStream.currentAccuracy()
        if accuracy == .reduced {
            accuracy = await locationStream.requestSessionFullAccuracy()
        }
        guard accuracy == .full else {
            lastStartFailure = .reducedAccuracy
            return
        }

        let sessionStart = Date()
        startedAt = sessionStart
        track = RunTrack()
        #if DEBUG
        dumpEntries = []
        #endif
        state = .acquiring

        let stream = locationStream.startUpdates()
        streamTask = Task { [weak self] in
            for await sample in stream {
                self?.ingest(sample, sessionStart: sessionStart)
            }
            self?.streamEnded()
        }
    }

    func finish() {
        guard isActive else { return }
        stopStream()
        state = .summary
    }

    func dismissSummary() {
        guard state == .summary else { return }
        state = .idle
        track = RunTrack()
        startedAt = nil
        #if DEBUG
        dumpEntries = []
        #endif
    }

    private func ingest(_ sample: RunSample, sessionStart: Date) {
        guard isActive else { return }
        // 시작 직후 도착하는 캐시된 옛 샘플은 버린다(스펙 §4 필터링)
        guard sample.timestamp >= sessionStart else { return }

        let accepted = sample.horizontalAccuracyMeters > 0
            && sample.horizontalAccuracyMeters <= Self.maxHorizontalAccuracyMeters
        #if DEBUG
        dumpEntries.append(RunSampleDumpEntry(sample: sample, accepted: accepted))
        #endif
        guard accepted else {
            updateWeakSignal(now: sample.timestamp)
            return
        }

        track.append(sample)
        isSignalWeak = false
        if state == .acquiring { state = .tracking }
    }

    private func updateWeakSignal(now: Date) {
        guard let lastAccepted = track.samples.last else {
            // 아직 유효 샘플이 하나도 없는 신호 확보 단계 — 탈락이 이어지면 약신호 표시
            isSignalWeak = true
            return
        }
        if now.timeIntervalSince(lastAccepted.timestamp) >= Self.weakSignalTimeoutSeconds {
            isSignalWeak = true
        }
    }

    /// 스트림이 밖에서 끊긴 경우(러닝 도중 권한 회수 등) — 수집분을 버리지 않는다(스펙 §6)
    private func streamEnded() {
        guard isActive else { return }
        stopStream()
        if track.samples.isEmpty {
            state = .idle
            startedAt = nil
            lastStartFailure = .permissionDenied
        } else {
            state = .summary
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        locationStream.stopUpdates()
        isSignalWeak = false
    }
}
```

- [ ] **Step 4: 테스트 통과 확인** — `RunSessionTests` 전부 PASS + 전체 그린

- [ ] **Step 5: Commit**

```bash
git add Trace/Domain/RunTracking/Protocol/RunLocationStreamProtocol.swift Trace/Application/RunTracking/RunSession.swift TraceTests/RunSessionTests.swift
git commit -m "feat: RunSession 오케스트레이터 + 위치 스트림 포트 추가

시작/종료 수명주기(대기→신호확보→트래킹→요약), 캐시·정확도 필터,
약신호 감지, 러닝 도중 권한 회수 시 수집분 보존을 구현. DEBUG 빌드는
필터 판정 포함 덤프 기록을 남긴다(QA 데이터 확보, 스펙 §1). 테스트 11건."
```

---

### Task 3: Infrastructure — RunLocationTracker + 프로젝트 설정

**Files:**
- Create: `Trace/Infrastructure/Location/CoreLocation/RunLocationTracker.swift`
- Create: `Config/Trace-Info.plist` (임시 정밀 권한 purpose key — 딕셔너리라 INFOPLIST_KEY로 표현 불가)
- Modify: `Trace.xcodeproj/project.pbxproj` — 앱 타깃 Debug/Release 두 빌드 설정 블록(400행대·445행대)에 동일하게

**Interfaces:**
- Consumes: `RunLocationStreamProtocol`, `RunSample`, `RunLocationAccuracy` (Task 2)
- Produces: `RunLocationTracker()` — 프로토콜 구현체. 기존 단발 조회용 `CoreLocationService`와 별개 인스턴스(별도 CLLocationManager).

- [ ] **Step 1: 프로젝트 설정 변경**

`Trace.xcodeproj/project.pbxproj`의 앱 타깃 빌드 설정 **두 블록 모두**에:

```text
INFOPLIST_FILE = "Config/Trace-Info.plist";
INFOPLIST_KEY_UIBackgroundModes = location;
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "달릴 코스를 현재 위치에서 시작하고, 러닝 중 이동 경로를 기록하기 위해 위치를 사용합니다. 러닝 기록은 화면을 꺼도 계속됩니다.";
```

(기존 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` 줄은 위 문구로 교체. `GENERATE_INFOPLIST_FILE = YES`는 유지 — Xcode가 파일과 생성 키를 병합한다.)

`Config/Trace-Info.plist` 신규:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSLocationTemporaryUsageDescriptionDictionary</key>
    <dict>
        <key>RunTracking</key>
        <string>러닝 경로를 정확하게 기록하려면 이번 러닝 동안 정확한 위치가 필요합니다.</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 2: 빌드로 설정 검증**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED. 이어서 생성된 앱의 Info.plist에 `UIBackgroundModes`(location)와 `NSLocationTemporaryUsageDescriptionDictionary`가 있는지 확인:
`plutil -p ~/Library/Developer/Xcode/DerivedData/Trace-*/Build/Products/Debug-iphonesimulator/Trace.app/Info.plist | grep -A 3 "UIBackgroundModes\|Temporary"`

- [ ] **Step 3: RunLocationTracker 구현**

`Trace/Infrastructure/Location/CoreLocation/RunLocationTracker.swift`:

```swift
import CoreLocation
import Foundation

/// 러닝용 연속 위치 스트림 — 기존 CoreLocationService(단발 조회)와 별개.
/// CLLocationManager는 런루프 있는 스레드 생성이 필요해 기존 선례대로 @MainActor 격리(스펙 §4).
@MainActor
final class RunLocationTracker: NSObject, RunLocationStreamProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<RunSample>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 5
    }

    func currentAccuracy() -> RunLocationAccuracy {
        manager.accuracyAuthorization == .fullAccuracy ? .full : .reduced
    }

    func requestSessionFullAccuracy() async -> RunLocationAccuracy {
        // purposeKey는 Config/Trace-Info.plist의 NSLocationTemporaryUsageDescriptionDictionary 키와 일치해야 한다
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunTracking")
        return currentAccuracy()
    }

    func startUpdates() -> AsyncStream<RunSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunSample.self)
        self.continuation = continuation
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // 결과는 didChangeAuthorization에서
        case .restricted, .denied:
            finishStream()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdating()
        @unknown default:
            finishStream()
        }
        return stream
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        finishStream()
    }

    private func beginUpdating() {
        // Background Modes(location) capability가 있어야 크래시 없이 동작(Task 3 Step 1)
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func finishStream() {
        continuation?.finish()
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: self.beginUpdating()
            case .restricted, .denied: self.stopUpdates() // 러닝 도중 회수 포함 — 스트림 종료로 전파
            case .notDetermined: break
            @unknown default: self.stopUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { location in
            RunSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.altitude,
                speedMetersPerSecond: location.speed,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                verticalAccuracyMeters: location.verticalAccuracy
            )
        }
        Task { @MainActor in
            for sample in samples { self.continuation?.yield(sample) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let isDenied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            if isDenied { self.stopUpdates() }
            // 일시적 위치 실패(kCLErrorLocationUnknown 등)는 무시 — 스트림 유지, 필터가 처리
        }
    }
}
```

- [ ] **Step 4: 빌드 + 전체 테스트 그린 확인** (이 클래스는 실기기/시뮬레이터 통합으로 검증 — 단위 테스트 없음)

- [ ] **Step 5: Commit**

```bash
git add Trace/Infrastructure/Location/CoreLocation/RunLocationTracker.swift Config/Trace-Info.plist Trace.xcodeproj/project.pbxproj
git commit -m "feat: RunLocationTracker 연속 위치 스트림 + 백그라운드 위치 설정

러닝용 CLLocationManager(.fitness, 최고 정확도, 자동 일시정지 끔)를
AsyncStream으로 브리지. Background Modes(location) capability, 위치 문구
갱신, 임시 정밀 권한 purpose key(Config/Trace-Info.plist 병합)를 추가."
```

---

### Task 4: DependencyContainer 확장 + TabView 루트

**Files:**
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `Trace/App/TraceApp.swift`
- Create: `Trace/App/UITestingRunLocationStream.swift`

**Interfaces:**
- Consumes: `RunSession`, `RunLocationTracker` (Task 2·3)
- Produces: `container.runSession: RunSession` — RunPage(Task 5)와 RunActivityController(Task 9)가 사용. 탭 구조(코스/러닝).

- [ ] **Step 1: DependencyContainer에 runSession 추가**

`Trace/App/DependencyContainer.swift` — struct에 프로퍼티 추가 및 두 팩토리 수정:

```swift
struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol
    let cameraStateStore: CameraStateStore
    let courseRepository: CourseRepositoryProtocol
    let runSession: RunSession

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService(),
            cameraStateStore: CameraStateStore(),
            courseRepository: SwiftDataCourseRepository(),
            runSession: RunSession(locationStream: RunLocationTracker())
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        let uiTestingDefaults = UserDefaults(suiteName: "uiTesting") ?? .standard
        return DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService(),
            cameraStateStore: CameraStateStore(defaults: uiTestingDefaults),
            // in-memory: UI 테스트가 실기기/다른 테스트의 저장 코스 데이터와 격리되도록
            courseRepository: SwiftDataCourseRepository(inMemory: true),
            runSession: RunSession(locationStream: UITestingRunLocationStream())
        )
    }
}
```

`Trace/App/UITestingRunLocationStream.swift` 신규 — 서울시청에서 북쪽으로 초당 3m 이동하는 스크립트 스트림:

```swift
import Foundation

/// UI 테스트/시뮬레이터 수동 확인용 — 0.5초마다 북쪽으로 이동하는 가짜 위치 스트림.
@MainActor
final class UITestingRunLocationStream: RunLocationStreamProtocol {
    private var feedTask: Task<Void, Never>?

    func currentAccuracy() -> RunLocationAccuracy { .full }
    func requestSessionFullAccuracy() async -> RunLocationAccuracy { .full }

    func startUpdates() -> AsyncStream<RunSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunSample.self)
        feedTask = Task {
            var step = 0
            while Task.isCancelled == false {
                continuation.yield(RunSample(
                    timestamp: Date(),
                    latitude: 37.5666 + Double(step) * 1.5 / 111_320.0,
                    longitude: 126.9784,
                    altitudeMeters: 20,
                    speedMetersPerSecond: 3,
                    horizontalAccuracyMeters: 5,
                    verticalAccuracyMeters: 5
                ))
                step += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
            continuation.finish()
        }
        return stream
    }

    func stopUpdates() {
        feedTask?.cancel()
        feedTask = nil
    }
}
```

- [ ] **Step 2: TraceApp을 TabView로 전환**

`Trace/App/TraceApp.swift`의 `body`:

```swift
var body: some Scene {
    WindowGroup {
        TabView {
            CoursePlannerPage(
                coursePlanningService: container.coursePlanningService,
                locationService: container.locationService,
                cameraStateStore: container.cameraStateStore,
                courseRepository: container.courseRepository
            )
            .tabItem { Label("코스", systemImage: "map") }

            RunPage(session: container.runSession)
                .tabItem { Label("러닝", systemImage: "figure.run") }
        }
        .tint(DesignToken.Color.accent)
    }
}
```

(Task 5 전까지 컴파일을 위해 `Trace/Pages/RunPage/RunPage.swift`에 최소 스텁을 함께 생성:)

```swift
import SwiftUI

struct RunPage: View {
    let session: RunSession
    var body: some View { Text("러닝") }
}
```

- [ ] **Step 3: 빌드 + 전체 테스트 그린 확인** — 기존 CoursePlannerPage 흐름이 탭 안에서 그대로 동작해야 함(시뮬레이터 부팅해 코스 탭 스모크 확인: 지도 표시·탭 전환)

- [ ] **Step 4: Commit**

```bash
git add Trace/App/DependencyContainer.swift Trace/App/TraceApp.swift Trace/App/UITestingRunLocationStream.swift Trace/Pages/RunPage/RunPage.swift
git commit -m "feat: 탭 구조(코스/러닝) 도입 + RunSession 컨테이너 등록

두-기둥 독립 구조를 앱 루트에 반영(스펙 §3). RunSession은 컨테이너가
소유해 탭 전환에도 세션이 유지된다. UI 테스트용 가짜 위치 스트림 추가."
```

---

### Task 5: RunPage — 4상태 UI (대기/신호확보/트래킹/요약)

**Files:**
- Modify: `Trace/Pages/RunPage/RunPage.swift` (스텁 교체)
- Create: `Trace/Pages/RunPage/RunPageViewModel.swift`
- Create: `Trace/Pages/RunPage/PolylineThrottle.swift`
- Create: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`
- Test: `TraceTests/PolylineThrottleTests.swift`, `TraceTests/RunPaceFormatterTests.swift`

**Interfaces:**
- Consumes: `RunSession`(Task 2), `DesignToken`(기존), `GlassIconButtonStyle`(기존)
- Produces: `RunPage(session:)`. `PolylineThrottle`: `mutating func shouldRefresh(now: Date, totalDistanceMeters: Double) -> Bool`(3초 또는 +20m). `RunPaceFormatter.string(secondsPerKm:) -> String`(`5'32"`).

- [ ] **Step 1: 순수 로직 테스트 작성 (스로틀 + 페이스 포맷)**

`TraceTests/PolylineThrottleTests.swift`:

```swift
import XCTest
@testable import Trace

final class PolylineThrottleTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func test_첫호출은_항상_갱신한다() {
        var throttle = PolylineThrottle()
        XCTAssertTrue(throttle.shouldRefresh(now: base, totalDistanceMeters: 0))
    }

    func test_3초와_20m_모두_안지나면_갱신하지_않는다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertFalse(throttle.shouldRefresh(now: base.addingTimeInterval(1), totalDistanceMeters: 10))
    }

    func test_3초가_지나면_갱신한다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertTrue(throttle.shouldRefresh(now: base.addingTimeInterval(3.1), totalDistanceMeters: 0))
    }

    func test_20m를_넘게_이동하면_시간과_무관하게_갱신한다() {
        var throttle = PolylineThrottle()
        _ = throttle.shouldRefresh(now: base, totalDistanceMeters: 0)
        XCTAssertTrue(throttle.shouldRefresh(now: base.addingTimeInterval(0.5), totalDistanceMeters: 25))
    }
}
```

`TraceTests/RunPaceFormatterTests.swift`:

```swift
import XCTest
@testable import Trace

final class RunPaceFormatterTests: XCTestCase {
    func test_초퍼km를_분초로_포맷한다() {
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 332), "5'32\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 600), "10'00\"")
    }

    func test_nil이나_비정상값은_대시로_표시한다() {
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: nil), "--'--\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 0), "--'--\"")
        XCTAssertEqual(RunPaceFormatter.string(secondsPerKm: 3600), "--'--\"") // 60분/km 초과는 무의미
    }
}
```

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 에러

- [ ] **Step 3: 순수 로직 구현**

`Trace/Pages/RunPage/PolylineThrottle.swift`:

```swift
import Foundation

/// SwiftUI Map의 자라는 폴리라인을 매 위치 업데이트마다 다시 그리지 않기 위한 게이트(스펙 §4).
struct PolylineThrottle {
    static let minInterval: TimeInterval = 3
    static let minDistanceMeters: Double = 20

    private var lastRefreshAt: Date?
    private var lastRefreshDistance: Double = 0

    mutating func shouldRefresh(now: Date, totalDistanceMeters: Double) -> Bool {
        guard let last = lastRefreshAt else {
            lastRefreshAt = now
            lastRefreshDistance = totalDistanceMeters
            return true
        }
        let timeDue = now.timeIntervalSince(last) >= Self.minInterval
        let distanceDue = totalDistanceMeters - lastRefreshDistance >= Self.minDistanceMeters
        guard timeDue || distanceDue else { return false }
        lastRefreshAt = now
        lastRefreshDistance = totalDistanceMeters
        return true
    }
}

enum RunPaceFormatter {
    /// 초/km → `5'32"`. nil·0 이하·60분/km 초과는 `--'--"`.
    static func string(secondsPerKm: Double?) -> String {
        guard let seconds = secondsPerKm, seconds > 0, seconds < 3600 else { return "--'--\"" }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d'%02d\"", minutes, remainder)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

- [ ] **Step 5: RunPageViewModel + RunPage UI 구현**

`Trace/Pages/RunPage/RunPageViewModel.swift`:

```swift
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RunPageViewModel {
    let session: RunSession

    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    private(set) var displayedCoordinates: [CLLocationCoordinate2D] = []
    var showsAccuracyAlert = false
    var showsPermissionAlert = false
    private var polylineThrottle = PolylineThrottle()

    init(session: RunSession) {
        self.session = session
    }

    func startTapped() async {
        await session.start()
        switch session.lastStartFailure {
        case .reducedAccuracy: showsAccuracyAlert = true
        case .permissionDenied: showsPermissionAlert = true
        case nil:
            displayedCoordinates = []
            polylineThrottle = PolylineThrottle()
            recenter()
        }
    }

    func endRun() {
        session.finish()
        // 요약: 경로 전체가 보이도록 카메라 핏
        let coordinates = session.track.samples.map(\.coordinate)
        displayedCoordinates = coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if let region = Self.fittingRegion(for: displayedCoordinates) {
            cameraPosition = .region(region)
        }
    }

    func closeSummary() {
        session.dismissSummary()
        displayedCoordinates = []
        recenter()
    }

    /// 세션 샘플 수 변화 시 View의 onChange에서 호출 — 스로틀을 통과할 때만 폴리라인 재구성
    func refreshPolylineIfDue(now: Date = Date()) {
        guard session.state == .tracking else { return }
        guard polylineThrottle.shouldRefresh(
            now: now, totalDistanceMeters: session.track.totalDistanceMeters
        ) else { return }
        displayedCoordinates = session.track.samples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    func recenter() {
        cameraPosition = .userLocation(fallback: .automatic)
    }

    private static func fittingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        )
    }
}
```

`Trace/Pages/RunPage/RunPage.swift` (스텁 교체):

```swift
import MapKit
import SwiftUI

struct RunPage: View {
    @State private var viewModel: RunPageViewModel

    init(session: RunSession) {
        _viewModel = State(initialValue: RunPageViewModel(session: session))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            runMap
            controls
        }
        .onChange(of: viewModel.session.track.samples.count) {
            viewModel.refreshPolylineIfDue()
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
    }

    private var runMap: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()
            if viewModel.displayedCoordinates.count >= 2 {
                MapPolyline(coordinates: viewModel.displayedCoordinates)
                    .stroke(DesignToken.Color.accent, lineWidth: 5)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.session.state {
        case .idle:
            startButton
        case .acquiring:
            acquiringPanel
        case .tracking:
            RunStatsPanel(viewModel: viewModel)
        case .summary:
            RunSummaryPanel(viewModel: viewModel)
        }
    }

    private var startButton: some View {
        Button {
            Task { await viewModel.startTapped() }
        } label: {
            Text("시작")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 96, height: 96)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .padding(.bottom, 40)
    }

    private var acquiringPanel: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("GPS 신호 찾는 중…")
                .font(DesignToken.Typography.subtitle)
                .foregroundStyle(DesignToken.Color.ink)
            Button("취소") { viewModel.session.finishAcquiringCancelled() }
                .font(DesignToken.Typography.chip)
        }
        .padding(DesignToken.Size.sheetPadding)
        .background(DesignToken.Color.surface, in: RoundedRectangle(cornerRadius: DesignToken.Corner.chrome))
        .padding(.bottom, 40)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
```

(주: `finishAcquiringCancelled()`는 RunSession에 추가 — `state == .acquiring`이면 스트림을 멈추고 `.idle`로 복귀. `RunSessionTests`에 케이스 1건 추가: 신호 확보 중 취소하면 대기로 돌아온다.)

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` — 트래킹 패널 + 요약 패널 + 길게 눌러 종료:

```swift
import SwiftUI

/// 트래킹 중 하단 패널: 거리·경과 시간·현재 페이스 + 길게 눌러 종료 + 약신호 표시
struct RunStatsPanel: View {
    let viewModel: RunPageViewModel
    @State private var isPressingEnd = false

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.session.isSignalWeak {
                Text("GPS 신호 약함")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
            }
            HStack(spacing: 24) {
                stat(
                    value: String(format: "%.2f", viewModel.session.track.totalDistanceMeters / 1000),
                    unit: "km"
                )
                if let startedAt = viewModel.session.startedAt {
                    VStack(spacing: 2) {
                        Text(startedAt, style: .timer)
                            .font(DesignToken.Typography.segmentRowDistance)
                            .monospacedDigit()
                        Text("시간").font(DesignToken.Typography.sectionLabel)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                }
                stat(
                    value: RunPaceFormatter.string(
                        secondsPerKm: viewModel.session.track.currentPaceSecondsPerKm
                    ),
                    unit: "페이스"
                )
            }
            endButton
        }
        .padding(DesignToken.Size.sheetPadding)
        .frame(maxWidth: .infinity)
        .background(
            DesignToken.Color.surface,
            in: UnevenRoundedRectangle(topLeadingRadius: DesignToken.Corner.sheetTop,
                                       topTrailingRadius: DesignToken.Corner.sheetTop)
        )
        .overlay(alignment: .topTrailing) { recenterButton }
    }

    private var endButton: some View {
        Text("길게 눌러 종료")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DesignToken.Color.danger, in: Capsule())
            .scaleEffect(isPressingEnd ? 0.95 : 1)
            .onLongPressGesture(minimumDuration: 1.0) {
                viewModel.endRun()
            } onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.15)) { isPressingEnd = pressing }
            }
    }

    private var recenterButton: some View {
        Button { viewModel.recenter() } label: {
            Image(systemName: "location.fill")
        }
        .buttonStyle(GlassIconButtonStyle())
        .offset(y: -(DesignToken.Size.fab + 12))
        .padding(.trailing, DesignToken.Size.screenMargin)
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DesignToken.Typography.segmentRowDistance)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink)
            Text(unit)
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }
}

/// 종료 요약 패널: 총 거리·시간·평균 페이스·고도 상승 + 닫기 (+ DEBUG 덤프는 Task 6)
struct RunSummaryPanel: View {
    let viewModel: RunPageViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("러닝 요약").font(DesignToken.Typography.segmentRowTitle)
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    summaryItem(String(format: "%.2f km", viewModel.session.track.totalDistanceMeters / 1000), "거리")
                    summaryItem(durationText, "시간")
                }
                GridRow {
                    summaryItem(
                        RunPaceFormatter.string(secondsPerKm: viewModel.session.track.averagePaceSecondsPerKm),
                        "평균 페이스"
                    )
                    summaryItem(String(format: "%.0f m", viewModel.session.track.elevationGainMeters), "고도 상승")
                }
            }
            Button("닫기") { viewModel.closeSummary() }
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(DesignToken.Size.sheetPadding)
        .frame(maxWidth: .infinity)
        .background(
            DesignToken.Color.surface,
            in: UnevenRoundedRectangle(topLeadingRadius: DesignToken.Corner.sheetTop,
                                       topTrailingRadius: DesignToken.Corner.sheetTop)
        )
    }

    private var durationText: String {
        let total = Int(viewModel.session.track.duration)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DesignToken.Typography.segmentRowDistance).monospacedDigit()
            Text(label).font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }
}
```

탭 배지 — `Trace/App/TraceApp.swift`의 러닝 탭에 (TraceApp이 세션을 관찰할 수 있게 `@State private var` 등으로 컨테이너 세션 참조):

```swift
RunPage(session: container.runSession)
    .tabItem { Label("러닝", systemImage: "figure.run") }
    .badge(container.runSession.isActive ? "●" : nil)
```

(참고: `.badge(_:)`의 nil 처리 — `Text?`가 필요하면 `container.runSession.isActive ? Text("●") : nil` 형태로. 배지가 클리핑되면 `figure.run` 아이콘의 `.symbolEffect` 대안 없이 배지만 유지 — UI 세부는 확인 없이 진행 원칙.)

- [ ] **Step 6: 빌드 + 전체 테스트 + 시뮬레이터 확인**

`-traceUITesting` 인자로 실행(가짜 스트림) → 시작 탭 → 신호 확보 → 트래킹(폴리라인이 북쪽으로 자람, 타이머 진행, 페이스 표시) → 코스 탭 전환(배지 ● 표시, 돌아오면 유지) → 길게 눌러 종료 → 요약 수치 확인 → 닫기 → 대기 복귀. XcodeBuildMCP 빌드/런치/스크린샷 사용 가능(테스트 실행만 금지).

- [ ] **Step 7: Commit**

```bash
git add Trace/Pages/RunPage Trace/App/TraceApp.swift Trace/Application/RunTracking/RunSession.swift TraceTests/PolylineThrottleTests.swift TraceTests/RunPaceFormatterTests.swift TraceTests/RunSessionTests.swift
git commit -m "feat: RunPage 4상태 UI + 폴리라인 스로틀 + 탭 배지

대기/신호확보/트래킹/요약 화면, 길게 눌러 종료, 약신호 표시, 내 위치
복귀, 러닝 탭 진행 중 배지를 구현. 지도 폴리라인은 3초/20m 스로틀로
갱신해 장거리 프레임 드랍을 방지한다(스펙 §3·§4)."
```

---

### Task 6: DEBUG 샘플 덤프 내보내기

**Files:**
- Create: `Trace/Pages/RunPage/RunSampleDumpEncoder.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (요약 패널에 DEBUG 버튼)
- Test: `TraceTests/RunSampleDumpEncoderTests.swift`

**Interfaces:**
- Consumes: `RunSampleDumpEntry`(Task 2, DEBUG 전용), `session.dumpEntries`
- Produces: `RunSampleDumpEncoder.jsonData(entries:startedAt:) throws -> Data` — ISO8601 날짜의 pretty JSON

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunSampleDumpEncoderTests.swift`:

```swift
import XCTest
@testable import Trace

final class RunSampleDumpEncoderTests: XCTestCase {
    func test_덤프JSON에_샘플원시값과_필터판정이_들어간다() throws {
        let entry = RunSampleDumpEntry(
            sample: RunSample(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                latitude: 37.5, longitude: 127.0,
                altitudeMeters: 12, speedMetersPerSecond: 3,
                horizontalAccuracyMeters: 40, verticalAccuracyMeters: 5
            ),
            accepted: false
        )
        let data = try RunSampleDumpEncoder.jsonData(
            entries: [entry], startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"accepted\" : false"))
        XCTAssertTrue(json.contains("\"horizontalAccuracyMeters\" : 40"))
        XCTAssertTrue(json.contains("2023-11-14")) // ISO8601 날짜
    }
}
```

- [ ] **Step 2: 실패 확인** → **Step 3: 구현**

`Trace/Pages/RunPage/RunSampleDumpEncoder.swift`:

```swift
import Foundation

#if DEBUG
/// 본 러닝 QA에서 회수하는 원시 데이터 덤프(스펙 §1) — 사이클 2 저장 스키마 결정의 근거.
enum RunSampleDumpEncoder {
    struct Dump: Encodable {
        let startedAt: Date
        let entries: [RunSampleDumpEntry]
    }

    static func jsonData(entries: [RunSampleDumpEntry], startedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Dump(startedAt: startedAt, entries: entries))
    }
}
#endif
```

요약 패널(`RunSummaryPanel`)의 "닫기" 버튼 위에 추가:

```swift
#if DEBUG
if let dumpURL = try? writeDumpFile() {
    ShareLink(item: dumpURL) {
        Label("샘플 덤프 내보내기 (DEBUG)", systemImage: "square.and.arrow.up")
            .font(DesignToken.Typography.chip)
    }
}
#endif
```

```swift
#if DEBUG
private func writeDumpFile() throws -> URL {
    let session = viewModel.session
    let data = try RunSampleDumpEncoder.jsonData(
        entries: session.dumpEntries,
        startedAt: session.startedAt ?? Date()
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("run-dump-\(Int(Date().timeIntervalSince1970)).json")
    try data.write(to: url)
    return url
}
#endif
```

- [ ] **Step 4: 테스트 통과 + 시뮬레이터에서 요약 화면 공유 시트 확인**

- [ ] **Step 5: Commit**

```bash
git add Trace/Pages/RunPage/RunSampleDumpEncoder.swift Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift TraceTests/RunSampleDumpEncoderTests.swift
git commit -m "feat: DEBUG 샘플 덤프 내보내기(요약 화면 공유)

본 러닝 QA에서 원시 샘플(필터 판정 포함)을 JSON으로 회수해 사이클 2
저장 스키마 결정의 근거로 쓴다(스펙 §1). Release 빌드에는 포함되지 않는다."
```

**→ 마일스톤 ① 완료 지점.** `docs/roadmap.md`의 `run-tracking`을 `[x]`로 갱신하고 커밋. 실기기 가벼운 확인(동네 걷기 수준)은 사용자와 일정 협의 — ②와 묶어서 해도 된다(본 QA는 ② 후).

---

### Task 7: Widget Extension 타깃 추가 (사용자 개입 1회)

**Files:**
- Modify: `Trace.xcodeproj/project.pbxproj` (Xcode GUI가 수정)
- Create: `TraceWidgets/TraceWidgetsBundle.swift` (템플릿 정리 후)
- Create: `Trace/Domain/RunTracking/RunActivityAttributes.swift` (양쪽 타깃 멤버십)

**Interfaces:**
- Produces: `TraceWidgets` 타깃, `RunActivityAttributes`(ContentState: `distanceMeters: Double`, `paceSecondsPerKm: Double?` / 고정값: `startedAt: Date`)

- [ ] **Step 1: 사용자 개입 — Xcode GUI로 타깃 추가** (pbxproj 수동 편집은 서명·objectVersion 77 리스크로 기각)

사용자에게 안내할 체크리스트:
1. Xcode에서 File > New > Target… > **Widget Extension**
2. Product Name: `TraceWidgets`, **"Include Configuration App Intent" 체크 해제**, "Include Live Activity" 옵션이 보이면 **체크**
3. Activate scheme 팝업은 **Cancel**(Trace 스킴 유지)
4. 새 파일 `Trace/Domain/RunTracking/RunActivityAttributes.swift`를 만들면(아래 Step 2에서 에이전트가 생성) Xcode 파일 인스펙터의 Target Membership에서 **Trace와 TraceWidgets 둘 다 체크**

- [ ] **Step 2: 에이전트 — 공유 Attributes 파일 생성 + 템플릿 정리**

`Trace/Domain/RunTracking/RunActivityAttributes.swift`:

```swift
import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
    }

    /// 경과 시간은 매초 푸시하지 않고 Text(timerInterval:)이 이 값으로 자체 갱신한다(스펙 §5)
    var startedAt: Date
}
```

TraceWidgets 폴더의 템플릿 파일 중 정적 위젯 샘플(`TraceWidgets.swift` 등)은 삭제하고 번들 파일만 남긴다:

`TraceWidgets/TraceWidgetsBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct TraceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivityWidget() // Task 8에서 구현
    }
}
```

- [ ] **Step 3: 빌드 설정 정합** — 새 타깃의 `SWIFT_VERSION = 6.0`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0` 확인/수정(pbxproj의 TraceWidgets 빌드 설정 블록). 앱 타깃 두 블록에 `INFOPLIST_KEY_NSSupportsLiveActivities = YES;` 추가(필수 — 없으면 `Activity.request` 실패, 스펙 §5).

- [ ] **Step 4: 빌드 확인** (Task 8의 `RunLiveActivityWidget` 스텁이 필요하면 `EmptyWidgetConfiguration`이 아닌 최소 구현을 Task 8에서 함께 진행해도 된다 — 이 경우 Task 7·8을 한 커밋으로 묶는다)

- [ ] **Step 5: Commit**

```bash
git add Trace.xcodeproj/project.pbxproj TraceWidgets Trace/Domain/RunTracking/RunActivityAttributes.swift
git commit -m "chore: TraceWidgets 위젯 확장 타깃 신설 + Live Activity 속성 정의

잠금화면 Live Activity UI가 살 확장 타깃을 추가하고(NSSupportsLiveActivities
포함) 앱·위젯이 공유하는 RunActivityAttributes를 정의한다(스펙 §5)."
```

---

### Task 8: 잠금화면 Live Activity UI + Dynamic Island

**Files:**
- Create: `TraceWidgets/RunLiveActivityWidget.swift`

**Interfaces:**
- Consumes: `RunActivityAttributes` (Task 7)
- Produces: `RunLiveActivityWidget: Widget`

- [ ] **Step 1: 구현**

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metric(distanceText(context), label: "거리")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                        Text("시간").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    metric(paceText(context), label: "페이스")
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(distanceText(context)).monospacedDigit()
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "figure.run")
                .font(.title2)
            metric(distanceText(context), label: "거리")
            VStack(spacing: 2) {
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("시간").font(.caption2).foregroundStyle(.secondary)
            }
            metric(paceText(context), label: "페이스")
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.6))
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func distanceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        String(format: "%.2fkm", context.state.distanceMeters / 1000)
    }

    private func paceText(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
        guard let pace = context.state.paceSecondsPerKm, pace > 0, pace < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(pace) / 60, Int(pace) % 60)
    }
}
```

(주: `RunPaceFormatter`는 앱 타깃 소속이라 위젯에서 못 쓴다 — 포맷 로직을 여기 중복하는 대신 공유 파일로 옮기고 싶으면 Task 7의 멤버십 절차와 같은 사용자 개입이 필요하므로, 12줄 중복을 수용한다. 드리프트 방지 주석을 양쪽에 남긴다.)

- [ ] **Step 2: 빌드 확인** — 앱+위젯 두 타깃 모두 BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TraceWidgets/RunLiveActivityWidget.swift TraceWidgets/TraceWidgetsBundle.swift
git commit -m "feat: 러닝 Live Activity 잠금화면 카드 + Dynamic Island

거리·페이스는 ContentState로, 경과 시간은 Text(timerInterval:) 시스템
타이머로 표시해 갱신 예산 없이 초 단위 진행을 보여준다(스펙 §5)."
```

---

### Task 9: RunActivityController — 세션 구독 → Activity 갱신

**Files:**
- Create: `Trace/Application/RunTracking/RunActivityController.swift`
- Modify: `Trace/App/DependencyContainer.swift`, `Trace/App/TraceApp.swift`

**Interfaces:**
- Consumes: `RunSession`(Task 2), `RunActivityAttributes`(Task 7)
- Produces: `RunActivityController(session:)` + `func startObserving()` — 컨테이너 소유. RunSession은 ActivityKit을 모른다(스펙 §5 — 미래 오디오 안내 소비자의 선례).

- [ ] **Step 1: 구현**

`Trace/Application/RunTracking/RunActivityController.swift`:

```swift
import ActivityKit
import Foundation
import Observation

/// RunSession의 비뷰 소비자 — withObservationTracking으로 세션을 구독해
/// Live Activity 생성·갱신·제거를 전담한다(스펙 §5).
@MainActor
final class RunActivityController {
    private let session: RunSession
    private var activity: Activity<RunActivityAttributes>?

    init(session: RunSession) {
        self.session = session
    }

    func startObserving() {
        observeOnce()
    }

    private func observeOnce() {
        withObservationTracking {
            _ = session.state
            _ = session.track.totalDistanceMeters
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeOnce() // 관찰은 1회성이라 재등록
            }
        }
    }

    private func sync() {
        switch session.state {
        case .tracking:
            if activity == nil {
                startActivity()
            } else {
                updateActivity()
            }
        case .idle, .acquiring, .summary:
            endActivityIfNeeded()
        }
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return } // 꺼져 있으면 조용히 무시(스펙 §6)
        guard let startedAt = session.startedAt else { return }
        let attributes = RunActivityAttributes(startedAt: startedAt)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: currentState(), staleDate: nil)
        )
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = currentState()
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivityIfNeeded() {
        guard let activity else { return }
        self.activity = nil
        let finalState = currentState()
        Task {
            // 요약은 앱 화면이 담당 — 잠금화면 잔류 없이 즉시 제거(스펙 §5)
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private func currentState() -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            distanceMeters: session.track.totalDistanceMeters,
            paceSecondsPerKm: session.track.currentPaceSecondsPerKm
        )
    }
}
```

(갱신 빈도 주: 위치 업데이트는 `distanceFilter = 5m`로 이미 간격이 있고, `totalDistanceMeters` 변화 때만 onChange가 발화하므로 별도 스로틀 없이 시작한다 — 본 러닝 QA에서 과도하면 Live Activity 쪽에도 `PolylineThrottle` 같은 게이트를 추가.)

- [ ] **Step 2: 컨테이너·앱 배선**

`DependencyContainer`에 `let runActivityController: RunActivityController` 추가, `live()`에서:

```swift
let runSession = RunSession(locationStream: RunLocationTracker())
return DependencyContainer(
    ...,
    runSession: runSession,
    runActivityController: RunActivityController(session: runSession)
)
```

(uiTesting도 동일 패턴.) `TraceApp.init` 끝에서 `container.runActivityController.startObserving()` 호출.

- [ ] **Step 3: 시뮬레이터 확인** — `-traceUITesting`으로 시작 → 홈으로 나가 잠금화면(시뮬레이터: Device > Lock) → Live Activity 카드에 거리·시간(자체 진행)·페이스 표시 → 앱에서 종료 → 카드 즉시 사라짐

- [ ] **Step 4: 전체 테스트 그린 확인 + Commit**

```bash
git add Trace/Application/RunTracking/RunActivityController.swift Trace/App/DependencyContainer.swift Trace/App/TraceApp.swift
git commit -m "feat: RunActivityController — 세션 구독으로 Live Activity 수명 관리

RunSession은 ActivityKit을 모르고, 컨트롤러가 withObservationTracking으로
상태·거리 변화를 구독해 생성/갱신/즉시 제거를 전담한다(스펙 §5).
Live Activity 비활성 설정은 조용히 무시(스펙 §6)."
```

---

### Task 10: 마무리 — 통합 검증 + 문서 갱신 + 본 러닝 QA 체크리스트

**Files:**
- Modify: `docs/roadmap.md` (`run-live-activity` `[x]`)
- Create: `docs/qa/2026-07-XX-run-tracking-device-checklist.md` (작성일로)

- [ ] **Step 1: 최종 검증 일괄 실행**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```

Expected: BUILD SUCCEEDED · 기존 178 + 신규 테스트 전부 PASS · lint 위반 0

- [ ] **Step 2: 시뮬레이터 위치 시뮬레이션 통합 확인** — `-traceUITesting` 인자 없이 실기기 조건에 가깝게: `xcrun simctl location $SIM_UDID start --speed=3 --distance=100 <경로 좌표들>` 또는 Xcode 스킴의 GPX로 실제 `RunLocationTracker` 경로 검증(권한 팝업 → 트래킹 → 종료 요약)

- [ ] **Step 3: 본 러닝 QA 체크리스트 작성** — `docs/agent-rules/testing.md`의 시나리오 카드 템플릿(처음 쓰는 유저 기준 평이한 언어)로: 시작 전 권한 팝업 / 신호 확보 / 뛰는 중 거리·페이스·경로 / 폰 잠그고 잠금화면 카드 갱신 / 다른 앱 갔다 오기 / 코스 탭 전환·배지 / 길게 눌러 종료 / 요약 수치 상식 범위(특히 평지 고도 상승) / 덤프 회수 / 배터리 체감. 사용자에게 제시.

- [ ] **Step 4: roadmap 갱신 + Commit**

```bash
git add docs/roadmap.md docs/qa/
git commit -m "docs: MVP13 사이클 1 마일스톤 완료 처리 + 본 러닝 QA 체크리스트

run-tracking·run-live-activity 완료. 실기기 본 러닝 QA(잠금 상태 실주행)
체크리스트를 제시하고, 통과 후 사이클 2(run-record-save) 킥오프."
```

- [ ] **Step 5: 브랜치 리뷰** — `superpowers:requesting-code-review` + `/code-review` (표준 무게 사이클의 커밋 전 리뷰는 각 Task에서 수행됐어도, 통합 시점 최종 브랜치 리뷰 1회)

---

## Self-Review 결과 (플랜 작성 후 자체 점검)

- 스펙 커버리지: §1(덤프 포함 ✓ Task 6), §2(파생값·필터·고도 ✓ Task 1·2), §3(4상태·배지·recenter·hold-to-end ✓ Task 5), §4(레이어·트래커·격리·스로틀 ✓ Task 1~5), §5(위젯 타깃·NSSupportsLiveActivities·컨트롤러·즉시 제거 ✓ Task 7~9), §6(권한 거부/정확도/약신호/도중 회수/LA 실패 ✓ Task 2·3·5·9), §7(단위·통합·체크리스트 ✓ 각 Task + Task 10). §8은 사이클 2 범위라 제외.
- 미해결 갭(의도적): 실기기 본 러닝 QA는 사용자 실주행이 필요해 플랜 밖. Task 7의 타깃 추가는 사용자 개입 1회 필요(명시됨).
