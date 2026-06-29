import Foundation
import Observation

@MainActor
@Observable
final class CourseEditSession {
    private(set) var segments: [CourseSegment] = []

    var course: PlannedCourse? {
        segments.isEmpty ? nil : PlannedCourse(segments: segments)
    }

    // 1 attach = 1 segment 추가 = undo 1번에 완전 제거
    func attach(
        _ newSegment: CourseSegment,
        using service: CoursePlanningServiceProtocol
    ) async throws {
        guard let existing = course,
              let existingStart = existing.coordinates.first,
              let existingEnd = existing.coordinates.last,
              let newStart = newSegment.coordinates.first,
              let newEnd = newSegment.coordinates.last else {
            segments.append(newSegment)
            return
        }

        let orientation = resolveOrientation(
            newStart: newStart, newEnd: newEnd,
            existingStart: existingStart, existingEnd: existingEnd
        )

        let oriented = orientation.needsReverse ? newSegment.reversed() : newSegment
        guard let orientedFirst = oriented.coordinates.first,
              let orientedLast = oriented.coordinates.last else { return }

        var combinedCoords = oriented.coordinates
        var combinedDistance = oriented.distanceMeters

        if orientation.attachesToEnd {
            if needsGap(from: existingEnd, to: orientedFirst) {
                let gap = try await service.route(from: existingEnd, to: orientedFirst)
                combinedCoords = gap.coordinates + Array(oriented.coordinates.dropFirst())
                combinedDistance += gap.distanceMeters
            }
            segments.append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
        } else {
            if needsGap(from: orientedLast, to: existingStart) {
                let gap = try await service.route(from: orientedLast, to: existingStart)
                combinedCoords = oriented.coordinates + Array(gap.coordinates.dropFirst())
                combinedDistance += gap.distanceMeters
            }
            segments.insert(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance), at: 0)
        }
    }

    func undo() {
        guard !segments.isEmpty else { return }
        segments.removeLast()
    }

    func clear() {
        segments = []
    }

    // MARK: - Private

    private struct AttachOrientation {
        let needsReverse: Bool
        let attachesToEnd: Bool
    }

    private func resolveOrientation(
        newStart: CourseCoordinate, newEnd: CourseCoordinate,
        existingStart: CourseCoordinate, existingEnd: CourseCoordinate
    ) -> AttachOrientation {
        let pairs: [(distance: Double, attachesToEnd: Bool, needsReverse: Bool)] = [
            (newStart.distanceMeters(to: existingEnd),   true,  false),
            (newEnd.distanceMeters(to: existingEnd),     true,  true),
            (newEnd.distanceMeters(to: existingStart),   false, false),
            (newStart.distanceMeters(to: existingStart), false, true),
        ]
        guard let closest = pairs.min(by: { $0.distance < $1.distance }) else {
            return AttachOrientation(needsReverse: false, attachesToEnd: true)
        }
        return AttachOrientation(needsReverse: closest.needsReverse, attachesToEnd: closest.attachesToEnd)
    }

    private func needsGap(from: CourseCoordinate, to: CourseCoordinate) -> Bool {
        from.distanceMeters(to: to) > 20
    }

    private func makeMerged(
        like original: CourseSegment,
        coordinates: [CourseCoordinate],
        distance: Double
    ) -> CourseSegment {
        switch original {
        case .tapped: return .tapped(coordinates: coordinates, distanceMeters: distance)
        case .drawn:  return .drawn(coordinates: coordinates, distanceMeters: distance)
        }
    }
}
