import XCTest
@testable import Trace

@MainActor
final class RunSessionGoalTests: XCTestCase {
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)

    private func sample(at date: Date, metersNorth: Double = 0) -> RunSample {
        RunSample(
            timestamp: date,
            latitude: 37.5666 + metersNorth / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5,
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

    private func startTracking(goal: RunGoal) async -> Date {
        await session.start(goal: goal)
        let start = Date()
        stream.yield(sample(at: start))
        await waitUntil { session.state == .tracking }
        return start
    }

    func test_시작시_목표를_보유하고_기본은_자유다() async {
        await session.start(goal: .distance(meters: 5000))
        XCTAssertEqual(session.goal, .distance(meters: 5000))
        session.finishAcquiringCancelled()
        await session.start()
        XCTAssertEqual(session.goal, .open)
    }

    func test_거리목표_절반과_달성_플래그가_순서대로_켜진다() async {
        let start = await startTracking(goal: .distance(meters: 1000))
        XCTAssertFalse(session.goalHalfReached)

        stream.yield(sample(at: start.addingTimeInterval(150), metersNorth: 505))
        await waitUntil { session.track.totalDistanceMeters > 500 }
        XCTAssertTrue(session.goalHalfReached)
        XCTAssertFalse(session.goalAchieved)

        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1010))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        XCTAssertTrue(session.goalAchieved)
        XCTAssertEqual(session.state, .tracking) // 달성 후에도 트래킹 계속(결정 6)
    }

    func test_시간목표는_샘플_타임스탬프_기준_활동시간으로_판정한다() async {
        let start = await startTracking(goal: .time(seconds: 600))
        stream.yield(sample(at: start.addingTimeInterval(301), metersNorth: 10))
        await waitUntil { session.track.samples.count >= 2 }
        XCTAssertTrue(session.goalHalfReached)
        XCTAssertFalse(session.goalAchieved)

        stream.yield(sample(at: start.addingTimeInterval(601), metersNorth: 20))
        await waitUntil { session.track.samples.count >= 3 }
        XCTAssertTrue(session.goalAchieved)
    }

    func test_시간목표는_일시정지_시간을_제외한다() async {
        let start = await startTracking(goal: .time(seconds: 800))
        session.pause(now: start.addingTimeInterval(100))
        session.resume(now: start.addingTimeInterval(700)) // 600초 일시정지
        // 벽시계 1300초 경과, 활동 시간 700초 < 800초 — 아직 미달성
        stream.yield(sample(at: start.addingTimeInterval(1300), metersNorth: 30))
        await waitUntil { session.track.samples.count >= 2 }
        XCTAssertFalse(session.goalAchieved)
    }

    func test_요약을_닫으면_목표가_리셋된다() async {
        let start = await startTracking(goal: .distance(meters: 1000))
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1010))
        await waitUntil { session.goalAchieved }
        session.finish()
        session.dismissSummary()
        XCTAssertEqual(session.goal, .open)
        XCTAssertFalse(session.goalHalfReached)
        XCTAssertFalse(session.goalAchieved)
    }
}
