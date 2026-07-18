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
        // 부트스트랩 샘플은 실제 session.startedAt(≥ start, prepareStart의 비동기 처리 시간만큼
        // 늦다) 기준으로 찍어야 한다 — `start`를 그대로 쓰면 RunSession.ingest()의
        // `sample.timestamp >= sessionStart` 가드에 걸려 조용히 버려지고 tracking 전이가
        // 영원히 일어나지 않는다(브리프 원본 테스트 코드의 결함, task-1-report.md 참고).
        stream.yield(sample(at: session.startedAt ?? start))
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
        // prepareStart()는 state == .idle에서만 진입한다(기존 가드) — summary를 닫아 idle로
        // 되돌린 뒤, prepareStart() 자체의 리셋 경로(dismissSummary와는 별개 지점)가
        // waypoints를 비우는지 별도로 확인한다.
        session.dismissSummary()
        _ = await session.prepareStart()
        XCTAssertTrue(session.waypoints.isEmpty)
        session.cancelPreparation()
    }

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
}
