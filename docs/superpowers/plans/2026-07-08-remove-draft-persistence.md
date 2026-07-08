# 초안 자동 저장/복원 제거 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱을 완전히 종료했다가 다시 켜면 작업 중이던 코스가 사라지고 빈 상태로 시작하도록, 디스크 기반 초안 자동 저장/복원 기능을 통째로 제거한다.

**Architecture:** 백그라운드 전환 후 복귀는 이미 메모리 상태(뷰 생명주기)만으로 유지되고 있어 코드 변경이 필요 없다 — 디스크에서 실제로 복원을 읽어오는 지점은 콜드 스타트(`bootstrapDraft`) 하나뿐이다. 그 복원 호출을 없애면 편집할 때마다 디스크에 쓰던 저장 로직(`persistDraft` 및 그 경로 전체: SwiftData `DraftRecord`, `CourseDraft` 도메인 타입, 프로토콜의 draft 메서드) 자체가 아무도 읽지 않는 죽은 코드가 되므로 함께 삭제한다. 저장 코스(이름 붙여 저장/목록/불러오기/삭제) 기능은 완전히 별개이며 그대로 유지한다.

**Tech Stack:** Swift 6, SwiftUI, MVVM, SwiftData, XCTest.

## Global Constraints

- 브랜치: 기존 `feature/course-save-roundtrip`에서 계속 진행.
- **제거 대상(draft)과 유지 대상(saved courses)을 정확히 구분**한다 — `CourseRepositoryProtocol`의 `saveCourse`/`fetchCourses`/`deleteCourse`, `SwiftDataCourseRepository`의 `CourseRecord`/해당 메서드, `CoursePersistenceDTO`의 `Coordinate`/`Segment`/`Course`(공유 또는 saved-course 전용)는 전부 유지.
- `CourseEditSession`의 `anchorID`/`anchorInsertsBefore` 필드는 **삭제하지 않는다** — draft 복원용이 아니라 왕복 삽입의 세션 내 undo/redo(anchor 기반 재삽입)에 쓰이는 살아있는 로직이다. 삭제 대상은 오직 `snapshot()`/`restore(from:)` 메서드와 `CourseDraft` 타입 자체.
- `CourseEditSession.load(segments:)`는 저장 코스 불러오기 기능이 쓰므로 유지한다.
- 테스트는 "draft 전용이라 삭제" / "saved-course 관련이라 유지하되 draft 시딩·검증 코드만 제거" 두 종류를 구분해서 처리한다 — 파일째 삭제 vs 부분 수정을 혼동하지 않는다.
- 각 태스크 종료 시 `xcodebuild build` + `xcodebuild test`(대상 스킴 전체)가 통과해야 한다. 삭제 작업이라 "실패하는 테스트를 먼저 쓰는" TDD 절차는 적용하지 않는다 — 대신 각 스텝 뒤에 전체 빌드로 빠진 참조가 없는지 확인한다.
- 기존 코드 스타일을 따른다: 불필요해진 주석("MVP11 스펙 §2/§3" 등 draft 관련 문구)도 함께 정리한다.

---

## Task 1: Domain·Application 레이어 — `CourseDraft` 제거, `CourseEditSession` 축소

**Files:**
- Delete: `Trace/Domain/CoursePlanning/Entity/CourseDraft.swift`
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift`
- Delete: `TraceTests/CourseDraftSnapshotTests.swift`
- Modify: `TraceTests/CourseEditSessionTests.swift` (draft 파일에서 살아남아야 하는 테스트 이관)
- Modify: `TraceTests/CourseRoundTripInsertTests.swift` (snapshot/restore 의존 테스트 2개 제거)

**Interfaces:**
- Consumes: 없음(최하위 레이어부터 제거 시작).
- Produces: `CourseEditSession`이 더 이상 `CourseDraft`/`snapshot()`/`restore(from:)`를 노출하지 않음 — Task 2·3에서 이 사실에 의존해 상위 레이어를 정리한다.

- [ ] **Step 1: `CourseDraft.swift` 파일 삭제**

```bash
rm Trace/Domain/CoursePlanning/Entity/CourseDraft.swift
```

- [ ] **Step 2: `CourseEditSession.swift`에서 `snapshot()`/`restore(from:)` 제거**

`// MARK: - Snapshot (초안 저장·복원, MVP11 스펙 §3)` 섹션 전체(현재 `func snapshot()`부터 `func restore(from draft: CourseDraft)`까지, `load(segments:)` 앞부분)를 아래로 교체 — `load(segments:)`는 그대로 남기고 그 위의 두 메서드와 섹션 헤더만 제거:

```swift
    // 저장 코스 불러오기: 공간순 세그먼트에 시간순을 0부터 재부여 (undo = 공간순 마지막부터 제거)
    func load(segments: [CourseSegment]) {
```

(즉 `// MARK: - Snapshot ...` 주석, `snapshot()`, `restore(from:)` 세 덩어리를 삭제하고 바로 `load(segments:)`로 이어지게 한다. `load(segments:)` 본문과 그 아래 나머지 코드는 변경하지 않는다.)

- [ ] **Step 3: `CourseDraftSnapshotTests.swift`에서 살아남아야 할 테스트를 `CourseEditSessionTests.swift`로 이관 후 파일 삭제**

`TraceTests/CourseEditSessionTests.swift`의 `func testRedo_empty_doesNothing() { ... }` 바로 다음, 클래스를 닫는 `}`(609번째 줄 근처, `// MARK: - Stub` 앞) 직전에 아래 테스트를 추가:

```swift

    func testLoadSegments_reassignsSequentialOrders() {
        let session = CourseEditSession()
        let segs: [CourseSegment] = [
            .tapped(coordinates: [CourseCoordinate(latitude: 37.50, longitude: 127.00), CourseCoordinate(latitude: 37.51, longitude: 127.00)], distanceMeters: 1000),
            .drawn(coordinates: [CourseCoordinate(latitude: 37.51, longitude: 127.00), CourseCoordinate(latitude: 37.52, longitude: 127.00)], distanceMeters: 1000)
        ]
        session.load(segments: segs)
        XCTAssertEqual(session.segments, segs)
        XCTAssertEqual(session.segmentColorKeys, [0, 1])
        session.undo() // 공간순 마지막이 시간순 최신
        XCTAssertEqual(session.segments.count, 1)
    }
```

그 다음 파일 삭제:

```bash
rm TraceTests/CourseDraftSnapshotTests.swift
```

- [ ] **Step 4: `CourseRoundTripInsertTests.swift`에서 snapshot/restore 의존 테스트 2개 제거**

`testSnapshotRestore_preservesRoundTripRedoAnchor`와 `testSnapshotRestore_preservesFrontAnchorPlacement` 두 함수 전체를 삭제한다. 이 두 테스트가 검증하던 "anchor 기반 redo가 뒤/앞 양쪽에서 정확히 복원되는지"는 같은 파일의 `testInsertRoundTrip_undoRedo_restoresAfterAnchor`와 `testInsertRoundTrip_frontSegment_undoRedo_restoresBeforeAnchor`(snapshot을 거치지 않고 직접 undo/redo)가 이미 커버하므로 커버리지 손실이 없다.

- [ ] **Step 5: 빌드 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build 2>&1 | tail -40`

Expected: 이 시점에는 `CoursePersistenceDTO.swift`/`CourseRepositoryProtocol.swift`/`SwiftDataCourseRepository.swift`/ViewModel이 아직 `CourseDraft`를 참조하므로 **컴파일 실패가 정상**(Task 2·3에서 해소). 에러 메시지가 전부 "Cannot find type 'CourseDraft'" 계열인지만 확인하고 다음 태스크로 진행한다.

- [ ] **Step 6: Commit**

```bash
git add Trace/Domain/CoursePlanning/Entity/CourseDraft.swift Trace/Application/CoursePlanning/CourseEditSession.swift TraceTests/CourseDraftSnapshotTests.swift TraceTests/CourseEditSessionTests.swift TraceTests/CourseRoundTripInsertTests.swift
git commit -m "$(printf 'refactor: CourseDraft·CourseEditSession 스냅샷 제거\n\nDomain CourseDraft 타입과 CourseEditSession.snapshot/restore를 삭제.\nload(segments:)는 저장 코스 불러오기가 쓰므로 유지.\nanchorID/anchorInsertsBefore 필드도 왕복 undo/redo에 쓰이므로 유지.')"
```

(이 커밋은 프로토콜/ViewModel이 아직 옛 시그니처를 참조해 컴파일이 깨진 상태로 남는다 — Task 2·3까지 이어서 진행해야 전체가 다시 컴파일된다. 계획대로 태스크 경계에서 커밋을 나누되, 실제 빌드 통과 확인은 Task 3 종료 시점에 한 번에 한다.)

---

## Task 2: Repository 프로토콜 + SwiftData 어댑터/모델/DTO 축소

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Protocol/CourseRepositoryProtocol.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataCourseRepository.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceModels.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift`
- Modify: `TraceTests/SwiftDataCourseRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1의 결과(더 이상 `CourseDraft`가 존재하지 않음).
- Produces: `CourseRepositoryProtocol`이 `saveCourse`/`fetchCourses`/`deleteCourse` 3개 메서드만 노출 — Task 3의 ViewModel이 이 축소된 프로토콜에 맞춰 정리된다.

- [ ] **Step 1: `CourseRepositoryProtocol.swift` 축소**

전체를 아래로 교체:

```swift
import Foundation

// 코스 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다 — 도메인·ViewModel은
// 저장 방식을 모른다.
protocol CourseRepositoryProtocol: Sendable {
    func saveCourse(_ course: SavedCourse) async throws
    // 최신순 정렬. 손상 행은 건너뛰고 나머지 반환
    func fetchCourses() async -> [SavedCourse]
    func deleteCourse(id: UUID) async throws
}
```

- [ ] **Step 2: `CoursePersistenceModels.swift`에서 `DraftRecord` 제거**

전체를 아래로 교체:

```swift
import Foundation
import SwiftData

// 어댑터 내부 전용 — 이 파일 밖(App/Domain/Pages)에서 import SwiftData 금지

@Model
final class CourseRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var payload: Data

    init(id: UUID, name: String, createdAt: Date, payload: Data) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.payload = payload
    }
}
```

- [ ] **Step 3: `SwiftDataCourseRepository.swift`에서 draft 메서드·스키마 항목 제거**

`Schema([DraftRecord.self, CourseRecord.self])`를 `Schema([CourseRecord.self])`로 교체(두 곳 — `makeContext(inMemory:)` 내부에 스키마 선언은 함수 시작부 1곳).

`// MARK: - Draft (단일 슬롯)` 섹션 전체(`saveDraft`/`loadDraft` 두 메서드)를 삭제한다.

`// MARK: - Decode` 섹션에서 `decodeDraft` static 메서드를 삭제하고 `decodeCourseSegments`는 그대로 둔다.

결과적으로 파일은 아래 구조가 된다(주석·본문은 기존 `saveCourse`/`fetchCourses`/`deleteCourse`/`decodeCourseSegments`/`makeContext` 그대로 유지, draft 관련 블록만 빠진 형태):

```swift
import Foundation
import SwiftData

actor SwiftDataCourseRepository: CourseRepositoryProtocol {
    enum RepositoryError: Error {
        case storeUnavailable
    }

    private let context: ModelContext?

    init(inMemory: Bool = false) {
        self.context = Self.makeContext(inMemory: inMemory)
    }

    private static func makeContext(inMemory: Bool) -> ModelContext? {
        let schema = Schema([CourseRecord.self])

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "TraceCourseStore.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        let backupURL = storeURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).bak")
        try? FileManager.default.moveItem(at: storeURL, to: backupURL)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return ModelContext(container)
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) else { return nil }
        return ModelContext(container)
    }

    // MARK: - Saved Courses

    func saveCourse(_ course: SavedCourse) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let dto = CoursePersistenceDTO.Course(
            version: CoursePersistenceDTO.currentVersion,
            segments: course.segments.map(CoursePersistenceDTO.Segment.init)
        )
        let payload = try JSONEncoder().encode(dto)
        context.insert(CourseRecord(
            id: course.id, name: course.name, createdAt: course.createdAt, payload: payload
        ))
        try context.save()
    }

    func fetchCourses() async -> [SavedCourse] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<CourseRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.compactMap { record in
            guard let segments = Self.decodeCourseSegments(record.payload) else { return nil }
            return SavedCourse(
                id: record.id, name: record.name, createdAt: record.createdAt, segments: segments
            )
        }
    }

    func deleteCourse(id: UUID) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<CourseRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - Decode (테스트 가능한 손상 처리 경로)

    static func decodeCourseSegments(_ data: Data) -> [CourseSegment]? {
        guard let dto = try? JSONDecoder().decode(CoursePersistenceDTO.Course.self, from: data),
              dto.version <= CoursePersistenceDTO.currentVersion else { return nil }
        return dto.segments.map(\.domain)
    }
}
```

- [ ] **Step 4: `CoursePersistenceDTO.swift`에서 `DraftEntry`/`Draft` 제거**

`struct DraftEntry: Codable { ... }` 전체 블록을 삭제.
`struct Draft: Codable { ... }` 전체 블록을 삭제(바로 아래 `struct Course: Codable { ... }`는 유지).
`extension CoursePersistenceDTO.Draft { ... }` (도메인 매핑) 블록 전체를 삭제.

`Coordinate`/`Segment`/`Course`와 그 도메인 매핑 확장(`extension CoursePersistenceDTO.Coordinate`, `extension CoursePersistenceDTO.Segment`)은 saved-course 저장에 그대로 쓰이므로 유지.

- [ ] **Step 5: `SwiftDataCourseRepositoryTests.swift`에서 draft 테스트 제거**

`sampleDraft()` 헬퍼, `testDraft_saveLoad_roundTripsAllFields`, `testDraft_secondSaveOverwritesFirst`, `testDraft_loadWithoutSave_returnsNil`, `testDecodeDraft_garbageData_returnsNil`, `testDecodeDraft_missingAnchorInsertsBeforeField_defaultsToFalse` 를 전부 삭제. `testCourses_saveFetchDelete`, `testCourses_duplicateNamesAllowed`, `testDecodeCourse_futureVersion_returnsNil`은 그대로 유지.

파일이 아래 구조로 남는다:

```swift
import XCTest
@testable import Trace

final class SwiftDataCourseRepositoryTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    func testCourses_saveFetchDelete() async throws {
        // ... 기존 본문 그대로
    }

    func testCourses_duplicateNamesAllowed() async throws {
        // ... 기존 본문 그대로
    }

    func testDecodeCourse_futureVersion_returnsNil() throws {
        // ... 기존 본문 그대로
    }
}
```

- [ ] **Step 6: 빌드 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build 2>&1 | tail -40`

Expected: `CoursePlannerPageViewModel.swift`가 아직 `saveDraft`/`loadDraft`/`bootstrapDraft`/`persistDraft`를 참조하므로 **컴파일 실패가 정상**(Task 3에서 해소). 에러가 ViewModel 파일에만 몰려 있는지 확인.

- [ ] **Step 7: Commit**

```bash
git add Trace/Domain/CoursePlanning/Protocol/CourseRepositoryProtocol.swift Trace/Infrastructure/Persistence/SwiftData/SwiftDataCourseRepository.swift Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceModels.swift Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift TraceTests/SwiftDataCourseRepositoryTests.swift
git commit -m "$(printf 'refactor: 저장소 계층에서 draft 저장/복원 제거\n\nCourseRepositoryProtocol에서 saveDraft/loadDraft 삭제, saveCourse/\nfetchCourses/deleteCourse 3개만 유지. SwiftData DraftRecord 모델과\nCoursePersistenceDTO의 Draft/DraftEntry, 관련 테스트를 함께 제거.')"
```

---

## Task 3: ViewModel + Page + DI 정리

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `TraceTests/CoursePlannerViewModelPersistenceTests.swift`

**Interfaces:**
- Consumes: Task 2의 축소된 `CourseRepositoryProtocol`(3개 메서드).
- Produces: 없음(최상위 레이어) — 이 태스크 종료 시 전체 빌드·테스트가 그린이어야 한다.

- [ ] **Step 1: `CoursePlannerPageViewModel.swift`에서 draft 상태·메서드·호출부 제거**

`private var draftSaveTask: Task<Void, Never>?` 4줄(주석 포함, `draftSaveFailureNotifyThreshold`까지)을 삭제.

`// MARK: - Draft Persistence (MVP11 스펙 §3)` 섹션 전체(`bootstrapDraft()`, `persistDraft()`, `flushDraftSaves()`, `recordDraftSaveFailure()` 네 메서드와 섹션 헤더)를 삭제.

아래 8개 호출부에서 `persistDraft()` 줄만 각각 삭제(주변 코드는 그대로):
- `routeAndAttach(from:to:)` 안, `try await session.attach(...)` 다음 줄.
- `routeStrokeAndAttach(_:startPinHit:generation:)` 안, `try await session.attach(...)` 다음 줄.
- `undo()` 안.
- `redo()` 안.
- `clear()` 안.
- `insertRoundTrip(afterColorKey:)` 안.
- `insertWholeCourseRoundTrip()` 안.
- `applyLoadedCourse(_:)` 안(마지막 줄).

- [ ] **Step 2: `CoursePlannerPage.swift`에서 bootstrapDraft 호출과 background persistDraft 제거**

`.task { ... }` 블록 맨 앞의 `await viewModel.bootstrapDraft()` 줄을 삭제(그 아래 카메라 복원·위치 부트스트랩 로직은 그대로 유지).

`.onChange(of: scenePhase) { _, newPhase in ... }` 블록에서 `viewModel.persistDraft()` 줄만 삭제 — `saveCameraPosition()` 호출은 카메라 상태 저장(별개 기능)이므로 유지:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background {
        saveCameraPosition()
    }
}
```

- [ ] **Step 3: `DependencyContainer.swift`의 낡은 주석 정리**

`.uiTesting()` 안의 `courseRepository: SwiftDataCourseRepository(inMemory: true)` 위 주석을 아래로 교체(draft 기준 설명이 더 이상 사실이 아니므로 저장 코스 격리 기준으로 재서술):

```swift
            // in-memory: UI 테스트가 실기기/다른 테스트의 저장 코스 데이터와 격리되도록
            courseRepository: SwiftDataCourseRepository(inMemory: true)
```

- [ ] **Step 4: `CoursePlannerViewModelPersistenceTests.swift` 정리**

`MockCourseRepository`에서 `savedDrafts`/`stubbedDraft`/`draftSaveError`/`setStubbedDraft`/`setDraftSaveError`/`saveDraft`/`loadDraft`를 제거하고 아래 형태로 축소:

```swift
// Task 6 공용 목 저장소
actor MockCourseRepository: CourseRepositoryProtocol {
    var savedCourses: [SavedCourse] = []

    func saveCourse(_ course: SavedCourse) async throws { savedCourses.append(course) }
    func fetchCourses() async -> [SavedCourse] {
        savedCourses.sorted { $0.createdAt > $1.createdAt }
    }
    func deleteCourse(id: UUID) async throws {
        savedCourses.removeAll { $0.id == id }
    }
}
```

`struct StubError: Error {}`는 draft 실패 테스트에서만 쓰였으므로 삭제.

`draftWithOneSegment()` 헬퍼를 삭제.

아래 draft 전용 테스트 함수를 통째로 삭제: `testBootstrapDraft_restoresSession`, `testBootstrapDraft_nilDraft_keepsEmptySession`, `testUndo_persistsDraftSnapshot`, `testClear_persistsEmptyDraft`, `testPersistDraft_savesInOperationOrder`, `testDraftSaveFailure_threeConsecutive_notifiesOnce`.

`testSaveCurrentCourse_savesSnapshotWithTrimmedName`에서 `await repo.setStubbedDraft(draftWithOneSegment())`와 `await vm.bootstrapDraft()` 두 줄을 삭제하고, 코스가 필요하므로 대신 `insertWholeCourseRoundTrip`이 아니라 직접 탭 경로로 세그먼트를 만들 필요 없이 — 이 테스트는 저장 버튼 동작만 검증하면 되므로, 세션에 구간이 있어야 한다면 `try? await vm.session.attach(.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000), using: StubPlannerService())`로 직접 채운다. 함수 전체를 아래로 교체:

```swift
    func testSaveCurrentCourse_savesSnapshotWithTrimmedName() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

        vm.courseNameInput = "  한강 5km  "
        await vm.saveCurrentCourse()

        let saved = await repo.savedCourses
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "한강 5km")
        XCTAssertEqual(saved.first?.segments, vm.course?.segments)
    }
```

`testRequestLoad_emptySession_loadsImmediately`에서 `await vm.flushDraftSaves()`와 그 다음 `let drafts = ...`/`XCTAssertEqual(drafts.last?.entries.count, 1)` 두 줄을 삭제(draft 저장 여부를 검증하던 부분 — 나머지 어서션은 유지):

```swift
    func testRequestLoad_emptySession_loadsImmediately() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        await vm.requestLoad(saved)
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
    }
```

`testRequestLoad_nonEmptySession_asksConfirmationThenReplaces`에서 `await repo.setStubbedDraft(draftWithOneSegment())`와 `await vm.bootstrapDraft()`를 지우고, 대신 "작업 중 코스가 있는 상태"를 직접 attach로 만든다:

```swift
    func testRequestLoad_nonEmptySession_asksConfirmationThenReplaces() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [
                .drawn(coordinates: [coord(37.55, 126.99), coord(37.56, 126.99)], distanceMeters: 3000)
            ]
        )

        await vm.requestLoad(saved)
        XCTAssertEqual(vm.pendingLoadCourse, saved) // 즉시 교체 아님 — 확인 대기
        XCTAssertNotEqual(vm.course?.segments, saved.segments)

        await vm.confirmPendingLoad()
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
        XCTAssertFalse(vm.isCourseListPresented) // 불러오면 시트 닫힘
    }
```

`testInsertRoundTrip_viaViewModel_updatesCourseAndPersists`에서 draft 시딩(`setStubbedDraft`/`bootstrapDraft`)과 draft 검증(`flushDraftSaves`/`savedDrafts` 어서션)을 제거하고, 코스 준비를 attach로 대체:

```swift
    func testInsertRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

        XCTAssertTrue(vm.canInsertRoundTrip(afterColorKey: 0))
        vm.insertRoundTrip(afterColorKey: 0)

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(대상 구간만큼 추가)
        XCTAssertNil(vm.selectedSegmentIndex)
    }
```

`testInsertWholeCourseRoundTrip_viaViewModel_updatesCourseAndPersists`도 동일하게 정리:

```swift
    func testInsertWholeCourseRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

        XCTAssertTrue(vm.canInsertWholeCourseRoundTrip)
        vm.insertWholeCourseRoundTrip()

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(전체 코스 왕복)
        XCTAssertNil(vm.selectedSegmentIndex)
    }
```

나머지 saved-course 테스트(`testSaveCurrentCourse_emptyNameOrCourse_doesNothing`, `testPresentCourseList_loadsCoursesNewestFirst`, `testDeleteSavedCourse_removesFromRepositoryAndList`, `testCanInsertRoundTrip_unknownKey_false`, `testCanInsertWholeCourseRoundTrip_emptyCourse_false`)와 `StubPlannerService`/`StubLocationService`는 draft를 참조하지 않으므로 그대로 둔다.

- [ ] **Step 5: 빌드 + 전체 테스트 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build 2>&1 | tail -30
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test 2>&1 | tail -80
```

Expected: `BUILD SUCCEEDED`, `TEST SUCCEEDED` — 이 시점부터 전체 스킴이 다시 컴파일·통과해야 한다(Task 1·2에서 의도적으로 깨뒀던 중간 상태가 여기서 해소됨).

- [ ] **Step 6: 시뮬레이터에서 육안 확인**

시뮬레이터에서 코스를 하나 그린 뒤 앱을 완전히 종료(`xcrun simctl terminate` 또는 홈 스와이프 후 강제 종료)했다가 다시 실행해 빈 지도로 시작하는지 확인한다. 그 다음 코스를 다시 그리고 앱을 홈 버튼으로만 백그라운드 전환했다가 복귀시켜 코스가 그대로 남아있는지 확인한다(두 시나리오 모두 확인해야 "백그라운드는 유지, 완전 종료는 초기화"가 실제로 검증된다).

- [ ] **Step 7: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/App/DependencyContainer.swift TraceTests/CoursePlannerViewModelPersistenceTests.swift
git commit -m "$(printf 'refactor: ViewModel·Page에서 draft 자동 저장/복원 제거\n\nbootstrapDraft/persistDraft/flushDraftSaves와 8곳의 호출부를 삭제.\n앱 완전 종료 후 재실행은 빈 상태로 시작하고, 백그라운드 전환 후\n복귀는 메모리 상태 그대로 유지된다(코드 변경 없이 기존 동작 유지).')"
```

---

## Task 4: 문서 갱신 — 스펙·project-decisions 정정

**Files:**
- Modify: `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md`
- Modify: `docs/agent-rules/project-decisions.md`

**Interfaces:** 없음(문서 전용).

- [ ] **Step 1: 스펙 §2·§3의 초안 자동 저장 부분에 정정 note 추가**

`docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md`의 `## 2. Persistence 설계` 제목 바로 아래에 아래 인용 블록을 추가:

```markdown
> **2026-07-08 정정**: 초안(작업 중 코스) 자동 저장·복원은 이후 제거되었다. 실기기 사용
> 중 "앱을 완전히 종료했다가 열면 이전 코스가 그대로 남아있는" 동작이 지도 앱 등 다른 앱의
> 관례와 어긋난다는 판단으로, 완전 종료 후에는 빈 상태로 시작하도록 되돌렸다. 백그라운드
> 전환 후 복귀는 (원래도 디스크가 아니라 메모리 상태로 유지되고 있었으므로) 코드 변경 없이
> 그대로 동작한다. 아래 §2·§3의 "초안" 관련 서술은 MVP11 최초 설계의 기록으로 남겨두되,
> 현재 구현과 다르다. 저장 코스(이름 붙여 저장/목록/불러오기/삭제)는 이 정정과 무관하게
> 그대로 유지된다.
```

`## 3. course-save — 동작 설계`의 `### 자동 저장·복원 (초안)` 소제목 바로 아래에도 같은 취지의 짧은 note를 추가:

```markdown
> **2026-07-08 정정**: 이 소절 전체(자동 저장·복원)가 제거되었다 — 위 §2 정정 note 참고.
```

- [ ] **Step 2: `project-decisions.md`의 Persistence 결정 항목 갱신**

`- Persistence: SwiftData, local-only (결정 2026-07-07, MVP11) — ...` 줄 끝에 이어서 아래 문장을 추가:

```markdown
 **(2026-07-08 정정)** 초안(작업 중 코스) 자동 저장·복원은 제거됨 — 완전 종료 후에는
 빈 상태로 시작. 저장 코스(이름 붙여 저장) 기능은 이 결정과 무관하게 SwiftData로 유지.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md docs/agent-rules/project-decisions.md docs/superpowers/plans/2026-07-08-remove-draft-persistence.md
git commit -m "$(printf 'docs: 초안 자동 저장 제거를 스펙·project-decisions에 기록\n\n완전 종료 후 빈 상태로 시작하도록 되돌린 배경을 §2/§3 정정 note로\n남기고, project-decisions.md의 Persistence 결정에도 반영. 이번\n제거 작업의 구현 플랜 파일도 함께 커밋.')"
```

---

## Self-Review 메모 (계획 작성자용)

- **범위 확인**: 저장 코스(이름 저장/목록/불러오기/삭제) 기능은 4개 태스크 전체에서 단 한 줄도 제거되지 않는다 — 각 태스크에서 "keep" 표시된 항목을 재확인할 것.
- **의존 순서**: Task 1(Domain·Application) → Task 2(Protocol·Infra, `CourseDraft` 소멸에 의존) → Task 3(ViewModel·Page·DI, 축소된 Protocol에 의존) → Task 4(문서, 코드 의존 없음). Task 1·2 종료 시점엔 의도적으로 빌드가 깨진 채 커밋되며, Task 3 종료 시점에 전체가 다시 그린이 된다 — 이는 이번 계획에 한해 허용한 예외로, 진행 중 중간에 브랜치를 다른 사람과 공유하거나 push하지 않는다는 전제.
- **커버리지 손실 점검**: `testLoadSegments_reassignsSequentialOrders`(Task 1에서 이관), anchor 기반 redo 앞/뒤 검증(기존 `testInsertRoundTrip_undoRedo_restoresAfterAnchor`/`testInsertRoundTrip_frontSegment_undoRedo_restoresBeforeAnchor`로 대체) 외에는 삭제되는 테스트 전부가 draft 기능 자체를 검증하던 것이라 기능 삭제와 함께 사라지는 것이 맞다.
