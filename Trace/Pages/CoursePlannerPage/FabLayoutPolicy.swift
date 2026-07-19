import Foundation

// 플로팅 버튼(undo/redo/clear/현위치)의 시트 연동 정책 — 방향 스펙 §2.
// 시트가 오르면 같이 오르고, 커질수록 페이드아웃, 풀 시트에서 소멸.
// (2026-07-13의 "collapsed 외 전부 숨김" 결정을 MVP16 방향 스펙이 대체한다.)
enum FabLayoutPolicy {
    static func opacity(for detent: SheetDetent) -> Double {
        switch detent {
        case .collapsed: return 1.0
        case .medium: return 0.55
        case .full: return 0.0
        }
    }

    static func showsEditingGroup(hasCourse: Bool, canUndo: Bool, canRedo: Bool) -> Bool {
        hasCourse || canUndo || canRedo
    }

    static func bottomPadding(
        detent: SheetDetent, collapsedSheetHeight: CGFloat, mediumListHeight: CGFloat
    ) -> CGFloat {
        switch detent {
        case .collapsed:
            return collapsedSheetHeight + 16
        case .medium, .full:
            // full은 opacity 0으로 숨김 — 페이드 아웃 중 위치 점프가 없도록 medium 앵커 유지
            return collapsedSheetHeight + mediumListHeight + 16
        }
    }
}
