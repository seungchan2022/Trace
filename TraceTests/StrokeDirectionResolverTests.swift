import XCTest
@testable import Trace

final class StrokeDirectionResolverTests: XCTestCase {
    // 기존 경로: A(37.50, 127.00) → B(37.52, 127.00)
    let courseStart = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    let courseEnd = CourseCoordinate(latitude: 37.52, longitude: 127.00)

    func testStrokeNearEndAppendsForward() {
        // 새 스트로크: 끝점(B) 근처에서 시작 → 더 멀리
        let stroke = [
            CourseCoordinate(latitude: 37.521, longitude: 127.00),
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .append)
        XCTAssertEqual(result.orientedStroke.first, stroke.first)
    }

    func testStrokeNearStartPrependsForward() {
        // 새 스트로크: 시작점(A) 근처에서 끝남 → 더 멀리에서 시작
        let stroke = [
            CourseCoordinate(latitude: 37.48, longitude: 127.00),
            CourseCoordinate(latitude: 37.499, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .prepend)
        // 스트로크 끝이 A에 가까우므로, 역순으로 뒤집혀서
        // orientedStroke의 끝이 A에 가까워야 한다
        let lastOfOriented = result.orientedStroke.last!
        let firstOfOriented = result.orientedStroke.first!
        XCTAssertTrue(lastOfOriented.distanceMeters(to: courseStart) < firstOfOriented.distanceMeters(to: courseStart))
    }

    func testStrokeNearEndButReversedGetsFlipped() {
        // 새 스트로크: B 근처에서 끝남 (시작은 멀리) → append이지만 reverse 필요
        let stroke = [
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
            CourseCoordinate(latitude: 37.521, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .append)
        // orientedStroke의 시작이 B에 가까워야 함
        let first = result.orientedStroke.first!
        XCTAssertTrue(first.distanceMeters(to: courseEnd) < 200)
    }

    func testFirstStrokeReturnsInitial() {
        let stroke = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: nil,
            existingCourseEnd: nil
        )
        XCTAssertEqual(result.direction, .initial)
        XCTAssertEqual(result.orientedStroke, stroke)
    }
}
