//
//  TraceUITestsLaunchTests.swift
//  TraceUITests
//
//  Created by 승찬 on 6/16/26.
//

import XCTest

nonisolated final class TraceUITestsLaunchTests: XCTestCase {

    // XCTestCase의 class var를 재정의하는 자리라 static으로 못 바꾼다(static은 재정의 불가) — 규칙 오탐.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
