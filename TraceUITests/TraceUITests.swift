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

    @MainActor
    func testRunTabHasNoHistoryEntryPointAndHistoryTabShowsEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        app.buttons["러닝"].tap()
        XCTAssertFalse(app.buttons["러닝 기록"].exists)

        app.buttons["기록"].tap()
        XCTAssertTrue(app.navigationBars["기록"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["아직 기록이 없어요"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRunTabShowsGoalSetupAndDistanceInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        app.buttons["러닝"].tap()

        XCTAssertTrue(app.staticTexts["run.idle.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["자유"].exists)
        XCTAssertTrue(app.buttons["거리"].exists)
        XCTAssertTrue(app.buttons["시간"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["run.goalPicker"].exists)
        XCTAssertTrue(app.buttons["run.startButton"].exists)

        app.buttons["거리"].tap()
        XCTAssertTrue(app.staticTexts["km"].waitForExistence(timeout: 5))
    }

    // 구간 1개면 리스트 콘텐츠가 뷰포트보다 짧아 양끝이 동시에 참이다 —
    // 리스트 아무 데나 잡고 아래로 끌면 시트가 한 단계 접힌다.
    @MainActor
    func testDraggingSegmentListDownCollapsesSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        // 초기 단계는 기본(접힘)이라 리스트가 렌더되지 않는다. 헤더를 눌러 중간으로 올린다.
        // bottomSheet 서브트리는 자식 Button의 identifier가 부모('coursePlanner.segmentPanel')로
        // 뭉개지는 알려진 문제가 있어(docs/solutions/workflow-issues/
        // child-accessibility-identifiers-collapse-to-parent-in-bottomsheet.md) 직접
        // "coursePlanner.segmentPanel.collapsed"로 조회할 수 없다. 같은 버튼 라벨 안의 자식
        // StaticText("coursePlanner.prompt")는 고유 identifier를 유지하므로 그걸 탭한다
        // (행 아이템 "coursePlanner.segmentPanel.item.0"·"roundTrip.0"은 실측 결과 이 뭉개짐의
        // 영향을 받지 않아 원래대로 조회 가능하다).
        let collapsedHeader = app.staticTexts["coursePlanner.prompt"]
        XCTAssertTrue(collapsedHeader.waitForExistence(timeout: 5))
        collapsedHeader.tap()

        let row = app.buttons["coursePlanner.segmentPanel.item.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)))

        // 기본 단계에서는 expandedSheetBody 자체가 사라진다.
        let disappeared = NSPredicate(format: "exists == false")
        expectation(for: disappeared, evaluatedWith: row)
        waitForExpectations(timeout: 5)
    }

    // 회귀 1순위: 리스트에 제스처를 얹어도 구간 행 버튼이 탭을 그대로 받아야 한다.
    // 2026-07-12에 sheetHeader를 제스처로 감쌌다가 안쪽 버튼이 전부 먹통이 된 이력이 있다.
    @MainActor
    func testSegmentRowButtonsStayTappableWithListDragGesture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["coursePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        // 위 테스트와 같은 이유로 identifier가 아닌 자식 StaticText를 통해 헤더를 탭한다.
        let collapsedHeader = app.staticTexts["coursePlanner.prompt"]
        XCTAssertTrue(collapsedHeader.waitForExistence(timeout: 5))
        collapsedHeader.tap()

        let row = app.buttons["coursePlanner.segmentPanel.item.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(app.buttons["coursePlanner.segmentPanel.roundTrip.0"].exists)

        // 탭이 드래그로 해석되면 시트 단계가 바뀌어 행이 사라진다. 탭 뒤에도 남아 있어야 한다.
        row.tap()
        XCTAssertTrue(row.exists)
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
