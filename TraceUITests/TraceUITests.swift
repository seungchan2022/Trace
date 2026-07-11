import XCTest

nonisolated final class TraceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingTwoPointsShowsDistance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        // Task 6(design-apply)부터 거리 헤드라인은 숫자(Text)와 단위 "km"(Text)가 분리된
        // 두 개의 접근성 엘리먼트로 렌더링된다(스펙 §2 — 44pt 숫자 + 17pt 단위 분리 표기).
        // 이전엔 "1.20 km" 문자열 전체가 하나의 Text였으나 이제는 숫자만 단독으로 존재한다.
        XCTAssertTrue(app.staticTexts["1.20"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRouteFailureShowsError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting", "-traceRouteFailure"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        XCTAssertTrue(app.staticTexts["도보 경로를 찾을 수 없습니다."].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func tapCoordinate(xRatio: CGFloat, yRatio: CGFloat) {
        let coordinate = coordinate(
            withNormalizedOffset: CGVector(dx: xRatio, dy: yRatio)
        )
        coordinate.tap()
    }
}
