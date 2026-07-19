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
        // 카운트다운(아직 idle)이 끝나 트래킹이 실제로 시작되는 순간, 사용자가 다른 탭에
        // 가 있었다면 탭바가 사라지기 전에 러닝 탭으로 데려온다 — 킥오프 §2.2의 "러닝 중
        // 탭 전환 진입점 제거"는 항상 러닝 화면을 보고 있다는 전제인데, 카운트다운 중(아직
        // idle이라 탭 전환 가능)에 다른 탭으로 이동해뒀다가 트래킹이 시작되면 탭바 없이
        // 그 탭에 갇히는 문제가 실기기 QA에서 발견됐다(2026-07-20).
        .onChange(of: container.runSession.state) { _, newState in
            if AppTab.isTabBarHidden(runState: newState) {
                selectedTab = .run
            }
        }
    }
}
