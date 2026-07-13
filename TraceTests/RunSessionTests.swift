import XCTest
@testable import Trace

@MainActor
final class RunSessionTests: XCTestCase {
    // XCTest는 테스트 메서드마다 새 인스턴스를 만들므로 필드 초기화만으로 setUp과 동일하게 매번 새로 생성된다.
    // (setUp() 오버라이드 대신 필드 초기화를 쓴 이유: `var x: T!` IUO는 프로젝트 린트 규칙 위반이라 사용하지 않는다)
    private let stream = MockRunLocationStream()
    private lazy var session = RunSession(locationStream: stream)

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
