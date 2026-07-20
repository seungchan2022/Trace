import XCTest
@testable import Trace

@MainActor
final class RecordingVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    var announcedPaces: [AnnouncementPace] = []
    var holds = 0, releases = 0, stops = 0
    func announce(_ text: String, pace: AnnouncementPace, kind: AnnouncementKind) {
        announced.append(text)
        announcedPaces.append(pace)
    }
    func holdAudioSession() { holds += 1 }
    func releaseAudioSession() { releases += 1 }
    func stopSpeaking() { stops += 1 }
}

@MainActor
final class RunPageViewModelTests: XCTestCase {
    // XCTest는 테스트 메서드마다 새 인스턴스를 만드므로 필드 초기화만으로 setUp과 동일하게 매번 새로 생성된다.
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)
    private let announcer = RecordingVoiceAnnouncer()
    private lazy var viewModel = RunPageViewModel(
        session: session,
        announcer: announcer,
        sleeper: { _ in } // 즉시 리턴 — 카운트다운을 동기적으로 소진
    )

    private func sample(at date: Date, latOffsetMeters: Double = 0) -> RunSample {
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
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms 폴링 간격
        }
    }

    /// 종료 시점에 벽시계 경과 시간을 캡처하는지 확인한다(스펙 리뷰 Fix 2).
    /// 요약 화면 시간 표기는 GPS 샘플 구간(`RunTrack.duration`)이 아니라, 트래킹 화면·Live Activity가
    /// 사용자에게 보여준 `startedAt` 기준 벽시계 시간과 일치해야 한다.
    func test_종료하면_시작시각부터의_벽시계_경과시간을_캡처한다() async throws {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }

        XCTAssertNil(viewModel.summaryElapsedSeconds)

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms 대기해 경과 시간이 관측 가능하게 한다
        viewModel.endRun()

        let elapsed = try XCTUnwrap(viewModel.summaryElapsedSeconds)
        XCTAssertGreaterThanOrEqual(elapsed, 0.05)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// 신호확보 중 취소한 경우처럼 `startedAt`이 없으면 캡처할 것이 없으니 nil로 남아야 한다.
    func test_시작하지_않은_상태에서_종료해도_크래시_없이_nil로_남는다() {
        viewModel.endRun()
        XCTAssertNil(viewModel.summaryElapsedSeconds)
    }

    /// 이전 러닝의 요약 시간이 다음 러닝에 잘못 이어붙지 않아야 한다 — 예를 들어 권한 회수로
    /// `endRun()` 없이(streamEnded 경로) 두 번째 러닝이 끝나면 캡처 로직이 다시 값을 세팅하지
    /// 않으므로, 첫 러닝의 값이 남아 있으면 잘못된 요약 시간이 노출된다(스펙 리뷰 Fix 2 후속).
    /// 다음 러닝을 시작하는 시점에 초기화해 이 낡은 값 노출을 막는다.
    func test_다음_러닝을_시작하면_이전_요약_경과시간이_초기화된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        viewModel.endRun()
        XCTAssertNotNil(viewModel.summaryElapsedSeconds)

        viewModel.closeSummary()
        await viewModel.startTapped()

        XCTAssertNil(viewModel.summaryElapsedSeconds)
    }

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

    /// 요약 화면 평균 페이스는 활동 시간(일시정지 제외) 기준이어야 한다(최종 브랜치 리뷰 Task 7).
    /// `RunTrack.averagePaceSecondsPerKm`(첫·마지막 샘플 타임스탬프 간격, 일시정지 포함)을 쓰면
    /// 같은 화면의 "시간" 필드·저장된 기록의 페이스와 값이 어긋난다 — 일시정지로 부풀려진 만큼 느리게 보인다.
    func test_요약_평균_페이스는_일시정지를_제외한_활동시간_기준이다() async throws {
        await viewModel.startTapped()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }

        try await Task.sleep(nanoseconds: 50_000_000) // 일시정지 전 실제로 뛴 시간
        session.pause(now: Date())
        try await Task.sleep(nanoseconds: 80_000_000) // 일시정지 구간 — 활동 시간에서 제외돼야 한다
        session.resume(now: Date())

        // 재개 직후 첫 샘플은 순간이동 방지로 거리 가산이 억제된다(RunTrack.markGap) — 위치만 갱신.
        stream.yield(sample(at: Date()))
        await waitUntil { session.track.samples.count == 2 }

        try await Task.sleep(nanoseconds: 30_000_000)
        // 1km 지점 샘플 — 첫 샘플과의 타임스탬프 간격(RunTrack.duration)에는 방금 그
        // 일시정지 구간이 그대로 섞여 들어간다(샘플이 드롭될 뿐 0으로 채워지지 않으므로).
        stream.yield(sample(at: Date(), latOffsetMeters: 1000))
        await waitUntil { session.track.samples.count == 3 }

        try await Task.sleep(nanoseconds: 20_000_000)
        viewModel.endRun()

        let distanceKm = session.track.totalDistanceMeters / 1000
        XCTAssertGreaterThan(distanceKm, 0)
        let elapsed = try XCTUnwrap(viewModel.summaryElapsedSeconds)
        XCTAssertGreaterThan(elapsed, 0)

        let expectedPace = elapsed / distanceKm
        let actualPace = try XCTUnwrap(viewModel.summaryAveragePaceSecondsPerKm)
        XCTAssertEqual(actualPace, expectedPace, accuracy: 0.0001)

        // 버그가 있었다면 이 값(RunTrack.duration 기준, 일시정지 포함)이 쓰였을 것이고
        // 활동 시간 기준보다 항상 더 느린(큰) 페이스로 나타난다.
        let buggyPace = try XCTUnwrap(session.track.averagePaceSecondsPerKm)
        XCTAssertLessThan(actualPace, buggyPace)
    }

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

    /// 격리된 UserDefaults suite — 프리필/저장 테스트가 .standard나 서로를 오염시키지 않게 한다.
    private func makeIsolatedDefaults(name: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func test_거리입력_파싱과_검증() {
        let defaults = makeIsolatedDefaults(name: #function)
        let vm = RunPageViewModel(session: session, announcer: announcer, defaults: defaults, sleeper: { _ in })
        vm.goalMode = .distance

        vm.goalDistanceInput = "5.5"
        XCTAssertEqual(vm.parsedGoalDistanceKm, 5.5)
        XCTAssertTrue(vm.isGoalInputValid)
        XCTAssertNil(vm.goalInputErrorText)

        for invalid in ["0", "-1", "abc"] {
            vm.goalDistanceInput = invalid
            XCTAssertNil(vm.parsedGoalDistanceKm, "invalid input \(invalid) should not parse")
            XCTAssertFalse(vm.isGoalInputValid)
            XCTAssertNotNil(vm.goalInputErrorText, "non-empty invalid input \(invalid) should show an error")
        }

        vm.goalDistanceInput = ""
        XCTAssertNil(vm.parsedGoalDistanceKm)
        XCTAssertFalse(vm.isGoalInputValid)
        XCTAssertNil(vm.goalInputErrorText, "empty input relies on the placeholder, not an inline error")
    }

    func test_시간입력_정수만_허용() {
        let defaults = makeIsolatedDefaults(name: #function)
        let vm = RunPageViewModel(session: session, announcer: announcer, defaults: defaults, sleeper: { _ in })
        vm.goalMode = .time

        vm.goalTimeInput = "30"
        XCTAssertEqual(vm.parsedGoalTimeMinutes, 30)
        XCTAssertTrue(vm.isGoalInputValid)

        vm.goalTimeInput = "30.5"
        XCTAssertNil(vm.parsedGoalTimeMinutes)
        XCTAssertFalse(vm.isGoalInputValid)

        vm.goalTimeInput = "0"
        XCTAssertNil(vm.parsedGoalTimeMinutes)
        XCTAssertFalse(vm.isGoalInputValid)
    }

    func test_composedGoal_입력값_반영() {
        let defaults = makeIsolatedDefaults(name: #function)
        let vm = RunPageViewModel(session: session, announcer: announcer, defaults: defaults, sleeper: { _ in })

        vm.goalMode = .distance
        vm.goalDistanceInput = "5.5"
        XCTAssertEqual(vm.composedGoal, .distance(meters: 5500))

        vm.goalMode = .time
        vm.goalTimeInput = "45"
        XCTAssertEqual(vm.composedGoal, .time(seconds: 2700))

        vm.goalMode = .open
        XCTAssertEqual(vm.composedGoal, .open)
    }

    func test_직전목표_프리필() {
        let name = #function
        let seededDefaults = makeIsolatedDefaults(name: name + ".seeded")
        seededDefaults.set(7.5, forKey: RunPageViewModel.lastDistanceKey)
        let seededVM = RunPageViewModel(
            session: session, announcer: announcer, defaults: seededDefaults, sleeper: { _ in }
        )
        XCTAssertEqual(seededVM.goalDistanceInput, "7.5")

        let emptyDefaults = makeIsolatedDefaults(name: name + ".empty")
        let emptyVM = RunPageViewModel(
            session: session, announcer: announcer, defaults: emptyDefaults, sleeper: { _ in }
        )
        XCTAssertEqual(emptyVM.goalDistanceInput, "")
    }

    func test_시작성공시_목표값_저장() async {
        let defaults = makeIsolatedDefaults(name: #function)
        let vm = RunPageViewModel(session: session, announcer: announcer, defaults: defaults, sleeper: { _ in })
        vm.goalMode = .distance
        vm.goalDistanceInput = "3.0"

        await vm.startTapped()

        XCTAssertEqual(defaults.double(forKey: RunPageViewModel.lastDistanceKey), 3.0)
    }

    func test_시작탭_카운트다운_삼이일_발화후_세션시작() async {
        await viewModel.startTapped()
        XCTAssertEqual(announcer.announced, ["삼", "이", "일"])
        // 일시정지/재개를 제외한 모든 발화는 measured(느린 속도) — 2026-07-18 후속 피드백
        XCTAssertEqual(announcer.announcedPaces, [.measured, .measured, .measured])
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
        // 정확도 게이트 대기 동안 예열용으로 미리 잡은 오디오 세션은 실패해도 반드시 해제해야 한다
        XCTAssertEqual(announcer.holds, 1)
        XCTAssertEqual(announcer.releases, 1)
    }

    // MARK: - 포인트 카드 (스펙 §2.2)

    private func startTrackingForWaypoint(_ vm: RunPageViewModel, at start: Date) async {
        await vm.startTapped()
        // startTapped()가 session.startedAt을 (카운트다운 종료 시점의) Date()로 세팅하므로,
        // 호출 전에 캡처한 `start`는 그보다 앞설 수 있다 — ingest()의 "캐시된 옛 샘플 폐기" 가드
        // (sample.timestamp >= sessionStart)에 걸려 샘플이 조용히 버려지고 .tracking 전이가
        // 영영 일어나지 않는다. max(start, Date())로 항상 sessionStart 이후 시각을 보장한다.
        stream.yield(RunSample(
            timestamp: max(start, Date()), latitude: 37.5666, longitude: 126.9784,
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
}
