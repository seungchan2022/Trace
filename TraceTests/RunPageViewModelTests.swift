import XCTest
@testable import Trace

@MainActor
final class RunPageViewModelTests: XCTestCase {
    // XCTest는 테스트 메서드마다 새 인스턴스를 만드므로 필드 초기화만으로 setUp과 동일하게 매번 새로 생성된다.
    private let stream = MockRunLocationStream()
    private lazy var session = RunSession(locationStream: stream)
    private lazy var viewModel = RunPageViewModel(session: session)

    private func sample(at date: Date) -> RunSample {
        RunSample(
            timestamp: date,
            latitude: 37.5666,
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
}
