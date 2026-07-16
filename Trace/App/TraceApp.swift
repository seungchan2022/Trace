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
        container.runActivityController.startObserving()
        container.runAudioCoach.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                CoursePlannerPage(
                    coursePlanningService: container.coursePlanningService,
                    locationService: container.locationService,
                    cameraStateStore: container.cameraStateStore,
                    courseRepository: container.courseRepository
                )
                .tabItem { Label("코스", systemImage: "map") }

                RunPage(session: container.runSession, recordRepository: container.runRecordRepository)
                    .tabItem { Label("러닝", systemImage: "figure.run") }
                    .badge(container.runSession.isActive ? "●" : nil)
            }
            .tint(DesignToken.Color.accent)
        }
    }
}
