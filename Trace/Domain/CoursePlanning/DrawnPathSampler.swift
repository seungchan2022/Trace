import Foundation

/// 손으로 그린 마커 좌표열을 최소 간격으로 다운샘플한다.
/// 라우팅 호출 수를 제한해 스로틀을 피하고, 시작/끝 좌표는 항상 보존한다.
enum DrawnPathSampler {
    static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate] {
        guard var last = raw.first else { return [] }
        var result = [last]
        for point in raw.dropFirst() where last.distanceMeters(to: point) >= minSpacingMeters {
            result.append(point)
            last = point
        }
        if let actualLast = raw.last, actualLast != last {
            result.append(actualLast)
        }
        return result
    }
}
