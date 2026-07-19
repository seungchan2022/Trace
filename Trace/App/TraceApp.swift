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

        let session = container.runSession
        let activityController = container.runActivityController
        MarkRunWaypointIntentBridge.handler = {
            RunWaypointIntentAction(
                session: session,
                endOrphanedActivities: { activityController.endOrphanedActivities() }
            ).perform()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .tint(DesignToken.Color.accent)
        }
    }
}
