import Foundation

/// 경과 시간 "H:MM:SS" 표기 — 요약 패널·기록 목록/상세가 같은 형식을 쓴다
enum RunDurationFormatter {
    static func string(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
