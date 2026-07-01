import Foundation
import Observation

@MainActor
@Observable
final class CourseEditSession {
    // segments 배열은 "공간적 순서"(경로상 위치)이고, order는 "시간순 attach 이력"이다.
    // prepend(맨 앞 삽입) 시 두 순서가 갈라지므로 undo/색상은 order를 따라야 한다.
    private struct Entry {
        let id: UUID
        let order: Int
        let segment: CourseSegment
    }

    private var entries: [Entry] = []
    private var nextOrder = 0

    var segments: [CourseSegment] { entries.map(\.segment) }

    // segments와 같은 순서로 정렬된 attach 순번(생성 순서). 색상 등 identity 기반 렌더링에 사용.
    var segmentColorKeys: [Int] { entries.map(\.order) }

    var course: PlannedCourse? {
        entries.isEmpty ? nil : PlannedCourse(segments: segments)
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
            append(newSegment)
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
            append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
        } else {
            if needsGap(from: orientedLast, to: existingStart) {
                let gap = try await service.route(from: orientedLast, to: existingStart)
                combinedCoords = oriented.coordinates + Array(gap.coordinates.dropFirst())
                combinedDistance += gap.distanceMeters
            }
            prepend(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
        }
    }

    func undo() {
        guard let mostRecent = entries.max(by: { $0.order < $1.order }) else { return }
        entries.removeAll { $0.id == mostRecent.id }
    }

    func clear() {
        entries = []
        nextOrder = 0
    }

    // MARK: - Private

    private func append(_ segment: CourseSegment) {
        entries.append(Entry(id: UUID(), order: nextOrder, segment: segment))
        nextOrder += 1
    }

    private func prepend(_ segment: CourseSegment) {
        entries.insert(Entry(id: UUID(), order: nextOrder, segment: segment), at: 0)
        nextOrder += 1
    }

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
