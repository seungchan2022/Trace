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
        let placedAtFront: Bool
        let segment: CourseSegment
    }

    private var entries: [Entry] = []
    private var redoStack: [Entry] = []
    private var nextOrder = 0

    var segments: [CourseSegment] { entries.map(\.segment) }

    // segments와 같은 순서로 정렬된 attach 순번(생성 순서). 색상 등 identity 기반 렌더링에 사용.
    var segmentColorKeys: [Int] { entries.map(\.order) }

    var course: PlannedCourse? {
        entries.isEmpty ? nil : PlannedCourse(segments: segments)
    }

    var canRedo: Bool { !redoStack.isEmpty }

    static let connectionThresholdMeters: Double = 20

    // 이어붙이기 순서 규칙 (spec 규칙 1~4): 반전은 "출발점 쪽 시작 = 출발 방향 연장" 하나뿐.
    // 규칙 4는 시작점 "단일 점"만 두 끝점과 최근접 비교한다(탭 nearestEndpoint와 동일한 <=) —
    // 스트로크 양끝 4쌍 비교·끝점 비교는 왕복 모호성을 재발시키므로 금지 (MVP9 → MVP10 스펙).
    // 1 attach = 1 segment 추가 = undo 1번에 완전 제거
    func attach(
        _ newSegment: CourseSegment,
        using service: CoursePlanningServiceProtocol
    ) async throws {
        guard let existing = course,
              let existingStart = existing.coordinates.first,
              let existingEnd = existing.coordinates.last,
              let newStart = newSegment.coordinates.first else {
            append(newSegment)
            return
        }

        let threshold = Self.connectionThresholdMeters
        let isClosedCourse = existingStart.distanceMeters(to: existingEnd) <= threshold
        let startsNearEnd = newStart.distanceMeters(to: existingEnd) <= threshold
        let startsNearStart = newStart.distanceMeters(to: existingStart) <= threshold

        // 규칙 3: 열린 코스의 출발점에서 시작한 구간만 "출발 방향 연장" — 반전 prepend.
        // 반전 후 끝 좌표 = 원래 시작점 ≈ 기존 출발점이므로 gap 라우팅이 필요 없다.
        if !isClosedCourse, !startsNearEnd, startsNearStart {
            prepend(newSegment.reversed())
            return
        }

        // 규칙 4(출발점 쪽): 규칙 1~3이 모두 안 걸린 원거리 스트로크는 시작점을 두 끝점과
        // 최근접 비교해, 출발점 쪽(등거리 포함)이면 규칙 3의 원거리 확장 — 반전 prepend + gap.
        // 진입 조건상 시작점-출발점 거리 > threshold이므로 gap 라우팅이 항상 필요하다.
        if !isClosedCourse, !startsNearEnd, !startsNearStart,
           newStart.distanceMeters(to: existingStart) <= newStart.distanceMeters(to: existingEnd) {
            let gap = try await service.route(from: newStart, to: existingStart)
            let reversed = newSegment.reversed()
            prepend(makeMerged(
                like: newSegment,
                coordinates: reversed.coordinates + Array(gap.coordinates.dropFirst()),
                distance: reversed.distanceMeters + gap.distanceMeters
            ))
            return
        }

        // 규칙 1·2·4(도착점 쪽): 그린 그대로 도착점 뒤에 append (필요 시 gap 라우팅)
        var combinedCoords = newSegment.coordinates
        var combinedDistance = newSegment.distanceMeters
        if needsGap(from: existingEnd, to: newStart) {
            let gap = try await service.route(from: existingEnd, to: newStart)
            combinedCoords = gap.coordinates + Array(newSegment.coordinates.dropFirst())
            combinedDistance += gap.distanceMeters
        }
        append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
    }

    func undo() {
        guard let mostRecent = entries.max(by: { $0.order < $1.order }) else { return }
        entries.removeAll { $0.id == mostRecent.id }
        redoStack.append(mostRecent)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        if entry.placedAtFront {
            entries.insert(entry, at: 0)
        } else {
            entries.append(entry)
        }
    }

    func clear() {
        entries = []
        redoStack = []
        nextOrder = 0
    }

    // MARK: - Private

    private func append(_ segment: CourseSegment) {
        entries.append(Entry(id: UUID(), order: nextOrder, placedAtFront: false, segment: segment))
        nextOrder += 1
        redoStack = []
    }

    private func prepend(_ segment: CourseSegment) {
        entries.insert(Entry(id: UUID(), order: nextOrder, placedAtFront: true, segment: segment), at: 0)
        nextOrder += 1
        redoStack = []
    }

    private func needsGap(from: CourseCoordinate, to: CourseCoordinate) -> Bool {
        from.distanceMeters(to: to) > Self.connectionThresholdMeters
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
