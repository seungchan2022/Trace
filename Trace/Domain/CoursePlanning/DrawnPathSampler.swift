import Foundation

/// 손으로 그린 마커 좌표열을 최소 간격으로 다운샘플한다.
/// 라우팅 호출 수를 제한해 스로틀을 피하고, 시작/끝 좌표는 항상 보존한다.
enum DrawnPathSampler {
    static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate] {
        guard let first = raw.first else { return [] }
        var result = [first]
        var accumulated = 0.0
        var prev = first
        for point in raw.dropFirst() {
            accumulated += prev.distanceMeters(to: point)
            if accumulated >= minSpacingMeters {
                result.append(point)
                accumulated = 0.0
            }
            prev = point
        }
        if let last = raw.last, last != result.last {
            result.append(last)
        }
        return result
    }
}
