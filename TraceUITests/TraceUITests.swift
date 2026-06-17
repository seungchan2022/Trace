import XCTest

final class TraceUITests: XCTestCase {
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

        XCTAssertTrue(app.staticTexts["1.20 km"].waitForExistence(timeout: 5))
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
