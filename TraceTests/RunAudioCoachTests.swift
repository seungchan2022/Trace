import XCTest
@testable import Trace

@MainActor
final class RunAudioCoachTests: XCTestCase {
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)
    private let announcer = FakeVoiceAnnouncer()
    private lazy var coach = RunAudioCoach(session: session, announcer: announcer)

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

    /// 시작 → 첫 샘플 수용(tracking 진입)까지 진행하고 발화 로그를 비운다
    private func startTracking() async {
        await session.start()
        coach.sync()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        coach.sync()
        announcer.announced.removeAll()
    }

    func test_시작하면_러닝시작_발화() async {
        await session.start()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["러닝 시작"])
    }

    func test_일시정지와_재개_발화() async {
        await startTracking()
        session.pause()
        coach.sync()
        session.resume()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["일시정지", "재개합니다"])
    }

    func test_km경계를_넘으면_한번만_발화() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))

        // 같은 km 안에서 추가 샘플 — 중복 발화 없음
        stream.yield(sample(at: start.addingTimeInterval(310), metersNorth: 1020))
        await waitUntil { session.track.totalDistanceMeters > 1015 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
    }

    func test_상태변화없는_sync는_발화하지_않는다() async {
        await startTracking()
        coach.sync()
        coach.sync()
        XCTAssertTrue(announcer.announced.isEmpty)
    }

    func test_종료하면_러닝종료_발화() async {
        await startTracking()
        session.finish()
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("러닝 종료. 총 "))
    }

    func test_새러닝을_시작하면_km카운터가_리셋된다() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        session.finish()
        coach.sync()
        session.dismissSummary()
        coach.sync()
        announcer.announced.removeAll()

        // 두 번째 러닝: 다시 1km를 넘으면 "1킬로미터"가 다시 나와야 한다
        await startTracking()
        let restart = Date()
        stream.yield(sample(at: restart.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))
    }

    func test_종료후_최종활동시간이_고정된다() async {
        await startTracking()
        XCTAssertNil(session.summaryActiveElapsedSeconds)
        session.finish()
        let first = session.summaryActiveElapsedSeconds
        XCTAssertNotNil(first)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.summaryActiveElapsedSeconds, first) // now가 지나도 안 자란다
    }
}

@MainActor
final class FakeVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    func announce(_ text: String) { announced.append(text) }
}
