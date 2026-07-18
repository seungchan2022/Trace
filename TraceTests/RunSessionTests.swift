import XCTest
@testable import Trace

@MainActor
final class RunSessionTests: XCTestCase {
    // XCTest는 테스트 메서드마다 새 인스턴스를 만들므로 필드 초기화만으로 setUp과 동일하게 매번 새로 생성된다.
    // (setUp() 오버라이드 대신 필드 초기화를 쓴 이유: `var x: T!` IUO는 프로젝트 린트 규칙 위반이라 사용하지 않는다)
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)

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

    /// 조건이 참이 될 때까지 짧은 간격으로 폴링한다 — 타임아웃 시 실패시킨다(고정 sleep 대신).
    /// AsyncStream 소비 태스크가 실제로 스케줄되어 상태를 반영한 순간 즉시 진행하므로 고정 대기보다
    /// 빠르고 안정적이다. 소비 태스크가 전혀 스케줄되지 않은 경우(실제 버그)에만 타임아웃으로 실패한다.
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

    /// 소비 태스크가 "아무 부수효과도 남기지 않아야" 하는 경우(세션 시작 이전 타임스탬프의 캐시 샘플은
    /// `RunSession.ingest`의 최상단 guard에서 즉시 반환되어 관측 가능한 상태 변화가 전혀 없다) 전용 대기.
    /// 이런 케이스는 폴링할 실제(참이 되어야 할) 조건이 없으므로(첫 상태가 이미 기대값을 만족) waitUntil을
    /// 쓸 수 없다 — 짧은 고정 sleep으로 소비 태스크가 최소 한 번 스케줄될 시간만 확보한다.
    private func drainNoOp() async { try? await Task.sleep(nanoseconds: 20_000_000) }

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
        // ingest()가 세션 시작 이전 타임스탬프를 최상단 guard에서 즉시 버리므로 관측 가능한
        // 부수효과가 전혀 없다 — waitUntil로 폴링할 조건이 없어 고정 대기를 유지한다.
        await drainNoOp()
        XCTAssertEqual(session.state, .acquiring)
        XCTAssertTrue(session.track.samples.isEmpty)
    }

    func test_첫_유효샘플에서_트래킹으로_전이된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        XCTAssertEqual(session.state, .tracking)
        XCTAssertEqual(session.track.samples.count, 1)
    }

    func test_수평정확도가_나쁜_샘플은_버린다() async {
        await session.start()
        stream.yield(sample(at: Date(), hAcc: 80))
        // 샘플 자체는 버려지지만 신호확보 단계에서 첫 유효샘플이 없는 채로 탈락하면
        // updateWeakSignal()이 isSignalWeak을 동기적으로 true로 세운다 — 이를 소비 완료 신호로 폴링한다.
        await waitUntil { session.isSignalWeak }
        XCTAssertTrue(session.track.samples.isEmpty)
    }

    func test_마지막_유효샘플후_10초이상_탈락이_이어지면_약신호로_표시한다() async {
        await session.start()
        let now = Date()
        stream.yield(sample(at: now))
        stream.yield(sample(at: now.addingTimeInterval(12), hAcc: 80))
        await waitUntil { session.isSignalWeak }
        XCTAssertTrue(session.isSignalWeak)
        // 신호 회복 시 해제
        stream.yield(sample(at: now.addingTimeInterval(13)))
        await waitUntil { session.isSignalWeak == false }
        XCTAssertFalse(session.isSignalWeak)
    }

    func test_신호확보중_유효샘플없이_첫샘플이_탈락하면_즉시_약신호로_표시한다() async {
        await session.start()
        stream.yield(sample(at: Date(), hAcc: 80))
        await waitUntil { session.isSignalWeak }
        XCTAssertTrue(session.isSignalWeak)
        XCTAssertEqual(session.state, .acquiring)
        XCTAssertTrue(session.track.samples.isEmpty)
    }

    func test_종료하면_요약상태가_되고_스트림을_멈춘다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        session.finish()
        XCTAssertEqual(session.state, .summary)
        XCTAssertTrue(stream.stopped)
    }

    func test_요약을_닫으면_데이터가_소멸하고_대기로_돌아간다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        session.finish()
        session.dismissSummary()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.track.samples.isEmpty)
        XCTAssertNil(session.startedAt)
    }

    func test_러닝중_스트림이_끊기면_수집분으로_요약을_보여준다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        stream.finish() // 권한 회수 등
        await waitUntil { session.state == .summary }
        XCTAssertEqual(session.state, .summary)
        XCTAssertEqual(session.track.samples.count, 1)
    }

    func test_샘플없이_스트림이_끊기면_대기로_돌아가고_권한거부를_알린다() async {
        await session.start()
        stream.finish()
        await waitUntil { session.state == .idle }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastStartFailure, .permissionDenied)
    }

    func test_신호_확보_중_취소하면_대기로_돌아온다() async {
        await session.start()
        XCTAssertEqual(session.state, .acquiring)
        session.finishAcquiringCancelled()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.track.samples.isEmpty)
        XCTAssertNil(session.startedAt)
        XCTAssertTrue(stream.stopped)
    }

    func test_종료하면_기록이_자동저장된다() async {
        await session.start()
        let start = Date()
        stream.yield(sample(at: start))
        stream.yield(sample(at: start.addingTimeInterval(10), latOffsetMeters: 30))
        await waitUntil { self.session.track.samples.count == 2 }

        session.finish()
        await waitUntil { self.session.saveStatus == .saved }

        let savedRuns = await recordRepository.savedRuns
        XCTAssertEqual(savedRuns.count, 1)
        let saved = savedRuns[0]
        XCTAssertEqual(saved.samples.count, 2)
        XCTAssertEqual(saved.summary.distanceMeters, session.track.totalDistanceMeters)
        XCTAssertEqual(saved.summary.startedAt, session.startedAt)
        XCTAssertGreaterThan(saved.summary.duration, 0) // 벽시계 경과 시간
    }

    func test_저장실패시_상태가_failed가_되고_재시도로_저장된다() async {
        await recordRepository.failNextSave()
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }

        session.finish()
        await waitUntil { self.session.saveStatus == .failed }
        let savedRunsAfterFailure = await recordRepository.savedRuns
        XCTAssertTrue(savedRunsAfterFailure.isEmpty)

        session.retrySave()
        await waitUntil { self.session.saveStatus == .saved }
        let savedRuns = await recordRepository.savedRuns
        XCTAssertEqual(savedRuns.count, 1)
    }

    func test_재시도해도_같은_id로_저장된다_중복기록_방지() async {
        await recordRepository.failNextSave()
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }
        session.finish()
        await waitUntil { self.session.saveStatus == .failed }

        session.retrySave()
        await waitUntil { self.session.saveStatus == .saved }
        let savedRuns = await recordRepository.savedRuns
        XCTAssertEqual(savedRuns.count, 1) // 실패분이 중복 저장되지 않는다
    }

    func test_신호확보중_취소하면_저장하지_않는다() async {
        await session.start()
        session.finishAcquiringCancelled()
        await drainNoOp()
        XCTAssertNil(session.saveStatus)
        let savedRuns = await recordRepository.savedRuns
        XCTAssertTrue(savedRuns.isEmpty)
    }

    func test_요약을_닫으면_저장상태가_초기화된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }
        session.finish()
        await waitUntil { self.session.saveStatus == .saved }

        session.dismissSummary()
        XCTAssertNil(session.saveStatus)
    }

    func test_스트림이_끊겨_요약으로_가도_자동저장된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }

        stream.finish() // 권한 회수 등으로 스트림 종료 (MockRunLocationStream의 기존 헬퍼)
        await waitUntil { self.session.state == .summary }
        await waitUntil { self.session.saveStatus == .saved }
        let savedRuns = await recordRepository.savedRuns
        XCTAssertEqual(savedRuns.count, 1)
    }

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

}

// 클래스 본문이 swiftlint type_body_length(300줄) 임계를 넘지 않도록 신규 테스트를 확장으로 분리한다.
extension RunSessionTests {
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

    func test_prepareStart_정확도재요청_대기중_재진입은_거부된다() async {
        stream.accuracy = .reduced
        stream.accuracyAfterRequest = .full
        let gate = stream.gateAccuracyRequest()

        let firstTask = Task { await session.prepareStart() }
        await drainNoOp() // 첫 호출이 정확도 재요청 await 지점까지 진행할 시간 확보

        let secondTask = Task { await session.prepareStart() }
        await drainNoOp() // 두 번째 호출도 (버그가 있다면) 같은 지점까지 도달할 시간 확보

        gate.finish() // 두 대기자를 동시에 깨운다
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value

        XCTAssertTrue(firstResult)
        XCTAssertFalse(secondResult, "정확도 재요청 대기 중 재진입은 거부되어야 한다")
    }

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

        guard let saved = await recordRepository.savedRuns.first else { return XCTFail("저장 없음") }
        XCTAssertEqual(saved.pauses.count, 1)
        XCTAssertEqual(saved.pauses[0].duration, 30, accuracy: 0.001)
        // duration + 일시정지합 ≈ 벽시계 경과(오차 1초 이내 — finish까지의 실행 지연)
        let wallElapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual(saved.summary.duration + 30, wallElapsed, accuracy: 1.0)
    }
}

@MainActor
final class MockRunLocationStream: RunLocationStreamProtocol {
    var accuracy: RunLocationAccuracy = .full
    var accuracyAfterRequest: RunLocationAccuracy = .full
    private(set) var stopped = false
    private var continuation: AsyncStream<RunSample>.Continuation?
    private var accuracyRequestGate: AsyncStream<Void>?

    func currentAccuracy() -> RunLocationAccuracy { accuracy }

    func requestSessionFullAccuracy() async -> RunLocationAccuracy {
        if let gate = accuracyRequestGate {
            for await _ in gate { break }
        }
        return accuracyAfterRequest
    }

    /// requestSessionFullAccuracy()가 게이트가 닫힐 때까지 대기하게 만든다 — 재진입 레이스 테스트용.
    /// finish()는 대기 중인 모든 소비자(여러 for-await)를 동시에 깨운다.
    func gateAccuracyRequest() -> AsyncStream<Void>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        accuracyRequestGate = stream
        return continuation
    }

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
