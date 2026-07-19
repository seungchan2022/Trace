import SwiftUI

// 루트 커스텀 탭바 — 시스템 탭바는 iOS 26에서 글래스로 렌더되어 불투명 클래식 모양이
// 안 나오므로 직접 만든다 (킥오프 §2.4). 풀폭 불투명 + 아이콘·한글 라벨 (ui-direction §1).
struct TraceTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // iPhone 가로모드에서 verticalSizeClass가 .compact — 고정 56pt 탭바가 낮은 화면
    // 높이 대비 비중이 커 보이는 문제 완화(세로 6.4% vs 가로 13.9%, 실기기 QA 2026-07-19).
    // iPad는 가로에서도 .regular라 영향 없음(의도된 동작).
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab // 트랜지션 없음(즉시 전환)이 확정 기본값 — ui-direction §1
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: isCompactHeight ? 18 : 22, weight: .medium))
                        Text(tab.title)
                            .font(DesignToken.Typography.chip)
                    }
                    .foregroundStyle(
                        selection == tab ? DesignToken.Color.accent : DesignToken.Color.ink2
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, isCompactHeight ? 4 : 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                .accessibilityIdentifier("root.tab.\(tab.rawValue)")
            }
        }
        .background {
            // 위쪽 헤어라인 + 불투명 Surface. 홈 인디케이터 영역까지 배경 확장 —
            // 커스텀 시트 배경(ignoresSafeArea bottom)과 같은 패턴.
            DesignToken.Color.surface
                .overlay(alignment: .top) {
                    DesignToken.Color.ink2.opacity(0.2)
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityIdentifier("root.tabBar")
    }
}
