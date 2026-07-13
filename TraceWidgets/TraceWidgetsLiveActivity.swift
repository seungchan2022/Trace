import ActivityKit
import SwiftUI
import WidgetKit

/// Task 8에서 실제 잠금화면/Dynamic Island UI를 구현한다. 지금은 타깃이 빌드되도록
/// 최소한의 골격만 둔다.
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { _ in
            EmptyView()
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}
