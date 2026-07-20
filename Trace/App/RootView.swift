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
            // GeometryReader는 자식 크기와 무관하게 항상 제안받은 크기를 보고하므로,
            // 자식(코스 ZStack)이 어떤 측정 오작동으로 부풀어도 VStack 배정량을 절대
            // 초과하지 않는다 — 가로에서 시트를 펼치면 코스 ZStack이 배정량(335)을 초과한
            // 높이(396)를 보고해 VStack이 중앙 오버플로로 탭바를 화면 아래로 밀어내던
            // 버그의 구조적 차단막(2026-07-20 실측). alignment .top: 잔여 내부 오버플로가
            // 위(topBar/상태바)가 아니라 아래(불투명 탭바 뒤)로만 향하게 한다.
            // .clipped()는 걸지 않는다 — 지도의 ignoresSafeArea 확장(상태바 밑 풀블리드)은
            // 의도된 동작이라 잘리면 안 된다.
            GeometryReader { proxy in
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
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }

            // 러닝 플로우(카운트다운~요약 닫기 전) 동안 탭바 자체를 제거 — 킥오프 §2.2.
            // RunSession은 @Observable이라 state 변화가 body를 다시 평가한다.
            if !AppTab.isTabBarHidden(runState: container.runSession.state) {
                TraceTabBar(selection: $selectedTab)
            }
        }
    }
}
