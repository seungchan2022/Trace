//
//  TraceApp.swift
//  Trace
//
//  Created by 승찬 on 6/16/26.
//

import SwiftUI

@main
struct TraceApp: App {
    private let container: DependencyContainer

    init() {
        if ProcessInfo.processInfo.arguments.contains("-traceUITesting") {
            container = .uiTesting()
        } else {
            container = .live()
        }
    }

    var body: some Scene {
        WindowGroup {
            CoursePlannerPage(coursePlanningService: container.coursePlanningService)
        }
    }
}
