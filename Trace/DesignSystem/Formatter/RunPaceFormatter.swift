import Foundation

enum RunPaceFormatter {
    /// 초/km → `5'32"`. nil·0 이하·60분/km 초과는 `--'--"`.
    ///
    /// **앱 타깃과 위젯 타깃이 이 구현을 공유한다** — 위젯 멤버십은 프로젝트 파일의
    /// `TraceWidgetsExtension` 예외 목록에 있다(`pace-dedup`, 2026-09-03).
    ///
    /// 60분/km 상한의 근거는 **도입 시점에 기록되지 않았다.** 도입 커밋 `685ea3c`는 러닝 탭
    /// 4상태 UI를 한꺼번에 만든 커밋이라 이 값을 설명하지 않는다. 걷기도 보통 10~15분/km이므로
    /// 넉넉한 sanity bound로 보이며, 실사용에서 상한에 닿은 적은 관측되지 않았다.
    /// 아주 느린 활동(하이킹 등)을 지원하게 되면 이 값을 다시 정해야 한다.
    static func string(secondsPerKm: Double?) -> String {
        guard let seconds = secondsPerKm, seconds > 0, seconds < 3600 else { return "--'--\"" }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d'%02d\"", minutes, remainder)
    }
}
