import Foundation

enum RunPaceFormatter {
    /// 초/km → `5'32"`. nil·0 이하·60분/km 초과는 `--'--"`.
    ///
    /// 주의: 위젯 타깃의 RunLiveActivityWidget.paceText(_:)에 동일 로직이 중복되어 있다
    /// (위젯 타깃은 이 타입을 볼 수 없어 Target Membership 없이는 재사용 불가). 여기를 고치면
    /// 그쪽도 같이 고칠 것.
    static func string(secondsPerKm: Double?) -> String {
        guard let seconds = secondsPerKm, seconds > 0, seconds < 3600 else { return "--'--\"" }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d'%02d\"", minutes, remainder)
    }
}
