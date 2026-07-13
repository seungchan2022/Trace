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

    /// AsyncStream 소비 태스크가 yield를 처리할 틈을 준다
    private func drain() async { try? await Task.sleep(nanoseconds: 20_000_000) }

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
