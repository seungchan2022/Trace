import Foundation

// 구간 패널의 스크롤 정책 판정. 뷰에서 분리한 순수 함수 — 스펙의 "판정은 순수 함수로 분리해
// 유닛 테스트한다" 요구사항 (2026-07-02-course-ux-polish-design.md).
enum SegmentPanelLogic {
    /// 가장 최근에 attach된 구간(생성 순번 최대)의 배열 인덱스.
    /// prepend 시 배열 맨 앞이 최신일 수 있으므로 "마지막 행"이 아니라 colorKey 최대값으로 찾는다.
    static func latestIndex(colorKeys: [Int]) -> Int? {
        guard let maxKey = colorKeys.max() else { return nil }
        return colorKeys.firstIndex(of: maxKey)
    }

    /// 채팅 앱 방식 자동 스크롤: 사용자가 직전 최신 구간 근처를 보고 있을 때만 새 구간을 따라간다.
    /// - anchorIndex: 뷰포트에 보이는 행(스크롤 앵커)의 배열 인덱스. nil이면 스크롤 정보 없음 → 따라간다.
    /// - previousLatestIndex: 새 구간이 추가되기 전 최신 구간의 배열 인덱스.
    /// - tolerance: "근처"로 인정할 행 간격. 패널 뷰포트가 최대 6행 내외라 3이 기본.
    static func shouldAutoScroll(anchorIndex: Int?, previousLatestIndex: Int?, tolerance: Int = 3) -> Bool {
        guard let anchorIndex, let previousLatestIndex else { return true }
        return abs(anchorIndex - previousLatestIndex) <= tolerance
    }
}
