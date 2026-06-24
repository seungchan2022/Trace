import Foundation

struct StrokeAttachment: Equatable, Sendable {
    let direction: StrokeDirection
    let orientedStroke: [CourseCoordinate]
}

enum StrokeDirectionResolver {
    static func resolve(
        newStroke: [CourseCoordinate],
        existingCourseStart: CourseCoordinate?,
        existingCourseEnd: CourseCoordinate?
    ) -> StrokeAttachment {
        guard let courseStart = existingCourseStart, let courseEnd = existingCourseEnd else {
            return StrokeAttachment(direction: .initial, orientedStroke: newStroke)
        }
        guard let strokeStart = newStroke.first, let strokeEnd = newStroke.last else {
            return StrokeAttachment(direction: .initial, orientedStroke: newStroke)
        }

        // 4쌍 거리 비교
        let pairs: [(distance: Double, direction: StrokeDirection, needsReverse: Bool)] = [
            (strokeStart.distanceMeters(to: courseEnd), .append, false),   // stroke시작 → 경로끝: append, 그대로
            (strokeEnd.distanceMeters(to: courseEnd), .append, true),      // stroke끝 → 경로끝: append, 뒤집기
            (strokeEnd.distanceMeters(to: courseStart), .prepend, false),  // stroke끝 → 경로시작: prepend, 그대로
            (strokeStart.distanceMeters(to: courseStart), .prepend, true), // stroke시작 → 경로시작: prepend, 뒤집기
        ]

        guard let closest = pairs.min(by: { $0.distance < $1.distance }) else {
            // This should never happen since pairs always has 4 elements
            return StrokeAttachment(direction: .initial, orientedStroke: newStroke)
        }
        let oriented = closest.needsReverse ? newStroke.reversed() : newStroke
        return StrokeAttachment(direction: closest.direction, orientedStroke: Array(oriented))
    }
}
