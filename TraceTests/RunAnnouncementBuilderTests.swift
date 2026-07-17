import XCTest
@testable import Trace

final class RunAnnouncementBuilderTests: XCTestCase {
    func test_상태전환_고정문구() {
        XCTAssertEqual(RunAnnouncementBuilder.start, "러닝 시작")
        XCTAssertEqual(RunAnnouncementBuilder.pause, "일시정지")
        XCTAssertEqual(RunAnnouncementBuilder.resume, "재개합니다")
    }

    func test_km경계_문구는_거리_총시간_평균페이스() {
        let text = RunAnnouncementBuilder.kilometer(
            km: 3, totalSeconds: 1110, averagePaceSecondsPerKm: 370
        )
        XCTAssertEqual(text, "3킬로미터. 총 시간 18분 30초. 평균 페이스 6분 10초")
    }

    func test_km경계_페이스없으면_절생략() {
        let text = RunAnnouncementBuilder.kilometer(
            km: 1, totalSeconds: 300, averagePaceSecondsPerKm: nil
        )
        XCTAssertEqual(text, "1킬로미터. 총 시간 5분")
    }

    func test_종료_문구는_총거리_시간_평균페이스() {
        let text = RunAnnouncementBuilder.finish(
            distanceMeters: 5200, totalSeconds: 1900, averagePaceSecondsPerKm: 365
        )
        XCTAssertEqual(text, "러닝 종료. 총 5.2킬로미터, 31분 40초, 평균 페이스 6분 5초")
    }

    func test_종료_정수km는_소수점없이_읽는다() {
        let text = RunAnnouncementBuilder.finish(
            distanceMeters: 5000, totalSeconds: 1800, averagePaceSecondsPerKm: 360
        )
        XCTAssertEqual(text, "러닝 종료. 총 5킬로미터, 30분, 평균 페이스 6분")
    }

    func test_시간읽기_시간분초_조합() {
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(45), "45초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(300), "5분")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(1110), "18분 30초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(3725), "1시간 2분 5초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(0), "0초")
    }

    func test_페이스읽기_비정상값은_nil() {
        XCTAssertEqual(RunAnnouncementBuilder.spokenPace(370), "6분 10초")
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(nil))
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(0))
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(3600)) // 60분/km 초과는 표시 규칙과 동일하게 무효
    }

    func test_목표_절반_문구() {
        XCTAssertEqual(RunAnnouncementBuilder.goalHalf, "절반 왔습니다")
    }

    func test_목표_달성_문구() {
        XCTAssertEqual(
            RunAnnouncementBuilder.goalAchieved(distanceMeters: 5000, totalSeconds: 1750),
            "목표 달성! 5킬로미터, 29분 10초"
        )
    }
}
