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
        let anchorID: UUID?   // 왕복 엔트리의 redo 재삽입 기준(대상 구간 id). 일반 엔트리는 nil.
        // anchorID가 있을 때만 의미 있음: true = anchor 바로 앞(코스 앞쪽 끝 왕복),
        // false = anchor 바로 뒤(코스 뒤쪽 끝 왕복).
        let anchorInsertsBefore: Bool
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
    static let maxTotalCoordinates = 20_000

    private var totalCoordinateCount: Int {
        entries.reduce(0) { $0 + $1.segment.coordinates.count }
    }

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
              let newStart = newSegment.coordinates.first,
              let newEnd = newSegment.coordinates.last else {
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

        // 규칙 3'/4'(근접 끝점 대칭): 규칙 1~3이 모두 안 걸린 경우, 시작점은 두 기존 핀
        // 모두에서 멀더라도 스트로크 끝점(손을 뗀 지점)이 근접할 수 있다 — 반대 방향으로
        // 그리기(먼 지점 → 핀 근처)가 그 경우다. 근접(threshold 이내) 판정에 한해서만
        // 끝점을 대칭적으로 쓰고, 원거리 비교(아래 규칙 4)는 시작점만 쓰는 기존 규칙을
        // 그대로 둔다. 두 기존 핀이 20~40m 정도로 가까운 "거의 닫힌 루프"에서는 끝점이
        // 양쪽 근접 범위에 동시에 들 수 있는데, 이때 절대 임계값 두 개를 독립으로 체크하면
        // 코드 순서상 먼저 걸리는 쪽이 실제 상대 거리와 무관하게 이겨버려 손 뗀 위치가
        // 1m만 달라져도 결과가 정반대로 뒤집힐 수 있다(MVP9가 제거한 것과 같은 불안정성).
        // 그래서 두 조건이 동시에 참이면 하나의 결정으로 묶어, nearestEndpoint/규칙4와
        // 동일한 마진 없는 <= 상대 비교로 결정론적으로 정한다.
        let endNearStart = newEnd.distanceMeters(to: existingStart) <= threshold
        let endNearEnd = newEnd.distanceMeters(to: existingEnd) <= threshold
        if !isClosedCourse, !startsNearEnd, !startsNearStart, endNearStart || endNearEnd {
            if endNearStart,
               !endNearEnd || newEnd.distanceMeters(to: existingStart) <= newEnd.distanceMeters(to: existingEnd) {
                // 끝점 ≈ 출발점(또는 상대적으로 더 가까움) → 반전 없이 그대로 prepend.
                // 스트로크의 첫 좌표(진짜 새 지점)가 코스의 새 출발점이 된다. gap 불필요.
                prepend(newSegment)
            } else {
                // 끝점 ≈ 도착점(위 조건에서 밀림) → 반전 후 append.
                // 반전하면 시작 ≈ 도착점이므로 gap 불필요, 원래 첫 좌표가 새 도착점이 된다.
                append(newSegment.reversed())
            }
            return
        }

        // 규칙 4(원거리, 방향 무관 대칭 처리): 열린 코스이고 시작점이 이미 근접 판정에
        // 걸리지 않은 경우에만 적용된다. 이 게이트 안에서는 스트로크의 양끝이 두 기존 핀
        // 모두에서 threshold보다 멀다는 것이 보장된다(근접 판정이 위에서 전부 가로챔).
        // 따라서 "어느 끝이 어느 핀에 더 가까운가"를 양끝 전체에서 비교해도, MVP9가 걱정한
        // 왕복 모호성(양끝이 동시에 핀 근처에 있는 경우)은 애초에 이 지점에 도달할 수 없다.
        // 닫힌 코스(규칙 1: 무조건 append)는 이 게이트 밖이므로 영향받지 않는다.
        if !isClosedCourse, !startsNearEnd, !startsNearStart {
            try await attachFarCase(
                newSegment,
                newStart: newStart,
                newEnd: newEnd,
                existingBounds: (existingStart, existingEnd),
                using: service
            )
            return
        }

        // 규칙 1·2(닫힌 코스 / 시작점이 도착점 근접): 그린 그대로 도착점 뒤에 append (필요 시 gap 라우팅)
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
        // 왕복 엔트리는 anchor 옆으로 복원 — anchor는 LIFO 순서상 항상 먼저 복원돼 있다 (스펙 §4).
        // anchorInsertsBefore로 anchor 앞/뒤 중 원래 삽입 위치를 재현한다.
        // anchor 미발견 시 placedAtFront/append 폴백 (스펙 증명상 도달 불가, 방어적).
        if let anchorID = entry.anchorID,
           let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }) {
            entries.insert(entry, at: entry.anchorInsertsBefore ? anchorIndex : anchorIndex + 1)
        } else if entry.placedAtFront {
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

    // MARK: - Round Trip (MVP11 스펙 §4, 2026-07-08 정정)

    // 코스의 자유 끝(맨 앞 또는 맨 뒤) 구간에서만 왕복 가능하다. 중간 구간은 반대쪽이 다른
    // 구간과 이어져 있어, 그 구간만 되짚으면 연결이 끊긴다 — 안전하게 되짚을 수 있는 쪽은
    // 아무것도 이어지지 않은 자유 끝뿐이다 (실기기 QA 2026-07-08로 확정, 이전의 "역+정 병합"
    // 방식은 거리가 3×가 되고 코스가 끊기지 않는 대신 항상 원래 끝점에 머물러 사용자 의도와
    // 어긋났다 — 폐기).
    func canInsertRoundTrip(afterOrder order: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.order == order }),
              index == 0 || index == entries.count - 1 else { return false }
        let n = entries[index].segment.coordinates.count
        guard n >= 2 else { return false }
        return totalCoordinateCount + n <= Self.maxTotalCoordinates
    }

    // 대상 구간(A→B)의 역방향(B→A)만 만들어 자유 끝에 붙인다 — 거리는 대상 구간과 동일(1×),
    // 코스 총 거리는 그 구간만큼 늘어 결과적으로 2×가 된다. 뒤쪽 끝이면 뒤에 append, 앞쪽
    // 끝이면 앞에 prepend — 구간이 하나뿐이면(양쪽 다 해당) append로 취급한다.
    func insertRoundTrip(afterOrder order: Int) {
        guard canInsertRoundTrip(afterOrder: order),
              let index = entries.firstIndex(where: { $0.order == order }) else { return }
        let target = entries[index]
        let reversed = target.segment.reversed()
        let roundTrip = CourseSegment.roundTrip(
            coordinates: reversed.coordinates,
            distanceMeters: reversed.distanceMeters
        )
        let isBackMost = index == entries.count - 1
        let newEntry = Entry(
            id: UUID(), order: nextOrder, placedAtFront: false,
            anchorID: target.id, anchorInsertsBefore: !isBackMost,
            segment: roundTrip
        )
        entries.insert(newEntry, at: isBackMost ? index + 1 : index)
        nextOrder += 1
        redoStack = []
    }

    // MARK: - Whole Course Round Trip (2026-07-08 추가)

    // 지금까지 그린 코스 전체를 뒤집어 맨 뒤에 이어붙인다 — 언제나 코스의 열린 끝(마지막 좌표)
    // 에서 시작하는 연산이라 별도 anchor 추적 없이 항상 연결이 유지된다(일반 append와 동일하게
    // undo/redo). 라우팅 재호출 없음(§4와 동일 원칙).
    func canInsertWholeCourseRoundTrip() -> Bool {
        guard let course, course.coordinates.count >= 2 else { return false }
        return totalCoordinateCount + course.coordinates.count <= Self.maxTotalCoordinates
    }

    func insertWholeCourseRoundTrip() {
        guard canInsertWholeCourseRoundTrip(), let course else { return }
        append(.roundTrip(coordinates: course.coordinates.reversed(), distanceMeters: course.distanceMeters))
    }

    // MARK: - Snapshot (초안 저장·복원, MVP11 스펙 §3)

    // 복원은 엔트리 id를 보존해야 한다 — append/prepend 재사용 시 id가 재발급되어
    // 왕복 anchor 참조가 끊긴다 (스펙 §3·§4).
    func snapshot() -> CourseDraft {
        CourseDraft(
            entries: entries.map {
                CourseDraft.Entry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore, segment: $0.segment
                )
            },
            nextOrder: nextOrder
        )
    }

    func restore(from draft: CourseDraft) {
        entries = draft.entries.map {
            Entry(
                id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore, segment: $0.segment
            )
        }
        nextOrder = draft.nextOrder
        redoStack = []
    }

    // 저장 코스 불러오기: 공간순 세그먼트에 시간순을 0부터 재부여 (undo = 공간순 마지막부터 제거)
    func load(segments: [CourseSegment]) {
        entries = segments.enumerated().map { index, segment in
            Entry(
                id: UUID(), order: index, placedAtFront: false,
                anchorID: nil, anchorInsertsBefore: false, segment: segment
            )
        }
        nextOrder = segments.count
        redoStack = []
    }

    // MARK: - Private

    private func append(_ segment: CourseSegment) {
        entries.append(Entry(
            id: UUID(), order: nextOrder, placedAtFront: false,
            anchorID: nil, anchorInsertsBefore: false, segment: segment
        ))
        nextOrder += 1
        redoStack = []
    }

    private func prepend(_ segment: CourseSegment) {
        entries.insert(Entry(
            id: UUID(), order: nextOrder, placedAtFront: true,
            anchorID: nil, anchorInsertsBefore: false, segment: segment
        ), at: 0)
        nextOrder += 1
        redoStack = []
    }

    private func needsGap(from: CourseCoordinate, to: CourseCoordinate) -> Bool {
        from.distanceMeters(to: to) > Self.connectionThresholdMeters
    }

    // 스트로크 양끝 중 threshold 밖에서 더 가까운 쪽을 anchor로 골라, 그 anchor를 기존 두
    // 끝점과 최근접 비교해 반전 prepend+gap 또는 그대로 append(+gap 필요 시)를 결정한다.
    // 호출 전제(호출부 규칙 4 주석 참고): 열린 코스이고 스트로크 양끝 모두 threshold 밖.
    private func attachFarCase(
        _ newSegment: CourseSegment,
        newStart: CourseCoordinate,
        newEnd: CourseCoordinate,
        existingBounds: (start: CourseCoordinate, end: CourseCoordinate),
        using service: CoursePlanningServiceProtocol
    ) async throws {
        let existingStart = existingBounds.start
        let existingEnd = existingBounds.end
        let startMin = min(
            newStart.distanceMeters(to: existingStart),
            newStart.distanceMeters(to: existingEnd)
        )
        let endMin = min(
            newEnd.distanceMeters(to: existingStart),
            newEnd.distanceMeters(to: existingEnd)
        )
        let anchorIsEnd = endMin < startMin
        let anchor = anchorIsEnd ? newEnd : newStart
        let effectiveSegment = anchorIsEnd ? newSegment.reversed() : newSegment

        // 출발점 쪽(등거리 포함): anchor는 항상 threshold 밖이므로 gap 라우팅이 항상 필요하다.
        if anchor.distanceMeters(to: existingStart) <= anchor.distanceMeters(to: existingEnd) {
            let gap = try await service.route(from: anchor, to: existingStart)
            let reversed = effectiveSegment.reversed()
            prepend(makeMerged(
                like: newSegment,
                coordinates: reversed.coordinates + Array(gap.coordinates.dropFirst()),
                distance: reversed.distanceMeters + gap.distanceMeters
            ))
            return
        }

        // 도착점 쪽: anchor 기준 그대로 append (이 게이트 안에서는 anchor가 항상 threshold
        // 밖이므로 아래 needsGap은 사실상 항상 참이다 — 구조를 default append 분기와
        // 맞추기 위해 그대로 둔다)
        var combinedCoords = effectiveSegment.coordinates
        var combinedDistance = effectiveSegment.distanceMeters
        if needsGap(from: existingEnd, to: anchor) {
            let gap = try await service.route(from: existingEnd, to: anchor)
            combinedCoords = gap.coordinates + Array(effectiveSegment.coordinates.dropFirst())
            combinedDistance += gap.distanceMeters
        }
        append(makeMerged(like: newSegment, coordinates: combinedCoords, distance: combinedDistance))
    }

    private func makeMerged(
        like original: CourseSegment,
        coordinates: [CourseCoordinate],
        distance: Double
    ) -> CourseSegment {
        switch original {
        case .tapped: return .tapped(coordinates: coordinates, distanceMeters: distance)
        case .drawn:  return .drawn(coordinates: coordinates, distanceMeters: distance)
        case .roundTrip: return .roundTrip(coordinates: coordinates, distanceMeters: distance)
        }
    }
}
