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
    private func startTracking(goal: RunGoal = .open) async {
        await session.start(goal: goal)
        coach.sync()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        coach.sync()
        announcer.announced.removeAll()
        announcer.announcedPaces.removeAll()
    }

    func test_시작하면_러닝시작_발화() async {
        await session.start()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["러닝을 시작합니다"])
    }

    func test_일시정지와_재개_발화() async {
        await startTracking()
        session.pause()
        coach.sync()
        session.resume()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["일시정지합니다", "재개합니다"])
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
        XCTAssertTrue(announcer.announced[0].hasPrefix("러닝을 종료합니다. 총 "))
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

    func test_목표_절반은_한번만_발화() async {
        await startTracking(goal: .distance(meters: 1000))
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(150), metersNorth: 505))
        await waitUntil { session.track.totalDistanceMeters > 500 }
        coach.sync()
        XCTAssertEqual(announcer.announced, ["절반 왔습니다"])

        // 절반 이후 추가 샘플 — 중복 발화 없음
        stream.yield(sample(at: start.addingTimeInterval(160), metersNorth: 520))
        await waitUntil { session.track.totalDistanceMeters > 515 }
        coach.sync()
        XCTAssertEqual(announcer.announced, ["절반 왔습니다"])
    }

    func test_목표달성은_km발화_다음_한번만_절반을_덮는다() async {
        // 한 샘플에 1km 경계와 절반·달성이 모두 걸림: km 먼저, 달성이 절반을 덮어 2건만
        await startTracking(goal: .distance(meters: 1000))
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 2)
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))
        XCTAssertTrue(announcer.announced[1].hasPrefix("목표를 달성했습니다."))
        XCTAssertTrue(announcer.announced[1].contains("평균 페이스")) // 목표 달성 발화도 종료 발화와 동일하게 페이스 절 포함

        // 달성 후 추가 샘플 — 재발화 없음
        stream.yield(sample(at: start.addingTimeInterval(310), metersNorth: 1020))
        await waitUntil { session.track.totalDistanceMeters > 1015 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 2)
    }

    func test_자유러닝은_목표발화가_없다() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1) // km 발화뿐
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))
    }

    func test_km경계와_목표달성_발화는_measured_속도() async {
        // 숫자 정보가 많은 문구는 알아듣기 어렵다는 실사용 QA 피드백(2026-07-18)으로 느린 속도 지정
        await startTracking(goal: .distance(meters: 1000))
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 2) // km 발화 + 목표 달성 발화
        XCTAssertEqual(announcer.announcedPaces, [.measured, .measured])
    }

    func test_상태전환과_절반_발화는_기본속도() async {
        // 시작·일시정지·재개·절반·종료는 짧은 문구라 기본 속도를 유지한다(2026-07-18)
        await session.start(goal: .distance(meters: 1000))
        coach.sync() // 시작 발화
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        coach.sync() // acquiring→tracking 전이 자체엔 발화 없음

        session.pause()
        coach.sync() // 일시정지 발화
        session.resume()
        coach.sync() // 재개 발화

        let start = Date()
        stream.yield(sample(at: start)) // 재개 직후 첫 샘플은 위치 앵커일 뿐 거리에는 반영되지 않는다
        stream.yield(sample(at: start.addingTimeInterval(150), metersNorth: 505))
        await waitUntil { session.track.totalDistanceMeters > 500 }
        coach.sync() // 절반 발화

        session.finish()
        coach.sync() // 종료 발화

        XCTAssertEqual(announcer.announced.count, 5)
        XCTAssertEqual(announcer.announcedPaces, [.brisk, .brisk, .brisk, .brisk, .brisk])
    }

    func test_새러닝을_시작하면_목표발화_카운터가_리셋된다() async {
        await startTracking(goal: .distance(meters: 1000))
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(150), metersNorth: 505))
        await waitUntil { session.track.totalDistanceMeters > 500 }
        coach.sync()
        session.finish()
        coach.sync()
        session.dismissSummary()
        coach.sync()

        // 두 번째 러닝: 절반이 다시 나와야 한다
        await startTracking(goal: .distance(meters: 1000))
        let restart = Date()
        stream.yield(sample(at: restart.addingTimeInterval(150), metersNorth: 505))
        await waitUntil { session.track.totalDistanceMeters > 500 }
        coach.sync()
        XCTAssertEqual(announcer.announced, ["절반 왔습니다"])
    }
}

@MainActor
final class FakeVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    var announcedPaces: [AnnouncementPace] = []
    func announce(_ text: String, pace: AnnouncementPace) {
        announced.append(text)
        announcedPaces.append(pace)
    }
}
