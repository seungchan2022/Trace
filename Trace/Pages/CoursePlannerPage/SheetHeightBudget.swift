import Foundation

// 바텀시트 높이 예산 — 뷰에서 분리한 순수 계산.
//
// 이 계산은 틀려도 경고 하나 없이 조용히 시트 높이만 바꾸기 때문에(2026-07-21 회귀에서
// 62pt가 소리 없이 사라졌다) 뷰 안의 계산식으로 두지 않고 테스트 가능한 자리로 뺐다.
enum SheetHeightBudget {
    /// 풀 디텐트 시트가 차지할 수 있는 최대 높이.
    ///
    /// **`pageHeight`에서 상단 안전영역을 빼지 않는다.** `pageHeight`는 GeometryReader가
    /// 보고하는 "부모가 제안한 크기"라 이미 안전영역이 제외된 값이다 — 한 번 더 빼면 시트가
    /// 그만큼 짧아져 풀 디텐트에서 topBar를 덮지 못한다(커밋 4772313 회귀: 앵커를
    /// mapHeight→pageHeight로 바꾸면서, mapHeight(안전영역 포함) 시절에만 옳던
    /// `- topSafeAreaInset` 항이 남아 62pt를 두 번 뺐다).
    static func maxSheetHeight(pageHeight: CGFloat, topMargin: CGFloat) -> CGFloat {
        max(0, pageHeight - topMargin)
    }

    /// 예산 안에서 구간 리스트가 쓸 수 있는 높이.
    /// `max(0,)`은 측정 전 기본값 조합에서 음수 프레임 경고를 막는 가드.
    static func listHeight(
        maxSheetHeight: CGFloat, grabberHeight: CGFloat, headerHeight: CGFloat
    ) -> CGFloat {
        max(0, maxSheetHeight - grabberHeight - headerHeight)
    }
}
