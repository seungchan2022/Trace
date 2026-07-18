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
