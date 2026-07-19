//
//  RootView.swift
//  Trace
//
//  Created by 승찬 on 7/19/26.
//

import SwiftUI

struct RootView: View {
    private let container: DependencyContainer
    @State private var selectedTab: AppTab = .course // 냉시작 기본 탭 = 코스 (ui-direction §1)

    init(container: DependencyContainer) {
        self.container = container
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CoursePlannerPage(
                    coursePlanningService: container.coursePlanningService,
                    locationService: container.locationService,
                    cameraStateStore: container.cameraStateStore,
                    courseRepository: container.courseRepository
                )
                .opacity(selectedTab == .course ? 1 : 0)
                .allowsHitTesting(selectedTab == .course)
                .accessibilityHidden(selectedTab != .course)

                RunPage(
                    session: container.runSession,
                    recordRepository: container.runRecordRepository,
                    announcer: container.voiceAnnouncer
                )
                .opacity(selectedTab == .run ? 1 : 0)
                .allowsHitTesting(selectedTab == .run)
                .accessibilityHidden(selectedTab != .run)
            }

            // 러닝 플로우(시작~요약 닫기 전) 동안 탭바 자체를 제거 — 킥오프 §2.2.
            // RunSession은 @Observable이라 state 변화가 body를 다시 평가한다.
            if !AppTab.isTabBarHidden(runState: container.runSession.state) {
                TraceTabBar(selection: $selectedTab)
            }
        }
    }
}
