import XCTest
@testable import Trace

@MainActor
final class CourseEditSessionTests: XCTestCase {
    private let A = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    private let B = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    private let C = CourseCoordinate(latitude: 37.52, longitude: 127.00)
    private let D = CourseCoordinate(latitude: 37.53, longitude: 127.00)

    // MARK: - reversed()

    func testReversedTapped() {
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [B, A])
        XCTAssertEqual(rev.distanceMeters, 100)
    }

    func testReversedDrawn() {
        let seg = CourseSegment.drawn(coordinates: [A, B, C], distanceMeters: 200)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [C, B, A])
    }

    // MARK: - attach: no existing course

    func testAttachFirstSegment_appendsDirectly() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        try await session.attach(seg, using: service)
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.segments.first?.coordinates.first, A)
        XCTAssertEqual(session.segments.first?.coordinates.last, B)
        XCTAssertEqual(service.routeCallCount, 0, "gap 라우팅 없어야 함")
    }

    // MARK: - attach: append (new start near existing end)

    func testAttach_appendNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: B→C (start near existing end B → append, no gap)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [near_B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A)
    }

    // MARK: - attach: 규칙 3 — 출발점에서 시작한 구간은 반전 prepend (유일한 반전)

    func testAttach_startNearExistingStart_reversePrepends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: near_B→A (출발점 B에서 시작해 바깥으로 그림) → 반전 prepend → 코스 A→…→C
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [near_B, A], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "반전 prepend로 코스 시작이 A여야 함")
        XCTAssertEqual(service.routeCallCount, 0, "출발점 근접이므로 gap 라우팅 없어야 함")
    }

    // MARK: - attach: 규칙 4 — 양 끝점 모두에서 먼 스트로크는 그린 그대로 도착점 gap append

    func testAttach_farStroke_appendsAsDrawnWithGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: C→D (양 끝점 모두에서 멂) → 도착점 B에서 C로 gap 라우팅 + 그린 그대로 append
        try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.last, D, "그린 방향 그대로여야 함 (반전 금지)")
        XCTAssertEqual(service.routeCallCount, 1, "gap 라우팅 1회")
    }

    // MARK: - attach: 새 규칙 4 — 원거리 스트로크 최근접 끝점 비교 (MVP10 마일스톤 4)

    /// 원거리 시작점이 출발점에 명백히 더 가까움 → 반전 prepend + gap 병합 (스펙 QA 케이스 324m vs 1241m 축소판)
    func testAttach_farStroke_nearerToStart_reversePrependsWithGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C (출발 B, 도착 C)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: P→A, P는 B에서 ~555m·C에서 ~1,665m (양쪽 임계값 밖, 출발점 쪽)
        let P = CourseCoordinate(latitude: 37.505, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P, A], distanceMeters: 500), using: service)

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "반전 prepend로 코스 시작이 A여야 함")
        XCTAssertEqual(session.course?.coordinates.last, C, "도착점은 그대로 C")
        XCTAssertEqual(service.routeCallCount, 1, "출발점 쪽 gap 라우팅 1회")
        // 병합 세그먼트: reversed(stroke) + gap(P→B).dropFirst() = [A, P] + [B]
        XCTAssertEqual(session.segments.first?.coordinates, [A, P, B])
        XCTAssertEqual(session.segments.first?.distanceMeters, 600, "스트로크 500 + gap 100")
    }

    /// near-tie 경계 (출발점 쪽): 이등분선보다 ~11m 출발점 쪽 → 결정론적으로 prepend
    func testAttach_nearTieBoundary_startSide_prepends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→C (이등분선 = 37.51)
        try await session.attach(.tapped(coordinates: [A, C], distanceMeters: 100), using: service)
        // New: P1→D, P1은 A에서 ~1,099m·C에서 ~1,121m (근소하게 출발점 쪽)
        let P1 = CourseCoordinate(latitude: 37.5099, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P1, D], distanceMeters: 300), using: service)

        XCTAssertEqual(session.course?.coordinates.first, D, "출발점 쪽 판정 → 반전 prepend → 시작이 D")
        XCTAssertEqual(session.course?.coordinates.last, C)
    }

    /// near-tie 경계 (도착점 쪽): 이등분선보다 ~11m 도착점 쪽 → 결정론적으로 append
    func testAttach_nearTieBoundary_endSide_appends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→C
        try await session.attach(.tapped(coordinates: [A, C], distanceMeters: 100), using: service)
        // New: P2→D, P2는 A에서 ~1,121m·C에서 ~1,099m (근소하게 도착점 쪽)
        let P2 = CourseCoordinate(latitude: 37.5101, longitude: 127.00)
        try await session.attach(.drawn(coordinates: [P2, D], distanceMeters: 300), using: service)

        XCTAssertEqual(session.course?.coordinates.first, A, "도착점 쪽 판정 → 출발점 불변")
        XCTAssertEqual(session.course?.coordinates.last, D, "그린 그대로 도착점 뒤 append")
    }

    /// 닫힌 코스 + 원거리 스트로크 → 여전히 append (규칙 1 선점 = 진입 조건 게이트 검증)
    func testAttach_closedCourse_farStroke_stillAppends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 닫힌 코스 구성: A→B, B근처→A근처 (첫·끝 좌표 ≤20m)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
        // New: E→C, E는 A 남쪽 ~1,110m — 닫힌 코스 양끝 어디서도 멀지만 출발점 A에 근소하게 더 가까움.
        // 비교가 게이트 없이 실행되면 prepend로 새어 규칙 1이 깨진다.
        let E = CourseCoordinate(latitude: 37.49, longitude: 127.00)
        try await session.attach(.tapped(coordinates: [E, C], distanceMeters: 100), using: service)

        XCTAssertEqual(session.course?.coordinates.first, A, "닫힌 코스는 무조건 append — 출발점 불변")
        XCTAssertEqual(session.course?.coordinates.last, C)
    }

    // MARK: - attach: 규칙 3'/4' — 근접 끝점 대칭 처리 (실기기 QA 전 스크린샷에서 발견한 버그 수정)

    /// 실기기 스크린샷에서 발견된 버그의 회귀 테스트: 스트로크를 반대 방향(먼 지점 → 출발점
    /// 근처)으로 그으면, 끝점 근접을 못 보던 옛 코드는 이걸 원거리 규칙 4로 흘려보내 불필요한
    /// gap을 만들고 마커를 옛 위치(출발점) 근처에 남겼다. 끝점 ≈ 출발점이므로 gap 없이 그대로
    /// prepend되어, 스트로크의 진짜 새 지점(A)이 코스의 새 출발점이 되어야 한다.
    func testAttach_reportedBug_strokeEndsNearStart_prependsUnreversedNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C (출발 B, 도착 C)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: A→near_B. A는 B·C 양쪽에서 멂(≈1112m·≈2224m), near_B는 출발점 B에서 ≈11.1m
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.drawn(coordinates: [A, near_B], distanceMeters: 500), using: service)

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "먼 지점 A가 새 출발점이어야 함(옛 위치 B 근처에 남으면 안 됨)")
        XCTAssertEqual(session.course?.coordinates.last, C, "도착점은 그대로 C")
        XCTAssertEqual(service.routeCallCount, 0, "끝점이 이미 출발점과 근접하므로 gap 불필요")
        XCTAssertEqual(session.segments.first?.coordinates, [A, near_B], "반전 없이 그대로 prepend되어야 함")
    }

    /// 대칭 케이스(도착점 쪽): 스트로크가 먼 지점에서 시작해 도착점 근처에서 끝나면 반전 후
    /// append되어, 스트로크의 진짜 새 지점(D)이 코스의 새 도착점이 되어야 한다.
    func testAttach_symmetric_strokeEndsNearEnd_appendsReversedNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B (출발 A, 도착 B)
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: D→near_B. D는 A·B 양쪽에서 멀고(≈3336m·≈2224m), near_B는 도착점 B에서 ≈11.1m
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.drawn(coordinates: [D, near_B], distanceMeters: 500), using: service)

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "출발점 불변")
        XCTAssertEqual(session.course?.coordinates.last, D, "먼 지점 D가 새 도착점이어야 함")
        XCTAssertEqual(service.routeCallCount, 0, "끝점이 이미 도착점과 근접하므로 gap 불필요")
        XCTAssertEqual(session.segments.last?.coordinates, [near_B, D], "반전 후 append되어야 함")
    }

    /// 어드바이저 리뷰에서 발견된 반례 클래스: 기존 출발·도착점이 20~40m 정도로 가까운
    /// "거의 닫힌 루프"(공식 닫힌 코스 20m 컷오프는 안 넘음)에서, 스트로크 끝점이 양쪽
    /// 임계값(20m) 안에 동시에 든다. 절대 임계값 두 개를 독립으로 체크하면 코드 순서상
    /// 먼저 걸리는 쪽이 실제 상대 거리와 무관하게 이겨버려, 3배 더 가까운 핀이 있어도
    /// 결과가 틀릴 수 있다 — 상대 비교라야 올바른(더 가까운) 쪽으로 붙는다.
    func testAttach_nearClosedLoop_endNearBothPins_attachesToGenuinelyCloserPin() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→A2, A2는 A 북쪽 ≈24.46m (20m 닫힌 코스 컷오프 밖이지만 근접)
        let A2 = CourseCoordinate(latitude: A.latitude + 0.00022, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [A, A2], distanceMeters: 100), using: service)
        // New: C→P. C는 A·A2 양쪽에서 멀고(≈2224m·≈2199m),
        // P는 A에서 ≈18.35m·A2에서 ≈6.12m — 둘 다 20m 이내지만 A2가 정확히 3배 더 가까움
        let P = CourseCoordinate(latitude: A.latitude + 0.000165, longitude: A.longitude)
        try await session.attach(.drawn(coordinates: [C, P], distanceMeters: 500), using: service)

        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "출발점은 그대로 A — 먼저 체크되는 조건이 이겨서는 안 됨")
        XCTAssertEqual(session.course?.coordinates.last, C, "3배 더 가까운 도착점(A2) 쪽에 붙어 C가 새 도착점이어야 함")
        XCTAssertEqual(service.routeCallCount, 0)
    }

    /// 근접-루프 near-tie 안정성: 두 후보점이 ≈0.46m 차이로 "실제로 더 가까운 핀"이
    /// 뒤바뀌면(A쪽 12.00m vs A2쪽 12.463m, 그리고 그 반대) 결과도 정확히 그 방향을 따라
    /// 뒤바뀌어야 한다 — 코드 순서에 고정된 답이 아니라 실제 상대 거리를 따른다는 것의 직접
    /// 검증. (브리프의 "동일 방향 유지" 변형 대신, 상대 거리에 따라 결과가 정확히 반대로
    /// 뒤바뀌는 것을 확인하는 형태를 택함 — 이 쪽이 "순서 비의존"을 더 직접적으로 검증한다.)
    func testAttach_nearClosedLoop_nearTie_resultFollowsTrueCloserSide() async throws {
        let A2 = CourseCoordinate(latitude: A.latitude + 0.00022, longitude: A.longitude)

        // Pn: A에서 ≈12.00m·A2에서 ≈12.463m (출발점 쪽이 더 가까움) → 반전 없이 prepend
        let startSideSession = CourseEditSession()
        let startSideService = StubCourseService()
        try await startSideSession.attach(.tapped(coordinates: [A, A2], distanceMeters: 100), using: startSideService)
        let Pn = CourseCoordinate(latitude: A.latitude + 0.00010791859271, longitude: A.longitude)
        try await startSideSession.attach(.drawn(coordinates: [C, Pn], distanceMeters: 500), using: startSideService)
        XCTAssertEqual(startSideSession.course?.coordinates.first, C, "출발점 쪽이 더 가까우므로 C가 새 출발점")
        XCTAssertEqual(startSideSession.course?.coordinates.last, A2, "도착점 A2는 불변")

        // Pm: A에서 ≈12.460m·A2에서 ≈12.003m (도착점 쪽이 더 가까움) → 반전 후 append
        let endSideSession = CourseEditSession()
        let endSideService = StubCourseService()
        try await endSideSession.attach(.tapped(coordinates: [A, A2], distanceMeters: 100), using: endSideService)
        let Pm = CourseCoordinate(latitude: A.latitude + 0.0001120554721, longitude: A.longitude)
        try await endSideSession.attach(.drawn(coordinates: [C, Pm], distanceMeters: 500), using: endSideService)
        XCTAssertEqual(endSideSession.course?.coordinates.first, A, "출발점 A는 불변")
        XCTAssertEqual(endSideSession.course?.coordinates.last, C, "도착점 쪽이 더 가까우므로 C가 새 도착점")
    }

    /// 출발점 쪽 gap 라우팅 실패 → 세션 상태 불변 + redo 스택 보존 (MVP9 에러 규칙의 새 분기 적용)
    func testAttach_farStrokeNearerToStart_gapFailure_preservesState() async throws {
        let session = CourseEditSession()
        let okService = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: okService)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: okService)
        session.undo()
        XCTAssertTrue(session.canRedo)

        // P는 A에서 ~333m·B에서 ~777m (출발점 쪽, 임계값 밖) → 새 분기의 gap 라우팅이 실패
        let P = CourseCoordinate(latitude: 37.503, longitude: 127.00)
        let failingService = FailingCourseService()
        do {
            try await session.attach(.drawn(coordinates: [P, D], distanceMeters: 300), using: failingService)
            XCTFail("gap 라우팅 실패로 throw되어야 함")
        } catch {}

        XCTAssertTrue(session.canRedo, "실패한 attach는 redo 스택을 보존해야 함")
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.course?.coordinates.first, A)
        XCTAssertEqual(session.course?.coordinates.last, B)
    }

    // MARK: - attach: 규칙 2 — 왕복 스트로크(도착점에서 시작)는 항상 append

    func testAttach_roundTripStroke_appendsPreservingRunOrder() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: 도착점 B 근처에서 시작해 출발점 A 근처로 되짚는 왕복 스트로크
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
        try await session.attach(.drawn(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A, "출발은 A 유지 (prepend 금지)")
        XCTAssertEqual(session.course?.coordinates.last, near_A, "달리는 순서 유지")
    }

    // MARK: - attach: 규칙 1 — 닫힌 코스에는 무조건 append

    func testAttach_closedCourse_alwaysAppends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 닫힌 코스 구성: A→B, 그리고 B→A근처로 되짚기 → 첫·끝 좌표 ≤20m
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        let near_A = CourseCoordinate(latitude: A.latitude + 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [near_B, near_A], distanceMeters: 100), using: service)
        // 닫힌 코스에서 공유 지점 근처에서 시작하는 새 구간 → prepend가 아니라 append여야 함
        let near_A2 = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [near_A2, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.course?.coordinates.first, A, "닫힌 코스 연장 시 출발점이 바뀌면 안 됨")
        XCTAssertEqual(session.course?.coordinates.last, C)
    }

    // MARK: - undo

    func testUndo_removesLastSegment() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        session.undo()
        XCTAssertEqual(session.segments.count, 1)
    }

    func testUndo_empty_doesNothing() {
        let session = CourseEditSession()
        session.undo()
        XCTAssertTrue(session.segments.isEmpty)
    }

    // MARK: - clear

    func testClear_removesAll() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        session.clear()
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertNil(session.course)
    }

    // MARK: - undo is exact unit (no dangling gap)

    func testUndo_withGap_removesGapAndSegmentTogether() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // 거리가 먼 곳 C→D (gap B→C 라우팅됨)
        try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
        // undo → gap+segment 합쳐진 하나가 제거되어야 함
        session.undo()
        XCTAssertEqual(session.segments.count, 1, "gap이 병합됐으므로 undo 1번에 하나만 남아야 함")
        XCTAssertEqual(session.course?.coordinates.last, B)
    }

    // MARK: - undo after prepend (시간순 vs 공간순)

    func testUndo_afterPrepend_removesMostRecentlyAttachedNotSpatialLast() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B, then B→C (append) → 공간 순서: A-B-C
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // D→A를 prepend (기존 시작 A 근처) → 공간 순서: D-A-B-C, 하지만 시간상 가장 최근 attach는 D→A
        let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [near_A, D], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 3)
        XCTAssertEqual(session.course?.coordinates.first, D)

        session.undo()

        XCTAssertEqual(session.segments.count, 2, "가장 최근 attach(D→A)만 제거되어야 함")
        XCTAssertEqual(session.course?.coordinates.first, A, "prepend로 붙인 최근 세그먼트가 제거되어야 함")
        XCTAssertEqual(session.course?.coordinates.last, C, "공간적 마지막 세그먼트(B→C)는 남아있어야 함")
    }

    // MARK: - segmentColorKeys (attach 순서 기반, prepend에도 안정적)

    func testSegmentColorKeys_stableAcrossPrepend() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segmentColorKeys, [0, 1])

        let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [near_A, D], distanceMeters: 100), using: service)

        // prepend는 배열 맨 앞에 삽입되지만, colorKey(생성 순서)는 기존 세그먼트의 것이 유지되어야 함
        XCTAssertEqual(session.segmentColorKeys, [2, 0, 1])
    }

    // MARK: - redo

    func testRedo_restoresUndoneSegment() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.redo()
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.last, C)
        XCTAssertEqual(session.segmentColorKeys, [0, 1], "order 보존")
        XCTAssertFalse(session.canRedo)
    }

    func testRedo_restoresPrependPosition() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // 반전 prepend 유발: 출발점 A 근처에서 시작해 D로
        let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [near_A, D], distanceMeters: 100), using: service)
        XCTAssertEqual(session.course?.coordinates.first, D)

        session.undo()
        XCTAssertEqual(session.course?.coordinates.first, A)
        session.redo()
        XCTAssertEqual(session.course?.coordinates.first, D, "prepend 자리(맨 앞)로 복원되어야 함")
        XCTAssertEqual(session.segmentColorKeys, [2, 0, 1], "colorKey 보존")
    }

    func testRedo_multiple_restoresInReverseUndoOrder() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
        session.undo()
        session.undo()
        XCTAssertEqual(session.segments.count, 1)
        session.redo()
        XCTAssertEqual(session.course?.coordinates.last, C, "먼저 되돌린 것부터 역순 복원")
        session.redo()
        XCTAssertEqual(session.course?.coordinates.last, D)
    }

    func testAttach_success_clearsRedoStack() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        session.undo()
        XCTAssertTrue(session.canRedo)
        try await session.attach(.tapped(coordinates: [B, D], distanceMeters: 100), using: service)
        XCTAssertFalse(session.canRedo, "성공한 attach는 미래를 무효화")
    }

    func testAttach_failure_preservesRedoStack() async throws {
        let session = CourseEditSession()
        let okService = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: okService)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: okService)
        session.undo()
        XCTAssertTrue(session.canRedo)

        // gap 라우팅이 실패하는 원거리 attach → entry 미추가 → 스택 보존
        let failingService = FailingCourseService()
        do {
            try await session.attach(.tapped(coordinates: [D, C], distanceMeters: 100), using: failingService)
            XCTFail("gap 라우팅 실패로 throw되어야 함")
        } catch {}
        XCTAssertTrue(session.canRedo, "실패한 attach는 redo 스택을 보존해야 함")
        XCTAssertEqual(session.segments.count, 1)
    }

    func testClear_clearsRedoStack() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.clear()
        XCTAssertFalse(session.canRedo)
    }

    func testRedo_empty_doesNothing() {
        let session = CourseEditSession()
        session.redo()
        XCTAssertTrue(session.segments.isEmpty)
    }
}

// MARK: - Stub

@MainActor
private final class StubCourseService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }
}

@MainActor
private final class FailingCourseService: CoursePlanningServiceProtocol {
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        throw CoursePlanningError.routeNotFound
    }
}
