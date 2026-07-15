# run-record-save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **완료(소급 확인):** Task 1~5 전부 완료, 2026-07-14~15. 브랜치 `feature/run-record-save`,
> Task별 코드 리뷰(sonnet) 4건 전부 Approved(0 Critical/Important). 경량 사이클 결정에 따라
> 문서 서브에이전트 리뷰·최종 브랜치 전체 리뷰는 생략. 실기기 QA
> (`docs/qa/2026-07-14-run-record-save-device-checklist.md`) 통과, 2026-07-15. main으로
> fast-forward 통합 완료(최종 커밋 `fc021db`). 진행 중 체크박스가 갱신되지 않은 채 남아
> 있던 것으로, 실제 구현 완료 여부와는 무관하다.

**Goal:** 러닝 종료 시 기록을 SwiftData에 자동 저장하고, 러닝 탭에서 기록 목록/상세를 볼 수 있게 한다 (MVP13 사이클 2, 경량).

**Architecture:** 코스 저장 패턴(Domain 포트 + SwiftData actor 어댑터 + 버전 blob DTO)을 미러링하되 **별도 스토어 파일**(`TraceRunStore.store`)을 쓴다. 목록은 요약 컬럼만 읽고(blob 미디코드), 상세만 단건 blob을 디코드한다. 자동 저장은 `RunSession`이 종료 시점에 주입받은 리포지토리로 직접 수행하고 저장 상태(진행/성공/실패+재시도)를 요약 화면에 노출한다.

**Tech Stack:** Swift 6(클래식 격리), SwiftUI, SwiftData, XCTest. 스펙: `docs/superpowers/specs/2026-07-14-run-record-save-design.md`

## Global Constraints

- iOS 17+, MVVM. 명시 `@MainActor`는 UI/상태 타입(`RunSession`·ViewModel)만 — 값 타입·Infrastructure는 기본 nonisolated (`docs/agent-rules/project-decisions.md`).
- `import SwiftData`는 `Trace/Infrastructure/Persistence/SwiftData/` 파일 밖에서 금지 (기존 주석 규칙).
- Force unwrap(`!`)/force cast(`as!`)/force try(`try!`)/IUO(`var x: T!`) 금지 — SwiftLint 에러이자 pre-commit 차단.
- 브랜치: `feature/run-record-save` (main 직접 커밋 금지). 시작 전 `git switch -c feature/run-record-save` (docs/run-record-save-kickoff가 이미 통합됐으면 main에서, 아니면 그 브랜치에서 분기).
- 시뮬레이터: 세션 시작 시 **iOS 26.5 iPhone UDID 하나를 고정**(`xcrun simctl list devices available | grep iPhone`), 이후 절대 변경 금지. 테스트는 raw `xcodebuild ... -parallel-testing-enabled NO test`만 사용(XcodeBuildMCP 테스트 툴 금지) — `docs/agent-rules/testing.md`.
- 커밋 전 3종 검증 + 스탬프 필수(pre-commit 훅이 검사). 각 Task의 커밋 스텝에 명령 포함.
- 커밋은 `scripts/trace-commit.sh -m "..." -- <paths>` 사용, `Co-Authored-By` 금지, 태그+한국어 제목+본문 3~4줄 (`docs/agent-rules/git.md`).
- 새 Swift 파일은 디스크에 만들면 타깃에 자동 포함된다(fileSystemSynchronizedGroups) — Xcode GUI 개입 불필요.
- 테스트 네이밍: 기존 스위트를 따른다 — 한국어 서술형(`test_시작하면_...`) 또는 영문 카멜 둘 다 선례 있음. 새 파일 안에서 일관되게.

**검증 명령 묶음 (아래 각 Task의 "검증+커밋" 스텝에서 이걸 실행):**

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test \
  && touch .git/trace-verify-test.ok
swiftlint && touch .git/trace-verify-lint.ok
```

---

### Task 1: Domain — `SavedRun`/`SavedRunSummary` 엔티티 + 리포지토리 포트

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/SavedRun.swift`
- Create: `Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift`
- Test: `TraceTests/SavedRunTests.swift`

**Interfaces:**
- Consumes: `RunSample`(기존, `Trace/Domain/RunTracking/Entity/RunSample.swift`), `CourseCoordinate`(기존).
- Produces: `SavedRunSummary(id:startedAt:distanceMeters:duration:elevationGainMeters:)` + 계산 프로퍼티 `averagePaceSecondsPerKm: Double?`; `SavedRunSample(timestamp:latitude:longitude:altitudeMeters:speedMetersPerSecond:)` + `init(_ sample: RunSample)` + `coordinate: CourseCoordinate`; `SavedRun(summary:samples:)`; `RunRecordRepositoryProtocol`의 4메서드(아래 시그니처 그대로) — Task 2·3·4가 전부 이 타입에 의존한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SavedRunTests.swift`:

```swift
import XCTest
@testable import Trace

nonisolated final class SavedRunTests: XCTestCase {
    func test_평균페이스는_거리와_시간에서_계산된다() {
        let summary = SavedRunSummary(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1000),
            distanceMeters: 2000, duration: 720, elevationGainMeters: 5
        )
        // 720초 / 2km = 360초/km
        XCTAssertEqual(summary.averagePaceSecondsPerKm, 360)
    }

    func test_거리나_시간이_0이면_평균페이스는_nil() {
        let zeroDistance = SavedRunSummary(
            id: UUID(), startedAt: Date(), distanceMeters: 0, duration: 720, elevationGainMeters: 0
        )
        let zeroDuration = SavedRunSummary(
            id: UUID(), startedAt: Date(), distanceMeters: 2000, duration: 0, elevationGainMeters: 0
        )
        XCTAssertNil(zeroDistance.averagePaceSecondsPerKm)
        XCTAssertNil(zeroDuration.averagePaceSecondsPerKm)
    }

    func test_RunSample에서_변환시_정확도는_버려지고_5필드만_남는다() {
        let sample = RunSample(
            timestamp: Date(timeIntervalSince1970: 1000), latitude: 37.5, longitude: 127.0,
            altitudeMeters: 20, speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5, verticalAccuracyMeters: 8
        )
        let saved = SavedRunSample(sample)
        XCTAssertEqual(saved.timestamp, sample.timestamp)
        XCTAssertEqual(saved.latitude, 37.5)
        XCTAssertEqual(saved.longitude, 127.0)
        XCTAssertEqual(saved.altitudeMeters, 20)
        XCTAssertEqual(saved.speedMetersPerSecond, 3)
        XCTAssertEqual(saved.coordinate, CourseCoordinate(latitude: 37.5, longitude: 127.0))
    }
}
```

- [ ] **Step 2: 테스트가 컴파일 실패(타입 미존재)하는지 확인**

Run: 위 "검증 명령 묶음"의 test 명령 (또는 빌드만으로 실패 확인).
Expected: FAIL — `cannot find 'SavedRunSummary' in scope`

- [ ] **Step 3: 엔티티 구현**

`Trace/Domain/RunTracking/Entity/SavedRun.swift`:

```swift
import Foundation

/// 저장된 러닝 기록의 목록용 요약 — 전부 스토어 컬럼에서 나오며 blob을 디코드하지 않는다(스펙 §2).
/// Hashable은 목록→상세 navigationDestination(for:)의 요구사항.
struct SavedRunSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let distanceMeters: Double
    /// 벽시계 경과 시간(초) — 트래킹 화면·요약이 보여준 시간과 같은 기준
    let duration: TimeInterval
    let elevationGainMeters: Double

    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 0, duration > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }
}

/// 저장용 샘플 — `RunSample`에서 필터 판정 전용인 정확도 2필드를 뺀 5필드(스펙 §2).
/// `RunSample`을 재사용하지 않는 이유: 로드 시 가짜 정확도 값을 채워 넣는 왜곡을 피한다.
struct SavedRunSample: Equatable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let speedMetersPerSecond: Double

    var coordinate: CourseCoordinate {
        CourseCoordinate(latitude: latitude, longitude: longitude)
    }

    init(
        timestamp: Date, latitude: Double, longitude: Double,
        altitudeMeters: Double, speedMetersPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }

    init(_ sample: RunSample) {
        self.init(
            timestamp: sample.timestamp, latitude: sample.latitude, longitude: sample.longitude,
            altitudeMeters: sample.altitudeMeters, speedMetersPerSecond: sample.speedMetersPerSecond
        )
    }
}

/// 저장된 러닝 기록 전체 — 상세 화면 단건 조회 전용(스펙 §2).
struct SavedRun: Equatable, Sendable {
    let summary: SavedRunSummary
    let samples: [SavedRunSample]
}
```

`Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift`:

```swift
import Foundation

// 러닝 기록 지속성 포트. 구현은 Infrastructure 어댑터(SwiftData)가 담당한다.
// 목록(fetchSummaries)과 상세(fetchRun)를 분리해 목록 경로가 blob을 디코드하지 않게 한다(스펙 §2·§5).
protocol RunRecordRepositoryProtocol: Sendable {
    func save(_ run: SavedRun) async throws
    /// 최신순(startedAt 내림차순). 컬럼만 읽는다 — blob 미디코드
    func fetchSummaries() async -> [SavedRunSummary]
    /// 단건 blob 디코드. 해독 실패(손상·미래 버전)·미존재 시 nil (스펙 §6 우아한 강등)
    func fetchRun(id: UUID) async -> SavedRun?
    func deleteRun(id: UUID) async throws
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: PASS (기존 178개 + 신규 3개 전부 그린)

- [ ] **Step 5: 검증+커밋**

검증 명령 묶음 3종 실행 → 전부 성공 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 기록 도메인 타입과 리포지토리 포트 추가

- SavedRunSummary(목록용 컬럼 요약)와 SavedRun(상세용 전체)을 분리해 정의한다
- SavedRunSample은 RunSample에서 필터 전용 정확도 2필드를 뺀 저장용 5필드다
- RunRecordRepositoryProtocol은 목록/상세 조회를 분리한 지속성 포트다" \
  -- Trace/Domain/RunTracking/Entity/SavedRun.swift \
     Trace/Domain/RunTracking/Protocol/RunRecordRepositoryProtocol.swift \
     TraceTests/SavedRunTests.swift
```

---

### Task 2: Infrastructure — DTO + `RunRecordModel` + SwiftData 어댑터

**Files:**
- Create: `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`
- Create: `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceModels.swift`
- Create: `Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift`
- Test: `TraceTests/SwiftDataRunRecordRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1의 `SavedRun`/`SavedRunSummary`/`SavedRunSample`/`RunRecordRepositoryProtocol`.
- Produces: `SwiftDataRunRecordRepository(inMemory: Bool = false)` — 포트 구현체. `static func decodeRunSamples(_ data: Data) -> [SavedRunSample]?` (테스트 가능한 손상 처리 경로). Task 3의 `DependencyContainer`가 생성자를 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SwiftDataRunRecordRepositoryTests.swift` (기존 `SwiftDataCourseRepositoryTests` 패턴 미러):

```swift
import XCTest
@testable import Trace

nonisolated final class SwiftDataRunRecordRepositoryTests: XCTestCase {
    private func makeRun(
        startedAt: Date, distance: Double = 1000, duration: TimeInterval = 600
    ) -> SavedRun {
        let samples = [
            SavedRunSample(
                timestamp: startedAt, latitude: 37.50, longitude: 127.00,
                altitudeMeters: 20, speedMetersPerSecond: 3
            ),
            SavedRunSample(
                timestamp: startedAt.addingTimeInterval(10), latitude: 37.51, longitude: 127.00,
                altitudeMeters: 21, speedMetersPerSecond: 3.2
            )
        ]
        return SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: startedAt, distanceMeters: distance,
                duration: duration, elevationGainMeters: 4
            ),
            samples: samples
        )
    }

    func test_저장후_요약은_최신순으로_컬럼값을_돌려준다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let older = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeRun(startedAt: Date(timeIntervalSince1970: 2000), distance: 5000)
        try await repo.save(older)
        try await repo.save(newer)

        let summaries = await repo.fetchSummaries()
        XCTAssertEqual(summaries.map(\.id), [newer.summary.id, older.summary.id]) // 최신순
        XCTAssertEqual(summaries.first?.distanceMeters, 5000)
        XCTAssertEqual(summaries.first?.duration, 600)
    }

    func test_단건조회는_샘플까지_복원한다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let run = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        try await repo.save(run)

        let fetched = await repo.fetchRun(id: run.summary.id)
        XCTAssertEqual(fetched, run) // 요약+샘플 왕복 무손실
    }

    func test_삭제하면_요약목록에서_사라진다() async throws {
        let repo = SwiftDataRunRecordRepository(inMemory: true)
        let run = makeRun(startedAt: Date(timeIntervalSince1970: 1000))
        try await repo.save(run)
        try await repo.deleteRun(id: run.summary.id)
        let summaries = await repo.fetchSummaries()
        XCTAssertTrue(summaries.isEmpty)
        let fetched = await repo.fetchRun(id: run.summary.id)
        XCTAssertNil(fetched)
    }

    func test_손상blob은_디코드가_nil을_돌려준다() {
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunSamples(Data("not json".utf8)))
    }

    func test_미래버전blob은_디코드가_nil을_돌려준다() {
        let payload = Data(#"{"version":999,"samples":[]}"#.utf8)
        XCTAssertNil(SwiftDataRunRecordRepository.decodeRunSamples(payload))
    }
}
```

- [ ] **Step 2: 컴파일 실패 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: FAIL — `cannot find 'SwiftDataRunRecordRepository' in scope`

- [ ] **Step 3: DTO·모델·어댑터 구현**

`Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`:

```swift
import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (코스 DTO와 동일 원칙, 스펙 §2).
// 미래 심박·케이던스는 Run에 스트림 배열 하나를 옆에 추가 + version 증가로 끝난다(additive).
enum RunPersistenceDTO: Sendable {
    static let currentVersion = 1

    struct Sample: Codable {
        let t: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double
    }

    struct Run: Codable {
        let version: Int
        let samples: [Sample]
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension RunPersistenceDTO.Sample {
    init(_ sample: SavedRunSample) {
        self.init(
            t: sample.timestamp, lat: sample.latitude, lon: sample.longitude,
            alt: sample.altitudeMeters, spd: sample.speedMetersPerSecond
        )
    }

    var domain: SavedRunSample {
        SavedRunSample(
            timestamp: t, latitude: lat, longitude: lon,
            altitudeMeters: alt, speedMetersPerSecond: spd
        )
    }
}
```

`Trace/Infrastructure/Persistence/SwiftData/RunPersistenceModels.swift`:

```swift
import Foundation
import SwiftData

// 어댑터 내부 전용 — 이 파일 밖(App/Domain/Pages)에서 import SwiftData 금지

@Model
final class RunRecordModel {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    // 거리·시간·고도 상승은 목록 성능용 캐시 컬럼 — 진실의 원천은 payload의 원시 샘플(스펙 §2)
    var distanceMeters: Double
    var durationSeconds: Double
    var elevationGainMeters: Double
    var payload: Data

    init(
        id: UUID, startedAt: Date, distanceMeters: Double,
        durationSeconds: Double, elevationGainMeters: Double, payload: Data
    ) {
        self.id = id
        self.startedAt = startedAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGainMeters = elevationGainMeters
        self.payload = payload
    }
}
```

`Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift` (코스 어댑터의 폴백 체인·affinity 규칙 미러):

```swift
import Foundation
import SwiftData

// SwiftData 어댑터 — 러닝 기록은 코스와 별도 스토어 파일에 저장한다(스펙 §2 저장소 분리:
// 기존 코스 스토어에 스키마 변경을 가하지 않아 마이그레이션 리스크 0).
actor SwiftDataRunRecordRepository: RunRecordRepositoryProtocol {
    enum RepositoryError: Error {
        case storeUnavailable
    }

    private let inMemory: Bool
    // 컨텍스트는 첫 사용 시 actor 실행기 위에서 생성 — main 스레드 init에서 만들면 affinity 위반
    // (코스 어댑터와 동일, 2026-07-08 QA 교훈).
    private lazy var context: ModelContext? = Self.makeContext(inMemory: inMemory)

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    // 컨테이너 생성 실패 정책(스펙 §5): ① 정상 생성 → ② 손상 스토어 백업 후 재생성(자산 즉시
    // 삭제 금지) → ③ in-memory 폴백 → ④ nil(모든 연산 no-op/throw). 런치 크래시 금지.
    private nonisolated static func makeContext(inMemory: Bool) -> ModelContext? {
        let schema = Schema([RunRecordModel.self])

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else { return nil }
            return ModelContext(container)
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "TraceRunStore.store")
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

    // MARK: - RunRecordRepositoryProtocol

    func save(_ run: SavedRun) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let dto = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: run.samples.map(RunPersistenceDTO.Sample.init)
        )
        let payload = try JSONEncoder().encode(dto)
        context.insert(RunRecordModel(
            id: run.summary.id,
            startedAt: run.summary.startedAt,
            distanceMeters: run.summary.distanceMeters,
            durationSeconds: run.summary.duration,
            elevationGainMeters: run.summary.elevationGainMeters,
            payload: payload
        ))
        try context.save()
    }

    func fetchSummaries() async -> [SavedRunSummary] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<RunRecordModel>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        // 컬럼만 읽는다 — payload는 건드리지 않는다(스펙 §2 목록 성능)
        return records.map { record in
            SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            )
        }
    }

    func fetchRun(id: UUID) async -> SavedRun? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try? context.fetch(descriptor).first else { return nil }
        // 해독 실패(손상·미래 버전)는 nil — 목록 요약은 컬럼 기반이라 계속 유효(스펙 §6 우아한 강등)
        guard let samples = Self.decodeRunSamples(record.payload) else { return nil }
        return SavedRun(
            summary: SavedRunSummary(
                id: record.id, startedAt: record.startedAt,
                distanceMeters: record.distanceMeters,
                duration: record.durationSeconds,
                elevationGainMeters: record.elevationGainMeters
            ),
            samples: samples
        )
    }

    func deleteRun(id: UUID) async throws {
        guard let context else { throw RepositoryError.storeUnavailable }
        let descriptor = FetchDescriptor<RunRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - Decode (테스트 가능한 손상 처리 경로)

    static func decodeRunSamples(_ data: Data) -> [SavedRunSample]? {
        guard let dto = try? JSONDecoder().decode(RunPersistenceDTO.Run.self, from: data),
              dto.version <= RunPersistenceDTO.currentVersion else { return nil }
        return dto.samples.map(\.domain)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: PASS (신규 5개 포함 전부 그린)

- [ ] **Step 5: 검증+커밋**

검증 명령 묶음 3종 실행 → 전부 성공 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 기록 SwiftData 어댑터 추가 — 별도 스토어 파일

- RunRecordModel은 요약 컬럼 캐시 + 버전 blob(payload)으로 구성한다
- 코스와 분리된 TraceRunStore.store를 써서 기존 스토어 마이그레이션 리스크를 없앤다
- 손상·미래 버전 blob은 fetchRun이 nil을 돌려주고 요약 목록은 컬럼으로 유지된다
- 폴백 체인(백업→재생성→in-memory→nil)과 actor affinity 규칙은 코스 어댑터를 미러링" \
  -- Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift \
     Trace/Infrastructure/Persistence/SwiftData/RunPersistenceModels.swift \
     Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift \
     TraceTests/SwiftDataRunRecordRepositoryTests.swift
```

---

### Task 3: Application — `RunSession` 자동 저장 + 저장 상태 + DI 배선

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift`
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `TraceTests/RunSessionTests.swift` (생성자 변경 반영 + 신규 테스트)
- Create: `TraceTests/MockRunRecordRepository.swift`

**Interfaces:**
- Consumes: Task 1 포트/타입, Task 2 어댑터(컨테이너 배선).
- Produces: `RunSession.init(locationStream:recordRepository:)` (기존 생성자 대체), `RunSession.SaveStatus`(`.saving`/`.saved`/`.failed`), `private(set) var saveStatus: SaveStatus?`, `func retrySave()`, `DependencyContainer.runRecordRepository: RunRecordRepositoryProtocol` — Task 4의 요약 UI·목록 화면이 사용.

- [ ] **Step 1: 목 리포지토리 작성**

`TraceTests/MockRunRecordRepository.swift`:

```swift
import Foundation
@testable import Trace

@MainActor
final class MockRunRecordRepository: RunRecordRepositoryProtocol {
    enum MockError: Error { case saveFailed }

    private(set) var savedRuns: [SavedRun] = []
    var failsNextSave = false

    func save(_ run: SavedRun) async throws {
        if failsNextSave {
            failsNextSave = false
            throw MockError.saveFailed
        }
        savedRuns.append(run)
    }

    func fetchSummaries() async -> [SavedRunSummary] {
        savedRuns.map(\.summary).sorted { $0.startedAt > $1.startedAt }
    }

    func fetchRun(id: UUID) async -> SavedRun? {
        savedRuns.first { $0.summary.id == id }
    }

    func deleteRun(id: UUID) async throws {
        savedRuns.removeAll { $0.summary.id == id }
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`TraceTests/RunSessionTests.swift`에 추가 — 먼저 필드와 세션 생성을 바꾼다(파일 상단, 기존 `private lazy var session = RunSession(locationStream: stream)` 교체):

```swift
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)
```

그리고 테스트 메서드 추가 (기존 `waitUntil` 헬퍼 재사용):

```swift
    func test_종료하면_기록이_자동저장된다() async {
        await session.start()
        let start = Date()
        stream.yield(sample(at: start))
        stream.yield(sample(at: start.addingTimeInterval(10), latOffsetMeters: 30))
        await waitUntil { self.session.track.samples.count == 2 }

        session.finish()
        await waitUntil { self.session.saveStatus == .saved }

        XCTAssertEqual(recordRepository.savedRuns.count, 1)
        let saved = recordRepository.savedRuns[0]
        XCTAssertEqual(saved.samples.count, 2)
        XCTAssertEqual(saved.summary.distanceMeters, session.track.totalDistanceMeters)
        XCTAssertEqual(saved.summary.startedAt, session.startedAt)
        XCTAssertGreaterThan(saved.summary.duration, 0) // 벽시계 경과 시간
    }

    func test_저장실패시_상태가_failed가_되고_재시도로_저장된다() async {
        recordRepository.failsNextSave = true
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }

        session.finish()
        await waitUntil { self.session.saveStatus == .failed }
        XCTAssertTrue(recordRepository.savedRuns.isEmpty)

        session.retrySave()
        await waitUntil { self.session.saveStatus == .saved }
        XCTAssertEqual(recordRepository.savedRuns.count, 1)
    }

    func test_재시도해도_같은_id로_저장된다_중복기록_방지() async {
        recordRepository.failsNextSave = true
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }
        session.finish()
        await waitUntil { self.session.saveStatus == .failed }

        session.retrySave()
        await waitUntil { self.session.saveStatus == .saved }
        XCTAssertEqual(recordRepository.savedRuns.count, 1) // 실패분이 중복 저장되지 않는다
    }

    func test_신호확보중_취소하면_저장하지_않는다() async {
        await session.start()
        session.finishAcquiringCancelled()
        await drainNoOp()
        XCTAssertNil(session.saveStatus)
        XCTAssertTrue(recordRepository.savedRuns.isEmpty)
    }

    func test_요약을_닫으면_저장상태가_초기화된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }
        session.finish()
        await waitUntil { self.session.saveStatus == .saved }

        session.dismissSummary()
        XCTAssertNil(session.saveStatus)
    }

    func test_스트림이_끊겨_요약으로_가도_자동저장된다() async {
        await session.start()
        stream.yield(sample(at: Date()))
        await waitUntil { self.session.track.samples.count == 1 }

        stream.finish() // 권한 회수 등으로 스트림 종료 (MockRunLocationStream의 기존 헬퍼)
        await waitUntil { self.session.state == .summary }
        await waitUntil { self.session.saveStatus == .saved }
        XCTAssertEqual(recordRepository.savedRuns.count, 1)
    }
```

주의: `MockRunLocationStream`은 `RunSessionTests.swift` 하단에 이미 있다(`yield(_:)`/`finish()` 헬퍼 포함) — 새로 만들지 않는다.

- [ ] **Step 3: 컴파일 실패 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: FAIL — `extra argument 'recordRepository' in call` 등

- [ ] **Step 4: `RunSession` 구현**

`Trace/Application/RunTracking/RunSession.swift` 변경:

```swift
    enum SaveStatus: Equatable {
        case saving
        case saved
        case failed
    }
```

프로퍼티·생성자 (기존에 추가/교체):

```swift
    private(set) var saveStatus: SaveStatus?
    /// 저장(또는 재시도) 대상 기록 — 재시도가 같은 id로 저장되게 값을 보관한다
    private var pendingRun: SavedRun?
    private var endedAt: Date?

    private let locationStream: RunLocationStreamProtocol
    private let recordRepository: RunRecordRepositoryProtocol
    private var streamTask: Task<Void, Never>?

    init(locationStream: RunLocationStreamProtocol, recordRepository: RunRecordRepositoryProtocol) {
        self.locationStream = locationStream
        self.recordRepository = recordRepository
    }
```

`finish()`·`streamEnded()`·`dismissSummary()` 수정 + 저장 로직 추가:

```swift
    func finish() {
        guard isActive else { return }
        stopStream()
        endedAt = Date()
        state = .summary
        startRecordSave()
    }
```

```swift
    /// 스트림이 밖에서 끊긴 경우(러닝 도중 권한 회수 등) — 수집분을 버리지 않는다(스펙 §6)
    private func streamEnded() {
        guard isActive else { return }
        stopStream()
        if track.samples.isEmpty {
            state = .idle
            startedAt = nil
            lastStartFailure = .permissionDenied
        } else {
            endedAt = Date()
            state = .summary
            startRecordSave()
        }
    }
```

```swift
    func dismissSummary() {
        guard state == .summary else { return }
        state = .idle
        track = RunTrack()
        startedAt = nil
        endedAt = nil
        saveStatus = nil
        pendingRun = nil
        #if DEBUG
        dumpEntries = []
        #endif
    }
```

저장 로직 (private 섹션에 추가):

```swift
    // MARK: - 자동 저장 (스펙 §3)

    private func startRecordSave() {
        guard let startedAt, let endedAt, track.samples.isEmpty == false else { return }
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(),
                startedAt: startedAt,
                distanceMeters: track.totalDistanceMeters,
                // 벽시계 경과 시간 — 요약 화면이 보여주는 시간과 같은 기준(GPS 샘플 구간 아님)
                duration: endedAt.timeIntervalSince(startedAt),
                elevationGainMeters: track.elevationGainMeters
            ),
            samples: track.samples.map(SavedRunSample.init)
        )
        pendingRun = run
        performSave(run)
    }

    /// 저장 실패 후 재시도 — 같은 pendingRun(같은 id)을 다시 저장하므로 중복 기록이 생기지 않는다
    func retrySave() {
        guard saveStatus == .failed, let pendingRun else { return }
        performSave(pendingRun)
    }

    private func performSave(_ run: SavedRun) {
        saveStatus = .saving
        Task { [weak self, recordRepository] in
            do {
                try await recordRepository.save(run)
                self?.markSaveFinished(for: run, status: .saved)
            } catch {
                self?.markSaveFinished(for: run, status: .failed)
            }
        }
    }

    /// 요약을 닫은 뒤(또는 다음 세션에서) 완료된 이전 저장이 상태를 오염시키지 않게 id로 가드한다
    private func markSaveFinished(for run: SavedRun, status: SaveStatus) {
        guard pendingRun?.summary.id == run.summary.id else { return }
        saveStatus = status
    }
```

주의: 요약을 저장 중에 닫아도 `run` 값은 Task에 캡처돼 있어 **저장은 끝까지 진행된다**(데이터 유실 없음) — 상태 표시만 가드로 무시된다(스펙 §3, "요약시간 상태오염" 계열 버그 예방).

- [ ] **Step 5: `DependencyContainer` 배선**

`Trace/App/DependencyContainer.swift` — 프로퍼티 추가 및 두 팩토리 수정:

```swift
    let runRecordRepository: RunRecordRepositoryProtocol
```

`live()`에서:

```swift
        let runRecordRepository = SwiftDataRunRecordRepository()
        let runSession = RunSession(locationStream: RunLocationTracker(), recordRepository: runRecordRepository)
```

(반환 구성에 `runRecordRepository: runRecordRepository` 추가)

`uiTesting()`에서 (in-memory — UI 테스트 격리, 코스와 동일):

```swift
        let runRecordRepository = SwiftDataRunRecordRepository(inMemory: true)
        let runSession = RunSession(locationStream: UITestingRunLocationStream(), recordRepository: runRecordRepository)
```

(반환 구성에 `runRecordRepository: runRecordRepository` 추가)

- [ ] **Step 6: 테스트 통과 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: PASS — 기존 `RunSessionTests` 전부 + 신규 6개 그린. `RunPageViewModelTests`가 `RunSession` 생성자를 쓰면 그 파일의 생성부도 `recordRepository: MockRunRecordRepository()`로 갱신한다.

- [ ] **Step 7: 검증+커밋**

검증 명령 묶음 3종 실행 → 전부 성공 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 종료 시 기록 자동 저장 — RunSession에 리포지토리 주입

- 요약 진입(수동 종료·스트림 강제 종료 모두) 시 확인 없이 자동 저장한다
- 저장 상태(saving/saved/failed)를 노출하고 실패 시 같은 id로 재시도한다
- 요약을 닫아도 진행 중 저장은 완료되며 상태 오염은 id 가드로 차단한다
- DependencyContainer에 러닝 기록 리포지토리를 배선(UI 테스트는 in-memory)" \
  -- Trace/Application/RunTracking/RunSession.swift \
     Trace/App/DependencyContainer.swift \
     TraceTests/RunSessionTests.swift \
     TraceTests/MockRunRecordRepository.swift
```

(단, Step 6에서 `RunPageViewModelTests.swift`도 수정했다면 커밋 경로에 추가한다.)

---

### Task 4: UI — 요약 저장 상태 표시 + 기록 목록/상세

**Files:**
- Create: `Trace/Pages/RunPage/RunHistoryViewModel.swift`
- Create: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`
- Create: `Trace/Pages/RunPage/RunDurationFormatter.swift`
- Modify: `Trace/Pages/RunPage/RunPage.swift` (기록 버튼 + 시트 + 생성자에 리포지토리)
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (요약 패널 저장 상태 줄 + durationText를 포매터로 교체)
- Modify: `Trace/App/TraceApp.swift` (RunPage 생성자에 리포지토리 전달)
- Test: `TraceTests/RunHistoryViewModelTests.swift`, `TraceTests/RunDurationFormatterTests.swift`

**Interfaces:**
- Consumes: Task 1 타입, Task 3의 `DependencyContainer.runRecordRepository`·`RunSession.saveStatus`·`retrySave()`, 기존 `RunPaceFormatter`·`DesignToken`·`RunPageViewModel.fittingRegion` 패턴.
- Produces: `RunHistoryViewModel(repository:)` — `summaries`/`load()`/`loadRun(id:)`/`requestDelete(_:)`/`confirmPendingDelete()`/`cancelPendingDelete()`/`pendingDelete`/`showsDeleteFailure`; `RunDurationFormatter.string(seconds:)`. 사용자 화면 문구는 아래 코드의 문자열을 그대로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunDurationFormatterTests.swift`:

```swift
import XCTest
@testable import Trace

nonisolated final class RunDurationFormatterTests: XCTestCase {
    func test_시분초_형식() {
        XCTAssertEqual(RunDurationFormatter.string(seconds: 3725), "1:02:05")
        XCTAssertEqual(RunDurationFormatter.string(seconds: 65), "0:01:05")
        XCTAssertEqual(RunDurationFormatter.string(seconds: 0), "0:00:00")
    }
}
```

`TraceTests/RunHistoryViewModelTests.swift`:

```swift
import XCTest
@testable import Trace

@MainActor
final class RunHistoryViewModelTests: XCTestCase {
    private let repository = MockRunRecordRepository()
    private lazy var viewModel = RunHistoryViewModel(repository: repository)

    private func seedRun(startedAt: Date) async -> SavedRun {
        let run = SavedRun(
            summary: SavedRunSummary(
                id: UUID(), startedAt: startedAt, distanceMeters: 1000,
                duration: 600, elevationGainMeters: 3
            ),
            samples: [SavedRunSample(
                timestamp: startedAt, latitude: 37.5, longitude: 127.0,
                altitudeMeters: 10, speedMetersPerSecond: 3
            )]
        )
        do { try await repository.save(run) } catch { XCTFail("seed save failed") }
        return run
    }

    func test_load하면_요약이_최신순으로_실린다() async {
        let older = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        let newer = await seedRun(startedAt: Date(timeIntervalSince1970: 2000))
        await viewModel.load()
        XCTAssertEqual(viewModel.summaries.map(\.id), [newer.summary.id, older.summary.id])
    }

    func test_삭제는_확인후에만_실행되고_목록이_재동기화된다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        await viewModel.load()

        viewModel.requestDelete(run.summary)
        XCTAssertEqual(viewModel.pendingDelete?.id, run.summary.id)
        XCTAssertEqual(viewModel.summaries.count, 1) // 아직 안 지워짐

        await viewModel.confirmPendingDelete()
        XCTAssertNil(viewModel.pendingDelete)
        XCTAssertTrue(viewModel.summaries.isEmpty)
    }

    func test_삭제취소는_아무것도_지우지_않는다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        await viewModel.load()
        viewModel.requestDelete(run.summary)
        viewModel.cancelPendingDelete()
        XCTAssertNil(viewModel.pendingDelete)
        XCTAssertEqual(viewModel.summaries.count, 1)
    }

    func test_상세는_리포지토리에서_단건을_가져온다() async {
        let run = await seedRun(startedAt: Date(timeIntervalSince1970: 1000))
        let fetched = await viewModel.loadRun(id: run.summary.id)
        XCTAssertEqual(fetched, run)
        let missing = await viewModel.loadRun(id: UUID())
        XCTAssertNil(missing) // 손상/미존재 → nil (상세가 우아한 강등 처리)
    }
}
```

- [ ] **Step 2: 컴파일 실패 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: FAIL — `cannot find 'RunHistoryViewModel' in scope`

- [ ] **Step 3: 포매터 + ViewModel 구현**

`Trace/Pages/RunPage/RunDurationFormatter.swift`:

```swift
import Foundation

/// 경과 시간 "H:MM:SS" 표기 — 요약 패널·기록 목록/상세가 같은 형식을 쓴다
enum RunDurationFormatter {
    static func string(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
```

`Trace/Pages/RunPage/RunHistoryViewModel.swift`:

```swift
import Foundation
import Observation

/// 기록 목록/상세 상태 — 목록은 요약(컬럼)만, 상세 진입 시에만 단건 blob을 읽는다(스펙 §2·§4)
@MainActor
@Observable
final class RunHistoryViewModel {
    private let repository: RunRecordRepositoryProtocol

    private(set) var summaries: [SavedRunSummary] = []
    private(set) var pendingDelete: SavedRunSummary?
    var showsDeleteFailure = false

    init(repository: RunRecordRepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        summaries = await repository.fetchSummaries()
    }

    func loadRun(id: UUID) async -> SavedRun? {
        await repository.fetchRun(id: id)
    }

    func requestDelete(_ summary: SavedRunSummary) {
        pendingDelete = summary
    }

    func cancelPendingDelete() {
        pendingDelete = nil
    }

    func confirmPendingDelete() async {
        guard let pendingDelete else { return }
        self.pendingDelete = nil
        do {
            try await repository.deleteRun(id: pendingDelete.id)
        } catch {
            showsDeleteFailure = true
        }
        // 성공·실패 모두 실제 스토어와 재동기화(스펙 §6)
        await load()
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: PASS

- [ ] **Step 5: 화면 조립 — 기록 버튼·시트·목록·상세 + 요약 저장 상태**

`Trace/Pages/RunPage/RunPage.swift` — 생성자·상태·idle 오버레이·시트:

```swift
struct RunPage: View {
    @State private var viewModel: RunPageViewModel
    @State private var historyViewModel: RunHistoryViewModel
    @State private var showsHistory = false

    init(session: RunSession, recordRepository: RunRecordRepositoryProtocol) {
        _viewModel = State(initialValue: RunPageViewModel(session: session))
        _historyViewModel = State(initialValue: RunHistoryViewModel(repository: recordRepository))
    }
```

`body`의 `ZStack`에 idle 한정 기록 버튼 오버레이와 시트를 단다 (기존 alert 체인 뒤에 추가):

```swift
        .overlay(alignment: .topTrailing) {
            if viewModel.session.state == .idle {
                Button { showsHistory = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(GlassIconButtonStyle())
                .padding(.trailing, DesignToken.Size.screenMargin)
                .accessibilityIdentifier("run.historyButton")
            }
        }
        .sheet(isPresented: $showsHistory) {
            RunHistorySheet(viewModel: historyViewModel)
        }
```

`Trace/App/TraceApp.swift`의 생성부 교체:

```swift
                RunPage(session: container.runSession, recordRepository: container.runRecordRepository)
```

`Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` (코스 목록 시트 선례 미러):

```swift
import MapKit
import SwiftUI

/// 기록 목록 시트 — 러닝 탭 대기 화면에서 진입(스펙 §4). 행은 요약 컬럼만 사용한다.
struct RunHistorySheet: View {
    let viewModel: RunHistoryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.summaries.isEmpty {
                    ContentUnavailableView(
                        "아직 기록이 없어요",
                        systemImage: "figure.run",
                        description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("러닝 기록")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedRunSummary.self) { summary in
                RunRecordDetailView(summary: summary, viewModel: viewModel)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await viewModel.load() }
    }

    private var historyList: some View {
        List {
            ForEach(viewModel.summaries) { summary in
                NavigationLink(value: summary) {
                    RunHistoryRow(summary: summary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete { indexSet in
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.summaries[first])
            }
        }
        .listStyle(.plain)
        .alert(
            "기록을 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { _ in }
            )
        ) {
            Button("삭제", role: .destructive) { Task { await viewModel.confirmPendingDelete() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingDelete() }
        } message: {
            Text("삭제한 기록은 되돌릴 수 없습니다")
        }
        .alert("삭제하지 못했어요", isPresented: Bindable(viewModel).showsDeleteFailure) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요")
        }
    }
}

private struct RunHistoryRow: View {
    let summary: SavedRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(DesignToken.Typography.segmentRowTitle)
                .foregroundStyle(DesignToken.Color.ink)
            Text(
                "\(String(format: "%.2f", summary.distanceMeters / 1000))km · "
                + "\(RunDurationFormatter.string(seconds: summary.duration)) · "
                + "\(RunPaceFormatter.string(secondsPerKm: summary.averagePaceSecondsPerKm))"
            )
            .font(DesignToken.Typography.segmentRowSubtitle)
            .foregroundStyle(DesignToken.Color.ink2)
        }
        .padding(.vertical, 4)
    }
}

/// 기록 상세 — 단건 blob을 읽어 경로를 그린다. 해독 실패 시 숫자는 컬럼 값으로 유지하고
/// 지도 영역만 안내로 강등한다(스펙 §6).
struct RunRecordDetailView: View {
    let summary: SavedRunSummary
    let viewModel: RunHistoryViewModel
    @State private var loadedRun: SavedRun?
    @State private var loadFinished = false

    var body: some View {
        VStack(spacing: 0) {
            detailMap
            statsGrid
                .padding(DesignToken.Size.sheetPadding)
        }
        .navigationTitle(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadedRun = await viewModel.loadRun(id: summary.id)
            loadFinished = true
        }
    }

    @ViewBuilder
    private var detailMap: some View {
        if let loadedRun, loadedRun.samples.count >= 2 {
            let coordinates = loadedRun.samples.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            Map(initialPosition: RunRecordDetailView.fittedPosition(for: coordinates)) {
                MapPolyline(coordinates: coordinates)
                    .stroke(DesignToken.Color.accent, lineWidth: 5)
            }
        } else if loadFinished {
            ContentUnavailableView(
                "경로를 불러올 수 없어요",
                systemImage: "map",
                description: Text("기록 데이터에 문제가 있어 경로 표시만 건너뜁니다")
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 28, verticalSpacing: 12) {
            GridRow {
                statItem(String(format: "%.2f km", summary.distanceMeters / 1000), "거리")
                statItem(RunDurationFormatter.string(seconds: summary.duration), "시간")
            }
            GridRow {
                statItem(RunPaceFormatter.string(secondsPerKm: summary.averagePaceSecondsPerKm), "평균 페이스")
                statItem(String(format: "%.0f m", summary.elevationGainMeters), "고도 상승")
            }
        }
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DesignToken.Typography.segmentRowDistance).monospacedDigit()
            Text(label).font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }

    /// 경로 전체가 보이도록 카메라 핏 (RunPageViewModel.fittingRegion과 같은 계산)
    private static func fittedPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        ))
    }
}
```

참고: `SavedRunSummary`의 `Hashable`(navigationDestination 요구)은 Task 1 선언에 이미 반영돼 있다. 상세 지도 핏 계산은 `RunPageViewModel.fittingRegion`과 같은 로직의 사본이다 — ViewModel private 메서드를 공유하려고 접근 제어를 풀지 않는다(표시 전용 계산 12줄, 사본 수용).

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`의 `RunSummaryPanel` 수정 — ① 제목 아래에 저장 상태 줄 추가, ② `durationText`를 포매터로 교체:

```swift
            Text("러닝 요약").font(DesignToken.Typography.segmentRowTitle)
            saveStatusLine
```

```swift
    @ViewBuilder
    private var saveStatusLine: some View {
        switch viewModel.session.saveStatus {
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("저장 중…").font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
        case .saved:
            Label("기록 저장됨", systemImage: "checkmark.circle.fill")
                .font(DesignToken.Typography.chip)
                .foregroundStyle(DesignToken.Color.accent)
        case .failed:
            HStack(spacing: 8) {
                Label("저장 실패", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
                Button("다시 시도") { viewModel.session.retrySave() }
                    .font(DesignToken.Typography.chip)
            }
        case nil:
            EmptyView()
        }
    }
```

```swift
    private var durationText: String {
        // 트래킹 화면·Live Activity가 보여준 벽시계 경과 시간과 맞춘다(스펙 리뷰 Fix 2).
        // GPS 샘플 구간(`RunTrack.duration`)은 신호확보 공백·후행 필터링 샘플 때문에 실제보다 짧게 잡힐 수 있다.
        RunDurationFormatter.string(seconds: viewModel.summaryElapsedSeconds ?? viewModel.session.track.duration)
    }
```

- [ ] **Step 6: 테스트 통과 확인**

Run: 검증 명령 묶음의 test 명령.
Expected: PASS — 전체 스위트 그린 (UI 변경으로 기존 테스트가 깨지지 않는지 포함)

- [ ] **Step 7: 검증+커밋**

검증 명령 묶음 3종 실행 → 전부 성공 후:

```bash
scripts/trace-commit.sh -m "feat: 러닝 기록 목록/상세 화면 + 요약 저장 상태 표시

- 러닝 탭 대기 화면의 기록 버튼으로 목록 시트 진입(코스 목록 선례 미러)
- 목록은 요약 컬럼만 표시, 상세만 단건 blob을 읽어 경로 지도를 그린다
- blob 해독 실패 시 숫자는 유지하고 지도만 안내로 강등(스펙 §6)
- 요약 패널에 저장 중/저장됨/실패+재시도 상태 줄 추가, 시간 표기는 포매터로 통일" \
  -- Trace/Pages/RunPage/RunHistoryViewModel.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift \
     Trace/Pages/RunPage/RunDurationFormatter.swift \
     Trace/Pages/RunPage/RunPage.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift \
     Trace/App/TraceApp.swift \
     TraceTests/RunHistoryViewModelTests.swift \
     TraceTests/RunDurationFormatterTests.swift
```

(Task 1의 `SavedRun.swift`에 `Hashable`을 추가했다면 그 경로도 포함.)

---

### Task 5: 시뮬레이터 통합 확인 + 문서 갱신 + QA 체크리스트

**Files:**
- Create: `docs/qa/2026-07-XX-run-record-save-device-checklist.md` (실행일 날짜로)
- Modify: `docs/roadmap.md` (MVP13 사이클 2 진행 상태)

**Interfaces:**
- Consumes: Task 1~4 전체.
- Produces: 실기기 QA 대기 상태의 완성 브랜치.

- [ ] **Step 1: 시뮬레이터에서 흐름 눈 확인**

XcodeBuildMCP로 앱을 빌드·실행(UI 테스트 모드 `-traceUITesting` — `UITestingRunLocationStream`이 가짜 위치를 공급)하고 스크린샷으로 확인:
1. 러닝 탭 대기 화면에 기록 버튼 표시
2. 시작→샘플 수신→길게 눌러 종료→요약에 "기록 저장됨" 표시
3. 기록 버튼→목록에 방금 기록 표시(날짜·거리·시간·페이스)
4. 행 탭→상세에 경로 지도+4개 스탯
5. 밀어서 삭제→확인 알럿→목록에서 제거
6. 앱 종료 후 재실행→기록 유지 확인은 **in-memory라 UI 테스트 모드에선 불가** — live 모드로 재실행해 빈 목록("아직 기록이 없어요")만 확인 (영속성 자체는 실기기 QA에서)

Expected: 각 단계 스크린샷에서 스펙 §4 구성과 일치.

- [ ] **Step 2: 실기기 QA 체크리스트 작성**

`docs/agent-rules/testing.md`의 시나리오 카드 템플릿을 따라 `docs/qa/`에 작성 — 처음 쓰는 유저 기준의 평이한 언어(용어 금지), 스펙 §7 범위(저장·목록 조작, 뛸 필요 없음 — 짧은 산책 1회로 저장→재실행 후 목록 유지까지). 시나리오: ① 산책 후 종료하면 요약에 "기록 저장됨"이 보인다 ② 기록 버튼을 누르면 방금 산책이 목록 맨 위에 있다 ③ 기록을 누르면 지도에 지나온 길이 보인다 ④ 앱을 완전히 껐다 켜도 기록이 남아 있다 ⑤ 기록을 밀어서 지우면 사라지고 다시 켜도 없다.

- [ ] **Step 3: roadmap 갱신 + 커밋**

`docs/roadmap.md`의 MVP13 블록에서 사이클 2 진행 상태를 "구현 완료, 실기기 QA 대기"로 갱신 (run-record-save 마일스톤 체크는 QA 통과 후).

```bash
scripts/trace-commit.sh -m "docs: run-record-save 시뮬레이터 확인 완료 + 실기기 QA 체크리스트

- 시뮬레이터에서 저장→목록→상세→삭제 흐름 눈 확인 완료
- 실기기 QA 체크리스트(저장·목록 조작, 산책 1회 수준) 작성
- roadmap의 사이클 2 상태를 구현 완료·실기기 QA 대기로 갱신" \
  -- docs/qa/2026-07-XX-run-record-save-device-checklist.md docs/roadmap.md
```

(문서만 변경이지만 워킹 트리에 Swift 변경이 없으므로 스탬프는 Task 4 검증분이 유효 — 훅이 요구하면 검증 명령 묶음을 다시 실행한다.)

---

## Self-Review 체크 결과 (플랜 작성 시 수행)

- 스펙 커버리지: §1 포함 3항목=Task 3·4, §2 스키마=Task 1·2, §3 자동 저장=Task 3, §4 화면=Task 4, §5 아키텍처=Task 1~3, §6 에러=Task 2(폴백·nil)·3(재시도)·4(강등·삭제 실패), §7 테스트=각 Task+Task 5. 갭 없음.
- `SavedRunSummary`는 `navigationDestination` 때문에 `Hashable` 필요 — Task 1 코드 블록에 직접 반영 완료.
- `MockRunLocationStream`의 종료 헬퍼는 `finish()`로 실제 코드에서 확인 완료.
- 타입/시그니처 일관성: `fetchSummaries()`/`fetchRun(id:)`/`deleteRun(id:)`/`save(_:)` 전 Task 동일. `duration`(도메인) ↔ `durationSeconds`(모델 컬럼) 매핑은 Task 2 어댑터 안에서만.
