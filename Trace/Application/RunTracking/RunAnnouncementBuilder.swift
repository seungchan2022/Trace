import Foundation

/// 발화 문구 조립 — 순수 문자열 로직(스펙 §3.3 초안 문구).
/// 표시용 포맷터(RunPaceFormatter 등)와 달리 소리 내어 읽는 한국어 문장을 만든다.
enum RunAnnouncementBuilder {
    static let start = "러닝을 시작합니다"
    static let pause = "일시정지합니다"
    static let resume = "재개합니다"
    /// 시작 카운트다운 낭독 순서(스펙 §1.1·§1.3, 사용자 확정: 숫자 낭독)
    static let countdown = ["삼", "이", "일"]

    static let goalHalf = "절반 왔습니다"

    /// "목표를 달성했습니다. 5킬로미터, 29분 10초, 평균 페이스 5분 50초" — 페이스 절은 finish와 동일 생략 규칙(스펙 §1.3)
    static func goalAchieved(
        distanceMeters: Double, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?
    ) -> String {
        var text = "목표를 달성했습니다. \(spokenDistance(distanceMeters)), \(spokenDuration(totalSeconds))"
        if let pace = spokenPace(averagePaceSecondsPerKm) {
            text += ", 평균 페이스 \(pace)"
        }
        return text
    }

    /// "3킬로미터. 총 시간 18분 30초. 평균 페이스 6분 10초"
    static func kilometer(km: Int, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?) -> String {
        var text = "\(km)킬로미터. 총 시간 \(spokenDuration(totalSeconds))"
        if let pace = spokenPace(averagePaceSecondsPerKm) {
            text += ". 평균 페이스 \(pace)"
        }
        return text
    }

    /// "러닝을 종료합니다. 총 5.2킬로미터, 31분 40초, 평균 페이스 6분 5초"
    static func finish(distanceMeters: Double, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?) -> String {
        var text = "러닝을 종료합니다. 총 \(spokenDistance(distanceMeters)), \(spokenDuration(totalSeconds))"
        if let pace = spokenPace(averagePaceSecondsPerKm) {
            text += ", 평균 페이스 \(pace)"
        }
        return text
    }

    /// 5200 → "5.2킬로미터", 5000 → "5킬로미터" (0.1km 반올림, 정수면 소수점 생략)
    static func spokenDistance(_ meters: Double) -> String {
        let roundedKm = (meters / 100).rounded() / 10
        if roundedKm == roundedKm.rounded() {
            return "\(Int(roundedKm))킬로미터"
        }
        return String(format: "%.1f킬로미터", roundedKm)
    }

    /// 1110 → "18분 30초", 3725 → "1시간 2분 5초", 300 → "5분", 45 → "45초"
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)시간") }
        if minutes > 0 { parts.append("\(minutes)분") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs)초") }
        return parts.joined(separator: " ")
    }

    /// 초/km → "6분 10초". nil·0 이하·60분/km 이상은 nil(문장에서 절 생략 — 표시 규칙과 동일 경계)
    static func spokenPace(_ secondsPerKm: Double?) -> String? {
        guard let pace = secondsPerKm, pace > 0, pace < 3600 else { return nil }
        return spokenDuration(pace)
    }
}
