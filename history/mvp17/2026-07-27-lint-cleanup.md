# lint-cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **완료(소급 확인, 2026-07-27):** Task 1~5 전부 구현·태스크별 리뷰(Approved, Critical/Important 0건) 통과, 컨트롤러 독립 재검증(빌드·경고 건수) 완료. 아래 Step 체크박스는 subagent-driven-development 실행 중 실시간으로 갱신되지 않았을 뿐 전부 완료됐다 — 근거: 커밋 `9eb8f99`(Task1)·`a56ea80`(Task2)·`954af3f`(Task3)·`bca1c63`(Task4)·`f284e35`(Task5), SDD 진행 원장(`.git/sdd/progress.md`). 경고 44→5건, 테스트 384개 전체 통과.

**Goal:** 앱 코드에 쌓인 SwiftLint 경고 44건 중 ①(identifier_name 28건)·②(line_length 9건)를 정리하고, 남는 구조 경고를 의도된 잔여로 확정한다.

**Architecture:** 세 갈래로 나눠 처리한다 — (1) 보편 관례라 이름을 바꾸는 게 오히려 나쁜 것은 `.swiftlint.yml` 규칙 예외로 소멸시키고(코드 무변경), (2) 진짜 의미 축약은 이름을 제대로 붙이고, (3) 온디스크 직렬화 키인 것은 `CodingKeys`로 wire 문자열을 보존한 채 이름만 바꾼다. 동작 변경은 0이며, 기존 테스트 전체 그린이 그 증거다.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / SwiftLint 0.5x / XCTest

## Global Constraints

- 이 사이클은 **경량**이다(`docs/agent-rules/workflow.md` 24-32행). 문서의 서브에이전트 리뷰와 최종 브랜치 리뷰는 생략하고, **커밋 전 코드리뷰 1회·TDD·커밋 규칙은 유지**한다.
- **동작을 바꾸지 않는다.** 이 사이클의 모든 변경은 이름·줄바꿈·린트 설정뿐이다. 로직·조건·순서를 함께 손보고 싶어지면 멈추고 백로그로 넘긴다.
- **③(구조 경고)은 범위 밖이다** — `MapViewRepresentable` 672줄 분해는 그 자체로 마일스톤 1개 규모이고, 이번 사이클이 그 파일의 로직을 건드리지 않으므로 지금 정리해도 덕 볼 것이 없다(킥오프 스펙 §8.2). **따라서 완료 시점의 기대값은 경고 0이 아니라 5건이다.**
- 브랜치는 `feature/mvp17-lint-cleanup`(생성 완료). **push하지 않는다.**
- 커밋은 경로를 명시해 스테이징한다. `git add -A` / `git add .` 금지.
- 사용자의 GPX 관련 Xcode 설정 변경(`Trace.xcodeproj/project.pbxproj`, `Trace.xcodeproj/xcshareddata/xcschemes/Trace.xcscheme`)은 **이 사이클의 어떤 커밋에도 포함하지 않는다.** 워킹 트리에 그대로 둔다.
- `swiftlint --fix`를 쓰지 않는다. 과거 이 명령이 범위 밖 앱 파일을 건드려 되돌린 이력이 있다(백로그 기술부채 항목).

## 검증 명령

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

경고 건수만 빠르게 세는 명령(각 태스크의 검증에 쓴다):

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

## 경고 인벤토리 (2026-07-27 실측, 총 44건)

킥오프 스펙 §8.2가 예측한 28/9/7 분류와 실측이 정확히 일치한다. 다만 §8.2가 **몰랐던 것 하나**가 있다 — 아래 ①-C 참고.

| 갈래 | 건수 | 처분 | 태스크 |
|---|---|---|---|
| **①-A 보편 관례** (`i`×7, `j`×1, `a`×1, `b`×1) | 10 | `.swiftlint.yml` 규칙 예외 — 코드 무변경 | 1 |
| **①-B 의미 축약 (안전)** (`t`×2, `n`, `s`, `e`, `m`, `c`, `d`×6) | 13 | 이름을 제대로 붙인다 | 2 |
| **①-C 의미 축약 (직렬화 키)** (`t`×2, `s`, `e`, `d`) | 5 | `CodingKeys`로 wire 보존 + 이름 변경 | 3 |
| **② line_length** | 9 | 줄 나눔 | 4 |
| **③ 구조** | 7 | **범위 밖** (단 nesting 2건은 Task 1에서 부수 소멸) | — |

### ①-C — 이 마일스톤에서 가장 위험한 부분

`Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`의 `t`·`s`·`e`·`t`·`d` 5건은 **로컬 변수가 아니라 `Codable` 저장 프로퍼티**다. 이 파일은 러닝 기록을 JSON blob으로 SwiftData에 저장하는 어댑터이고, Swift는 `CodingKeys`가 없으면 **프로퍼티 이름을 그대로 JSON 키로 쓴다.**

즉 `let t: Date`를 `let timestamp: Date`로 그냥 바꾸면, 저장된 blob의 `{"t": ...}`를 더 이상 못 읽는다 → **사용자 기기에 이미 쌓인 러닝 기록이 전부 사라진다.** 새로 설치한 시뮬레이터에서는 아무 증상이 없고(저장된 데이터가 없으니), 기존 테스트 350개도 옛 포맷 픽스처가 없어서 못 잡는다.

**처분:** `CodingKeys`로 wire 문자열(`"t"`, `"s"`, `"e"`, `"d"`)을 고정하고 프로퍼티 이름만 바꾼다. 저장 포맷이 안 바뀌므로 `project-decisions.md`의 persistence 결정을 건드리지 않고, 지금 암묵적이던 "필드명 = 저장 키" 결합이 오히려 코드에 명시된다. Task 3은 이 안전성을 테스트로 먼저 못박은 뒤에 이름을 바꾼다.

## File Structure

| 파일 | 변경 내용 | 태스크 |
|---|---|---|
| `.swiftlint.yml` | `identifier_name.excluded`에 `i`·`j`·`a`·`b` 추가, `nesting.type_level` 2로 조정 | 1 |
| `Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift` | `t` → `projection` | 2 |
| `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift` | 패턴 바인딩 `d` → `distance` | 2 |
| `Trace/Domain/RunTracking/Entity/RunSplit.swift` | 파라미터 `t` → `time` | 2 |
| `Trace/Application/CoursePlanning/CourseEditSession.swift` | `n` → `coordinateCount` | 2 |
| `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` | `s`·`e` → `startKey`·`endKey`, `m` → `multiplier`, 56행 줄 나눔 | 2·4 |
| `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift` | `c` → `coordinate`, 패턴 바인딩 `d` → `distance` | 2 |
| `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift` | `CodingKeys` 3개 추가 + 저장 프로퍼티 5건 이름 변경 | 3 |
| `TraceTests/RunPersistenceDTOWireFormatTests.swift` | **신설** — 저장 포맷 고정 테스트 | 3 |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` | 긴 줄 7건 나눔 | 4 |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift` | 긴 줄 1건 나눔 | 4 |
| `docs/roadmap.md` · `docs/backlog.md` · `docs/agent-rules/project-decisions.md` | 마일스톤 종결 + 잔여 경고 기록 | 5 |

**태스크별 기대 경고 수:** 44 → (1) 32 → (2) 19 → (3) 14 → (4) 5

---

### Task 1: 보편 관례를 규칙 예외로 소멸시킨다

루프 인덱스 `i`/`j`와 기하 파라미터 `a`/`b`는 이름만 보고도 뭔지 안다. `index`·`pointA`로 바꾸면 오히려 낯설다. 규칙의 목적이 "이름만 보고 뭔지 알게 하는 것"이므로, 규칙이 그 차이를 잡도록 맞춘다(킥오프 스펙 §8.2).

`nesting`도 함께 조정한다. Task 3에서 `CodingKeys`를 추가하는데, `enum RunPersistenceDTO` > `struct Sample` > `enum CodingKeys`가 정확히 2레벨이라 **린트를 고치려다 nesting 위반 3건을 새로 만들게 된다.** Swift에서 "네임스페이스 enum + 중첩 DTO + CodingKeys"는 표준 관례이고, 기존 위반 2건도 같은 종류다(`CoursePersistenceDTO.Segment.Kind`, 그리고 ActivityKit이 `ContentState` 중첩을 **문법적으로 강제**하는 `RunActivityAttributes`). 규칙 기본값 1레벨이 이 프로젝트의 실제 패턴과 안 맞는 것이므로 2로 올린다.

> **범위 노트:** 이 조정으로 ③(범위 밖)에 속했던 nesting 2건이 부수적으로 소멸한다. 의도된 것이며, 남는 구조 경고가 7건이 아니라 5건이 되는 이유다. `MapViewRepresentable` 분해는 여전히 범위 밖이다.

**Files:**
- Modify: `.swiftlint.yml:44-49` (`identifier_name` 블록), `nesting` 블록 신설

**Interfaces:**
- Consumes: 없음
- Produces: 이후 모든 태스크의 린트 기준선. Task 3은 `nesting.type_level: 2`에 의존한다.

- [ ] **Step 1: 현재 경고 건수를 기록한다**

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

Expected: `44`

44가 아니면 **멈추고 보고한다.** 이 플랜의 모든 기대값이 44 기준이라, 다르면 그 사이 코드가 바뀐 것이므로 인벤토리를 다시 세야 한다.

- [ ] **Step 2: `.swiftlint.yml`을 수정한다**

`identifier_name` 블록을 아래로 교체한다(기존 `excluded`의 `id`·`x`·`y`는 유지하고 4개를 더한다):

```yaml
identifier_name:
  min_length:
    warning: 2
  excluded:
    # 짧아도 이름만 보고 뭔지 아는 것들만 예외로 둔다. 의미 축약(m, s, e, d 등)은
    # 예외가 아니라 이름을 제대로 붙이는 쪽으로 처리했다 (MVP17 lint-cleanup, 킥오프 스펙 §8.2).
    - id
    - x
    - y
    - i   # 루프 인덱스 — 보편 관례
    - j   # 중첩 루프 인덱스
    - a   # 기하 파라미터(선분 a-b) — doc comment와 이름이 일치
    - b
```

그리고 `identifier_name` 블록 **바로 아래**에 `nesting` 블록을 추가한다:

```yaml
# 기본값 1레벨은 이 프로젝트의 표준 패턴과 안 맞는다:
# ① 네임스페이스 enum > DTO struct > CodingKeys (직렬화 키 고정에 필수)
# ② ActivityKit은 ContentState를 ActivityAttributes 안에 중첩하도록 문법적으로 강제한다
# 2레벨까지만 허용하므로 그 이상의 진짜 과중첩은 여전히 잡힌다.
nesting:
  type_level:
    warning: 2
```

- [ ] **Step 3: 경고가 12건 줄었는지 확인한다**

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

Expected: `32` (44 − identifier 10 − nesting 2)

건수만이 아니라 **어떤 종류가 남았는지**도 확인한다:

```bash
swiftlint lint --quiet 2>/dev/null | grep -c "Variable name 'i'\|Variable name 'j'\|Variable name 'a'\|Variable name 'b'\|Nesting"
```

Expected: `0`

- [ ] **Step 4: 빌드와 전체 테스트가 그대로 통과하는지 확인한다**

린트 설정만 바꿨으니 당연히 통과해야 하지만, `.swiftlint.yml` YAML 문법 오류는 빌드 단계에서만 드러나는 경우가 있어 확인한다.

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점: 규칙 완화가 정당한 범위인지 — 특히 `nesting` 2레벨이 "진짜 과중첩"을 여전히 잡는지, `excluded` 목록에 의미 축약(`m`·`d`·`s`·`e`·`t`·`n`·`c`)이 섞여 들어가지 않았는지.

```bash
git add .swiftlint.yml
git commit -m "chore: 린트 규칙을 프로젝트 실제 관례에 맞춘다

루프 인덱스(i, j)와 기하 파라미터(a, b)를 identifier_name 예외로 둔다.
이름만 보고 뭔지 아는 것들이라 긴 이름이 오히려 읽기 나쁘다.
의미 축약은 예외가 아니라 이름을 고치는 쪽으로 간다(다음 커밋).

nesting은 2레벨까지 허용한다. 네임스페이스 enum > DTO > CodingKeys 구조와
ActivityKit이 강제하는 ContentState 중첩이 기본값 1레벨과 맞지 않는다.

경고 44 → 32건."
```

---

### Task 2: 의미 축약 13건에 제대로 된 이름을 붙인다

`m`은 이름만 봐서 모른다. 전부 로컬 변수·함수 파라미터·패턴 바인딩이라 호출부에 영향이 없다(직렬화 키인 5건은 Task 3에서 따로 다룬다).

**Files:**
- Modify: `Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift:30`
- Modify: `Trace/Domain/CoursePlanning/Entity/CourseSegment.swift:17`
- Modify: `Trace/Domain/RunTracking/Entity/RunSplit.swift:96-102`
- Modify: `Trace/Application/CoursePlanning/CourseEditSession.swift:162-164`
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift:62-71`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift:31-32, 43-45`

**Interfaces:**
- Consumes: Task 1의 `.swiftlint.yml` 기준선
- Produces: 없음(외부 시그니처 무변경). `RunSplit.activeSeconds(at:start:pauses:)`의 **외부 인자 레이블 `at`은 그대로**이므로 호출부는 손대지 않는다.

- [ ] **Step 1: `CourseCoordinate+Geo.swift`의 투영 파라미터 이름을 바꾼다**

30행. 선분 위로 투영한 위치를 0~1로 정규화한 값이다.

```swift
        let projection = max(0, min(1, -(ax * abx + ay * aby) / lengthSquared))
        let closestX = ax + projection * abx
        let closestY = ay + projection * aby
```

> `a`·`b`(18행 파라미터)는 Task 1에서 규칙 예외로 처리됐으므로 **손대지 않는다.**

- [ ] **Step 2: `CourseSegment.swift`의 패턴 바인딩 이름을 바꾼다**

17행. 바로 위 11행이 이미 `coords`를 쓰고 있으므로 대칭을 맞춘다.

```swift
    var distanceMeters: Double {
        switch self {
        case .tapped(_, let distance), .drawn(_, let distance), .roundTrip(_, let distance): return distance
        }
    }
```

- [ ] **Step 3: `RunSplit.swift`의 파라미터 내부 이름을 바꾼다**

96-98행. **외부 레이블 `at`은 유지**하므로 호출부는 바뀌지 않는다. doc comment의 `t`도 함께 고친다.

```swift
    /// 주어진 시점까지의 활동 시간 = 벽시계 경과 − [start, 그 시점]과 겹치는 일시정지 합
    private static func activeSeconds(
        at time: Date, start: Date, pauses: [RunPauseInterval]
    ) -> TimeInterval {
        let pausedOverlap = pauses.reduce(0.0) { total, pause in
            let overlapStart = max(pause.start, start)
            let overlapEnd = min(pause.end, time)
```

> 함수 본문에 `t`가 더 나오면 전부 `time`으로 바꾼다. `sed -n '94,115p'`로 본문 전체를 먼저 읽고 시작할 것.

- [ ] **Step 4: `CourseEditSession.swift`의 좌표 개수 변수 이름을 바꾼다**

162-164행.

```swift
        let coordinateCount = entries[index].segment.coordinates.count
        guard coordinateCount >= 2 else { return false }
        return totalCoordinateCount + coordinateCount <= Self.maxTotalCoordinates
```

- [ ] **Step 5: `MapKitCoursePlanningService.swift`의 캐시 키·배수 이름을 바꾼다**

62-71행.

```swift
    private func cacheKey(from start: CourseCoordinate, to end: CourseCoordinate) -> String {
        let startKey = "\(round(start.latitude, 5)),\(round(start.longitude, 5))"
        let endKey = "\(round(end.latitude, 5)),\(round(end.longitude, 5))"
        return "\(startKey)->\(endKey)"
    }

    private func round(_ value: Double, _ places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (value * multiplier).rounded() / multiplier
    }
```

> ⚠️ **캐시 키 문자열 포맷은 바뀌지 않는다** — 변수 이름만 바뀌고 보간 결과는 동일하다. `RouteCacheTests`가 이를 지킨다.

- [ ] **Step 6: `CoursePersistenceDTO.swift`의 파라미터·패턴 바인딩 이름을 바꾼다**

30-33행 (`_ c:`는 와일드카드 레이블이라 호출부 무변경):

```swift
extension CoursePersistenceDTO.Coordinate {
    init(_ coordinate: CourseCoordinate) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }
```

43-45행:

```swift
        case .tapped(_, let distance):    self.init(kind: .tapped, coordinates: coords, distanceMeters: distance)
        case .drawn(_, let distance):     self.init(kind: .drawn, coordinates: coords, distanceMeters: distance)
        case .roundTrip(_, let distance): self.init(kind: .roundTrip, coordinates: coords, distanceMeters: distance)
```

> ⚠️ 이 파일에서 **`lat`·`lon`·`kind`·`coordinates`·`distanceMeters`는 절대 건드리지 않는다.** 그것들은 저장된 코스 blob의 JSON 키다(린트 위반도 아니다). 바꾸는 것은 위 두 곳의 지역 이름뿐이다.

- [ ] **Step 7: 경고가 13건 줄고 테스트가 전부 통과하는지 확인한다**

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

Expected: `19` (32 − 13)

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **` — 350개 전부 통과.

**동작 무변경의 증거가 이 테스트 결과다.** 하나라도 실패하면 이름 변경 과정에서 로직을 건드린 것이므로 되돌리고 다시 한다.

- [ ] **Step 8: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점: 이름 변경이 **정말 이름뿐인지**(조건·연산자·순서가 함께 바뀐 곳이 없는지), 그리고 직렬화 키(`lat`/`lon`/`kind` 등)를 실수로 건드리지 않았는지.

```bash
git add Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift \
        Trace/Domain/CoursePlanning/Entity/CourseSegment.swift \
        Trace/Domain/RunTracking/Entity/RunSplit.swift \
        Trace/Application/CoursePlanning/CourseEditSession.swift \
        Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift \
        Trace/Infrastructure/Persistence/SwiftData/CoursePersistenceDTO.swift
git commit -m "refactor: 의미를 알 수 없는 축약 이름 13건을 제대로 붙인다

m → multiplier, s/e → startKey/endKey, n → coordinateCount 등.
전부 지역 변수·파라미터·패턴 바인딩이라 외부 시그니처와 저장 포맷은 그대로다.
동작 무변경 — 테스트 350개 전체 통과가 근거.

경고 32 → 19건."
```

---

### Task 3: 저장 포맷을 고정한 뒤 직렬화 키 이름을 바꾼다

**이 태스크가 이번 사이클에서 유일하게 데이터를 깨뜨릴 수 있는 곳이다.** `RunPersistenceDTO`의 `t`·`s`·`e`·`d`는 로컬 변수가 아니라 저장된 JSON blob의 키다.

TDD 순서가 평소와 다르다. 먼저 **현재 저장 포맷을 그대로 못박는 테스트**를 쓰고(지금 코드에서 통과한다), 그다음 `CodingKeys` 없이 이름을 바꿔서 **그 테스트가 실제로 실패하는 것을 눈으로 확인**한 뒤, `CodingKeys`를 넣어 다시 통과시킨다. 중간의 실패를 건너뛰면 이 테스트가 정말 무언가를 지키는지 알 수 없다.

**Files:**
- Create: `TraceTests/RunPersistenceDTOWireFormatTests.swift`
- Modify: `Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`

> ✅ **`project.pbxproj`를 건드리지 않아도 된다.** `TraceTests`는 `PBXFileSystemSynchronizedRootGroup`(`project.pbxproj:98-100`)이라 폴더에 파일을 두면 자동으로 타겟에 편입된다. 만약 빌드가 새 테스트를 못 찾는다면 멈추고 보고할 것 — `project.pbxproj`를 수정하면 사용자의 GPX 설정 변경이 같은 파일에 섞여 있어 커밋 분리가 까다로워진다.

**Interfaces:**
- Consumes: Task 1의 `nesting.type_level: 2` (이게 없으면 `CodingKeys` 3개가 새 경고를 만든다)
- Produces: `RunPersistenceDTO.Sample.timestamp` · `Pause.start` · `Pause.end` · `Waypoint.timestamp` · `Waypoint.distanceMeters`. 저장 키(`"t"`·`"s"`·`"e"`·`"d"`)와 `.domain` 프로퍼티 시그니처는 **변경 없음** — `SwiftDataRunRecordRepository`는 손대지 않는다.

- [ ] **Step 1: 저장 포맷을 고정하는 테스트를 쓴다**

`TraceTests/RunPersistenceDTOWireFormatTests.swift`를 새로 만든다. 이 테스트의 목적은 "코드가 어떻게 생겼든 디스크에 있는 바이트는 이 모양이어야 한다"를 못박는 것이다.

```swift
import XCTest
@testable import Trace

/// 저장된 러닝 기록 blob의 JSON 키를 고정한다.
///
/// `RunPersistenceDTO`의 필드 이름을 바꾸면 Swift는 조용히 JSON 키도 함께 바꾼다.
/// 그러면 사용자 기기에 이미 쌓인 기록을 못 읽게 되는데, 새로 설치한 환경에서는
/// 아무 증상이 없어서 눈으로는 절대 못 잡는다. 이 테스트가 그 경로를 막는다.
///
/// **이 테스트가 실패하면 이름을 되돌리거나 `CodingKeys`로 키를 보존할 것.**
/// 저장 포맷을 진짜로 바꾸려면 `currentVersion`을 올리고 마이그레이션을 설계해야 한다.
final class RunPersistenceDTOWireFormatTests: XCTestCase {

    /// v4 포맷으로 저장된 blob. 실제 앱이 써온 키 이름 그대로다.
    private let storedBlob = Data("""
    {
      "version": 4,
      "samples": [
        {"t": 700000000, "lat": 37.5665, "lon": 126.9780, "alt": 38.0, "spd": 2.5}
      ],
      "pauses": [
        {"s": 700000100, "e": 700000160}
      ],
      "goal": {"type": "distance", "value": 5000.0},
      "waypoints": [
        {"t": 700000200, "lat": 37.5670, "lon": 126.9785, "d": 1000.0}
      ]
    }
    """.utf8)

    func test_저장된_blob이_그대로_해독된다() throws {
        let decoder = JSONDecoder()
        let run = try decoder.decode(RunPersistenceDTO.Run.self, from: storedBlob)

        XCTAssertEqual(run.version, 4)

        let sample = try XCTUnwrap(run.samples.first)
        XCTAssertEqual(sample.domain.timestamp.timeIntervalSinceReferenceDate, 700_000_000, accuracy: 0.001)
        XCTAssertEqual(sample.domain.latitude, 37.5665, accuracy: 0.00001)
        XCTAssertEqual(sample.domain.altitudeMeters, 38.0, accuracy: 0.001)
        XCTAssertEqual(sample.domain.speedMetersPerSecond, 2.5, accuracy: 0.001)

        let pause = try XCTUnwrap(run.pauses?.first)
        XCTAssertEqual(pause.domain.start.timeIntervalSinceReferenceDate, 700_000_100, accuracy: 0.001)
        XCTAssertEqual(pause.domain.end.timeIntervalSinceReferenceDate, 700_000_160, accuracy: 0.001)

        let waypoint = try XCTUnwrap(run.waypoints?.first)
        XCTAssertEqual(waypoint.domain.timestamp.timeIntervalSinceReferenceDate, 700_000_200, accuracy: 0.001)
        XCTAssertEqual(waypoint.domain.totalDistanceMeters, 1000.0, accuracy: 0.001)
    }

    func test_새로_저장한_blob도_같은_키를_쓴다() throws {
        let run = RunPersistenceDTO.Run(
            version: RunPersistenceDTO.currentVersion,
            samples: [RunPersistenceDTO.Sample(
                SavedRunSample(
                    timestamp: Date(timeIntervalSinceReferenceDate: 700_000_000),
                    latitude: 37.5665, longitude: 126.9780,
                    altitudeMeters: 38.0, speedMetersPerSecond: 2.5
                )
            )],
            pauses: [RunPersistenceDTO.Pause(
                RunPauseInterval(
                    start: Date(timeIntervalSinceReferenceDate: 700_000_100),
                    end: Date(timeIntervalSinceReferenceDate: 700_000_160)
                )
            )],
            goal: RunPersistenceDTO.Goal(.distance(meters: 5000)),
            waypoints: [RunPersistenceDTO.Waypoint(
                RunWaypoint(
                    timestamp: Date(timeIntervalSinceReferenceDate: 700_000_200),
                    latitude: 37.5670, longitude: 126.9785,
                    totalDistanceMeters: 1000.0
                )
            )]
        )

        let encoded = try JSONEncoder().encode(run)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        let sample = try XCTUnwrap((json["samples"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(sample.keys), ["t", "lat", "lon", "alt", "spd"])

        let pause = try XCTUnwrap((json["pauses"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(pause.keys), ["s", "e"])

        let waypoint = try XCTUnwrap((json["waypoints"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(waypoint.keys), ["t", "lat", "lon", "d"])
    }
}
```

> **Date 인코딩 주의:** `JSONDecoder`/`JSONEncoder`의 기본 `dateEncodingStrategy`는 `.deferredToDate`이고, 이는 `Date`를 "2001-01-01 기준 초"인 실수로 직렬화한다. 위 blob의 `700000000` 같은 숫자와 `timeIntervalSinceReferenceDate` 비교는 그 전제를 따른 것이다. `SwiftDataRunRecordRepository`가 인코더 전략을 따로 설정하지 않는 것을 먼저 확인할 것(`grep -n "JSONEncoder\|dateEncoding" Trace/Infrastructure/Persistence/SwiftData/SwiftDataRunRecordRepository.swift`). 설정하고 있다면 테스트의 디코더/인코더에도 같은 전략을 준다.

- [ ] **Step 2: 테스트가 지금 코드에서 통과하는지 확인한다**

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -only-testing:TraceTests/RunPersistenceDTOWireFormatTests \
  -parallel-testing-enabled NO test
```

Expected: **PASS** (2개 테스트 모두)

여기서 실패하면 테스트가 현재 포맷을 잘못 적은 것이다. 이름을 바꾸기 전에 반드시 초록을 봐야 한다 — 그래야 다음 단계의 빨강이 "이름 변경 때문"임이 확실해진다.

- [ ] **Step 3: `CodingKeys` 없이 이름만 바꿔 테스트가 실제로 깨지는 것을 확인한다**

`RunPersistenceDTO.swift`의 struct 정의만 아래처럼 바꾼다. **`CodingKeys`는 아직 넣지 않는다.** 매핑 extension(51·58·66·70·94-95·99행)도 새 이름에 맞춰 고쳐야 컴파일된다.

```swift
    struct Sample: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double
    }

    struct Pause: Codable {
        let start: Date
        let end: Date
    }
```

```swift
    struct Waypoint: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        /// 탭 시점 누적 거리(m) — 표시용 캐시(스펙 §2.4)
        let distanceMeters: Double
    }
```

매핑 extension도 함께 수정한다:

```swift
extension RunPersistenceDTO.Sample {
    init(_ sample: SavedRunSample) {
        self.init(
            timestamp: sample.timestamp, lat: sample.latitude, lon: sample.longitude,
            alt: sample.altitudeMeters, spd: sample.speedMetersPerSecond
        )
    }

    var domain: SavedRunSample {
        SavedRunSample(
            timestamp: timestamp, latitude: lat, longitude: lon,
            altitudeMeters: alt, speedMetersPerSecond: spd
        )
    }
}

extension RunPersistenceDTO.Pause {
    init(_ interval: RunPauseInterval) {
        self.init(start: interval.start, end: interval.end)
    }

    var domain: RunPauseInterval {
        RunPauseInterval(start: start, end: end)
    }
}
```

```swift
extension RunPersistenceDTO.Waypoint {
    init(_ waypoint: RunWaypoint) {
        self.init(timestamp: waypoint.timestamp, lat: waypoint.latitude,
                  lon: waypoint.longitude, distanceMeters: waypoint.totalDistanceMeters)
    }

    var domain: RunWaypoint {
        RunWaypoint(timestamp: timestamp, latitude: lat, longitude: lon,
                    totalDistanceMeters: distanceMeters)
    }
}
```

같은 테스트를 다시 돌린다:

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -only-testing:TraceTests/RunPersistenceDTOWireFormatTests \
  -parallel-testing-enabled NO test
```

Expected: **FAIL** — `test_저장된_blob이_그대로_해독된다`가 `keyNotFound` 에러로 실패하고, `test_새로_저장한_blob도_같은_키를_쓴다`는 키 집합이 `["timestamp", "lat", ...]`로 나와 실패한다.

**이 빨강이 이 태스크의 존재 이유다.** 여기서 통과해버리면 테스트가 아무것도 안 지키고 있다는 뜻이므로 멈추고 보고한다.

- [ ] **Step 4: `CodingKeys`로 저장 키를 되돌린다**

세 struct에 `CodingKeys`를 추가한다. 이름이 그대로인 필드(`lat`·`lon`·`alt`·`spd`)도 **빠짐없이 나열해야 한다** — 하나라도 빠지면 그 필드가 인코딩·디코딩에서 누락된다.

```swift
    struct Sample: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        let alt: Double
        let spd: Double

        // 저장된 blob의 키는 압축형이다. 필드 이름을 바꿔도 여기가 포맷을 고정한다.
        enum CodingKeys: String, CodingKey {
            case timestamp = "t"
            case lat, lon, alt, spd
        }
    }

    struct Pause: Codable {
        let start: Date
        let end: Date

        enum CodingKeys: String, CodingKey {
            case start = "s"
            case end = "e"
        }
    }
```

```swift
    struct Waypoint: Codable {
        let timestamp: Date
        let lat: Double
        let lon: Double
        /// 탭 시점 누적 거리(m) — 표시용 캐시(스펙 §2.4)
        let distanceMeters: Double

        enum CodingKeys: String, CodingKey {
            case timestamp = "t"
            case lat, lon
            case distanceMeters = "d"
        }
    }
```

파일 상단 주석(3-5행)에도 이 사실을 남긴다:

```swift
// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (코스 DTO와 동일 원칙, 스펙 §2).
// 미래 심박·케이던스는 Run에 스트림 배열 하나를 옆에 추가 + version 증가로 끝난다(additive).
//
// ⚠️ 저장 키는 CodingKeys가 고정한다(용량을 아끼려 압축한 이름이다). 필드 이름은 자유롭게
// 바꿔도 되지만 CodingKeys의 문자열을 바꾸면 이미 저장된 기록을 못 읽는다.
// RunPersistenceDTOWireFormatTests가 이를 지킨다.
```

- [ ] **Step 5: 테스트가 다시 통과하는지 확인한다**

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -only-testing:TraceTests/RunPersistenceDTOWireFormatTests \
  -parallel-testing-enabled NO test
```

Expected: **PASS**

- [ ] **Step 6: 전체 테스트와 린트를 확인한다**

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **` — 기존 350개 + 신규 2개 = 352개.

특히 `SwiftDataRunRecordRepositoryTests`가 통과해야 한다. 저장→불러오기 왕복이 실제로 도는 경로다.

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

Expected: `14` (19 − 5)

nesting 위반이 새로 생기지 않았는지도 확인한다(Task 1의 `type_level: 2`가 제대로 걸렸는지 검증):

```bash
swiftlint lint --quiet 2>/dev/null | grep -c "Nesting"
```

Expected: `0`

- [ ] **Step 7: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점: `CodingKeys`가 **모든** 필드를 나열했는지(누락 시 그 필드가 조용히 사라진다), wire 문자열이 원래 값(`"t"`·`"s"`·`"e"`·`"d"`)과 정확히 같은지, `.domain` 매핑이 도메인 프로퍼티와 올바르게 연결됐는지(`timestamp`↔`timestamp`, `distanceMeters`↔`totalDistanceMeters`).

```bash
git add Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift \
        TraceTests/RunPersistenceDTOWireFormatTests.swift
git commit -m "refactor: 저장 키를 CodingKeys로 고정하고 DTO 필드 이름을 제대로 붙인다

RunPersistenceDTO의 t/s/e/d는 지역 변수가 아니라 저장된 JSON 키였다.
그냥 이름을 바꾸면 이미 저장된 러닝 기록을 못 읽게 되는데, 새로 설치한
환경에서는 증상이 없어 눈으로 못 잡는다.

CodingKeys로 wire 문자열을 고정한 뒤 이름만 바꿨다. 저장 포맷 무변경.
포맷을 고정하는 테스트를 먼저 쓰고, CodingKeys 없이 바꾸면 실제로
깨지는 것을 확인한 뒤 넣었다.

경고 19 → 14건."
```

---

### Task 4: 긴 줄 9건을 나눈다

기계적 수정이지만 **제약이 하나 있다.**

> ⚠️ **`updateUIView`(236~340행)는 이미 `function_body_length` 경고 상태다 — 91줄이고 warning 60, error 100.** 9건 중 250·251·298·311행이 **전부 이 함수 안**이라, 인자를 한 줄씩 펼치는 식으로 나누면 100줄을 넘겨 **경고가 error로 승격되고 pre-commit 훅이 커밋을 막는다.**
>
> 따라서 이 함수 안의 4줄은 **2줄짜리 최소 나눔**만 쓴다(한 줄당 +1). 함수 밖인 355·433·445·629행과 `ControlsComponent`는 여유가 있으므로 읽기 좋은 형태를 우선한다.
>
> 또 하나: 이 사이클의 Global Constraint는 "이름·줄바꿈·린트 설정뿐"이다. **줄을 나누면서 클로저를 추출하거나 `map` 구조를 바꾸지 않는다** — 그건 리뷰어가 범위 초과로 반려할 수 있는 유일한 변경이 된다.

250행은 123자로 걸리는데 바로 아래 251행은 120자로 통과한다. 대칭을 위해 251도 같은 형태로 맞추되, 위 줄 수 제약 때문에 **둘 다 2줄 형태**로만 나눈다(+2).

**Files:**
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift:56`
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:250-251, 298, 311, 355, 433, 445, 629`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift:15`

**Interfaces:**
- Consumes: 없음
- Produces: 없음(순수 포매팅)

- [ ] **Step 1: `MapKitCoursePlanningService.swift:56`을 나눈다**

```swift
            #if DEBUG
            print("[MapKitCoursePlanning] Unhandled error: "
                  + "domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
            #endif
```

- [ ] **Step 2: `MapViewRepresentable.swift:250-251`을 나눈다** *(함수 내부 — 최소 나눔)*

`.map` 뒤의 클로저 본문만 다음 줄로 내린다. **새 변수나 클로저를 만들지 않는다.** 중첩 `$0` 섀도잉은 지금 코드에도 이미 있는 형태라 그대로 컴파일된다.

```swift
                first: $0.coordinates.first
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                last: $0.coordinates.last
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
```

순증 +2줄.

- [ ] **Step 3: `MapViewRepresentable.swift:298`을 나눈다** *(함수 내부 — 최소 나눔)*

```swift
                    configureRenderer(renderer, segmentIndex: polyline.segmentIndex,
                                      colorKey: polyline.colorKey, selected: selectedSegmentIndex)
```

순증 +1줄.

- [ ] **Step 4: `MapViewRepresentable.swift:311`을 나눈다** *(함수 내부 — 최소 나눔)*

```swift
            MapPin(coordinate: $0.coordinate, title: $0.title ?? "", color: $0.color,
                   systemImage: $0.systemImage, role: $0.role)
```

순증 +1줄. **여기까지 함수 내부 순증은 +4줄이며, 91 + 4 = 95 < 100(error)이다.**

- [ ] **Step 5: `MapViewRepresentable.swift:354-356`을 나눈다**

```swift
        guard let selectedSegmentIndex,
              let casing = uiView.overlays.first(where: {
                  ($0 as? SegmentCasingPolyline)?.segmentIndex == selectedSegmentIndex
              }) as? SegmentCasingPolyline
        else { return }
```

- [ ] **Step 6: `MapViewRepresentable.swift:433`을 나눈다**

```swift
            parent.configureRenderer(
                renderer,
                segmentIndex: polyline.segmentIndex,
                colorKey: polyline.colorKey,
                selected: parent.selectedSegmentIndex
            )
```

- [ ] **Step 7: `MapViewRepresentable.swift:445`를 나눈다**

```swift
                let view = mapView
                    .dequeueReusableAnnotationView(withIdentifier: identifier) as? SegmentDistanceAnnotationView
                    ?? SegmentDistanceAnnotationView(annotation: distanceAnnotation, reuseIdentifier: identifier)
```

- [ ] **Step 8: `MapViewRepresentable.swift:629`를 나눈다**

```swift
                try? await Task.sleep(
                    until: .now + .seconds(Self.markerShowDelay),
                    tolerance: .zero,
                    clock: .continuous
                )
```

- [ ] **Step 9: `CoursePlannerPage+ControlsComponent.swift:15`를 나눈다**

```swift
                segmentToggleButton(
                    title: "경로 찍기",
                    systemImage: "mappin.and.ellipse",
                    isActive: !viewModel.isDrawingMode
                )
```

- [ ] **Step 10: 경고가 9건 줄고 테스트가 통과하는지 확인한다**

```bash
swiftlint lint --quiet 2>/dev/null | wc -l
```

Expected: `5`

```bash
swiftlint lint --quiet 2>/dev/null | grep -c "Line Length"
```

Expected: `0`

**severity가 승격되지 않았는지 확인한다.** 건수만 세면 warning이 error로 바뀐 것을 못 잡는다:

```bash
swiftlint lint --quiet 2>/dev/null | grep -c "error:"
```

Expected: `0`

`updateUIView`가 error 임계값(100줄) 아래인지 수치로 확인한다:

```bash
swiftlint lint --quiet 2>/dev/null | grep "Function Body Length"
```

Expected: `currently spans 95 lines` 안팎 — **100 미만이면 통과.** 100 이상이면 Step 2~4의 나눔이 과했다는 뜻이므로 더 압축된 형태로 되돌린다.

```bash
SIM_UDID="FAE97799-97D7-4B5F-8960-5B796686C702"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **` — 352개.

> `MapViewRepresentable`은 자동 테스트 커버리지가 얇은 UIKit 브리지다. 이번 변경은 순수 줄바꿈이라 위험이 낮지만, 확인 비용도 낮으므로 **시뮬레이터에서 코스 탭을 열어 구간이 정상 렌더링되는지 눈으로 한 번 확인한다**(빌드→실행→지도에 코스 그리기→구간 색·거리 라벨 표시 확인).

- [ ] **Step 11: 커밋 전 코드리뷰를 받고 커밋한다**

리뷰 초점: 줄 나눔이 **의미를 바꾸지 않았는지**(특히 Step 2의 클로저 추출과 Step 5의 `first(where:)` 재구성), 들여쓰기가 주변 코드 관례와 맞는지.

```bash
git add Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift \
        Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift \
        Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
git commit -m "style: 120자를 넘는 줄 9건을 나눈다

250행만 걸리고 251행은 통과했지만 두 줄이 대칭이라 함께 정리했다.

경고 14 → 5건."
```

---

### Task 5: 잔여 경고를 확정하고 마일스톤을 닫는다

경고 0이 아니라 **5건이 남는 것이 이 마일스톤의 정상 종료 상태**다. 그 사실과 이유를 문서에 남기지 않으면, 다음 세션이 "린트 정리했다는데 왜 경고가 있지?"에서 다시 시작한다.

**Files:**
- Modify: `docs/roadmap.md` (MVP17 `lint-cleanup` 체크박스)
- Modify: `docs/backlog.md` (기술부채 항목 — ①② 종결, ③ 존치)
- Modify: `docs/agent-rules/project-decisions.md` (린트 규칙 조정 기록)

**Interfaces:**
- Consumes: Task 1~4의 결과
- Produces: 없음

- [ ] **Step 1: 잔여 5건이 전부 ③인지 확인한다**

```bash
swiftlint lint --quiet 2>/dev/null | sed 's|/Users/seungchan/Documents/Trace/||'
```

Expected: 정확히 아래 5건.

| 파일:행 | 규칙 |
|---|---|
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:236` | cyclomatic_complexity (12) |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:236` | function_body_length (91줄) |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:150` | private_over_fileprivate |
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:672` | file_length (672줄) |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift:20` | type_body_length (322줄) |

> Task 4에서 줄을 나누면서 `MapViewRepresentable`의 총 줄 수가 늘어난다(672 → 690 안팎). file_length 경고 수치가 커지는 것은 정상이며, 이 파일 분해가 범위 밖이라는 판단은 그대로다.
>
> 이 목록과 다르면 **멈추고 보고한다.** 특히 identifier_name·line_length·nesting이 하나라도 남아 있으면 앞 태스크가 덜 끝난 것이다.

- [ ] **Step 2: `docs/roadmap.md`의 마일스톤을 완료로 바꾼다**

MVP17 섹션의 `lint-cleanup` 줄을 `- [ ]` → `- [x]`로 바꾸고 결과를 덧붙인다:

```markdown
- [x] **lint-cleanup** — 린트 ①(identifier_name 28건)·②(line_length 9건) 정리 완료. ①은 킥오프 §8.2 처분대로 갈랐다 — 보편 관례 10건(`i`·`j`·`a`·`b`)은 `.swiftlint.yml` 규칙 예외로 소멸, 의미 축약 18건은 이름을 제대로 붙였다. **그중 5건(`RunPersistenceDTO`)은 §8.2가 지역 변수로 오분류한 것이었고 실제로는 저장된 JSON 키였다** — 그냥 바꾸면 사용자 기기의 기존 러닝 기록이 해독 불가가 되는 경로라, `CodingKeys`로 wire 문자열을 고정한 뒤 이름을 바꾸고 포맷 고정 테스트(`RunPersistenceDTOWireFormatTests`)로 못박았다. `CodingKeys` 중첩 때문에 `nesting.type_level`을 2로 올렸고(ActivityKit `ContentState` 강제 중첩도 같은 이유), 그 부수 효과로 ③ 7건 중 nesting 2건이 함께 소멸했다. **잔여 경고 5건은 전부 ③(구조)이며 의도된 상태다** — `MapViewRepresentable` 분해는 여전히 별도 마일스톤 규모. 경고 44 → 5건, 테스트 352개 전체 통과. 구현 플랜: [`2026-07-27-lint-cleanup.md`](superpowers/plans/2026-07-27-lint-cleanup.md)
```

MVP17 섹션 헤더의 상태 문구도 갱신한다:

```markdown
### MVP17 — 러닝 기록 관리 + 대기 화면 보강   (상태: 마일스톤 4개 전부 완료 · 아카이빙 대기)
```

- [ ] **Step 3: `docs/backlog.md`의 기술부채 항목을 갱신한다**

"앱 코드 린트 경고 44건 — 세 갈래로 갈라서 처리" 항목(28행)의 상태를 `planned` → `done`으로 바꾸고 말미에 아래를 덧붙인다. ③은 **닫지 않고 새 항목으로 분리**한다.

```markdown
*resolved(2026-07-27):* MVP17 `lint-cleanup`에서 ①② 완료(경고 44 → 5건). 백로그가 ①을 "코드 수정 vs 규칙 조정" 양자택일로 적어둔 것은 킥오프 §8.2에서 "둘 다"로 정정됐고, 실행 단계에서 **한 번 더 정정됐다** — §8.2가 "의미 축약 18건"으로 묶은 것 중 5건(`RunPersistenceDTO`의 `t`·`s`·`e`·`d`)이 지역 변수가 아니라 **저장된 JSON 키**였다. 이름을 그냥 바꿨다면 사용자 기기에 쌓인 러닝 기록이 전부 해독 불가가 되고, 새로 설치한 환경에서는 증상이 없어 QA로도 못 잡혔을 것이다. `CodingKeys`로 wire 문자열을 고정해 저장 포맷을 무변경으로 유지하고 `RunPersistenceDTOWireFormatTests`로 못박았다. **교훈: 린트가 "짧은 이름"이라고 지적한 것이 사실은 의도적 압축인 경우가 있다 — Codable 저장 프로퍼티인지 먼저 확인할 것.** `done`
```

그리고 ③을 독립 항목으로 새로 만든다(같은 "기술부채" 섹션):

```markdown
- [ ] **린트 ③ 구조 경고 5건 — `MapViewRepresentable` 분해** — *what:* `MapViewRepresentable.swift`가 상한(500줄)을 넘겨 690줄 안팎이고, 그 안의 한 함수가 91줄·복잡도 12다. `CoursePlannerPageViewModel`도 클래스 본문 322줄로 상한(300)을 넘는다. 경고 5건: file_length·function_body_length·cyclomatic_complexity·private_over_fileprivate(`MapViewRepresentable`) + type_body_length(`CoursePlannerPageViewModel`). *why deferred:* 경고가 실제 설계 부담을 가리키는 경우라 **쪼개기 자체가 마일스톤 1개 규모**다. MVP17 `lint-cleanup`은 ①②만 범위로 잡았고(킥오프 §8.2), 그 사이클이 이 파일들의 로직을 건드리지 않았으므로 지금 정리해도 덕 볼 것이 없다. *trigger:* `MapViewRepresentable`이나 코스 편집 뷰모델을 어차피 크게 손볼 마일스톤이 생기면 그때 함께. 독립적으로 착수하면 "동작 무변경 리팩터링"의 검증 부담만 크고 얻는 것이 린트 경고 5건 소멸뿐이다. *참고:* 원래 ③은 7건이었으나 nesting 2건은 `lint-cleanup`에서 규칙 조정(`type_level: 2`)으로 소멸했다 — 그중 `RunActivityAttributes`는 ActivityKit이 `ContentState` 중첩을 문법적으로 강제해 **리팩터링으로는 애초에 못 고치는** 종류였다. `open`
```

- [ ] **Step 4: `docs/agent-rules/project-decisions.md`에 린트 규칙 조정을 기록한다**

`Current Defaults` 섹션 끝에 한 줄 추가한다. 규칙 파일을 열지 않고도 "왜 이 예외가 있는지"를 알 수 있어야 한다.

```markdown
- SwiftLint 규칙 조정 (결정 2026-07-27, MVP17 `lint-cleanup`): `identifier_name.excluded`에 `i`·`j`(루프 인덱스)·`a`·`b`(기하 파라미터)를 두고, `nesting.type_level`은 2로 올린다. 근거는 규칙의 목적("이름만 보고 뭔지 알게")이며, 의미 축약(`m`·`s`·`e`·`d` 등)은 예외가 아니라 이름을 고치는 쪽으로 처리했다. `nesting` 2레벨은 이 프로젝트의 두 표준 패턴이 요구한다 — 네임스페이스 enum > DTO struct > `CodingKeys`(저장 키 고정에 필수), ActivityKit이 강제하는 `ContentState` 중첩. **`RunPersistenceDTO`·`CoursePersistenceDTO`의 필드 이름은 저장된 JSON 키와 직결된다** — `CodingKeys`가 wire 문자열을 고정하고 있으므로 그 문자열은 포맷 마이그레이션 없이 바꾸지 않는다(`RunPersistenceDTOWireFormatTests`가 방어).
```

- [ ] **Step 5: 문서 변경을 검토하고 커밋한다**

리뷰 초점: 잔여 5건의 설명이 정확한지(특히 file_length 수치가 Task 4 이후 값으로 갱신됐는지), ③ 새 항목의 트리거가 실제로 판정 가능한지.

```bash
git add docs/roadmap.md docs/backlog.md docs/agent-rules/project-decisions.md
git commit -m "docs: lint-cleanup 마일스톤을 닫고 잔여 경고 5건을 확정한다

경고 44 → 5건. 남은 5건은 전부 ③(구조)이고 의도된 상태다 —
MapViewRepresentable 분해는 별도 마일스톤 규모라 범위 밖으로 뒀다.
③은 백로그에 독립 항목으로 분리해 트리거를 걸었다.

킥오프 §8.2가 지역 변수로 분류한 5건이 실제로는 저장 키였다는
정정도 백로그에 남겼다."
```

---

## 실기기 QA — 면제

`docs/agent-rules/workflow.md`(3항)는 "순수 로직·docs·리팩터링만 포함된 MVP는 면제"로 정한다. 이 마일스톤은 이름 변경·줄 나눔·린트 설정뿐이고 UI·제스처·위치·권한 동작을 바꾸지 않으므로 **별도 실기기 체크리스트를 만들지 않는다.**

다만 두 가지가 자동 검증으로 커버되어야 면제가 성립한다:

1. **저장/불러오기 회귀** — Task 3의 `RunPersistenceDTOWireFormatTests` + 기존 `SwiftDataRunRecordRepositoryTests`가 커버한다. 이게 이번 사이클에서 유일하게 사용자 데이터에 닿는 부분이다.
2. **지도 렌더링 회귀** — Task 4 Step 2의 클로저 재구성은 자동 테스트가 얇으므로, 같은 Step 10에서 시뮬레이터 육안 확인을 필수로 넣었다.

> **MVP17 아카이빙 전 남은 관문:** 킥오프 스펙 §8.3은 MVP 완료 판정을 "마일스톤 2 종료 시점에 러닝 탭 대기 화면을 실기기로 열어보고 최초 관찰('러닝 탭이 초라하다')이 해소됐는지 사용자가 직접 판정한다"로 정했다. 이 판정이 기록된 흔적이 없으므로, `trace-archive` **전에** 사용자에게 확인해야 한다. 이 마일스톤의 통과 조건은 아니다.

## 플랜 자체 검토 (2026-07-27)

- [x] 킥오프 §8.2의 처분(①은 규칙 예외 10건 + 코드 수정 18건, ②는 줄 나눔, ③은 범위 밖)이 Task 1·2·3·4에 1:1로 대응한다.
- [x] 실측 인벤토리(28/9/7 = 44건)가 §8.2의 예측과 일치함을 확인했고, 태스크별 기대 경고 수(44→32→19→14→5)가 산술적으로 맞는다.
- [x] §8.2가 "의미 축약 18건"으로 묶은 것 중 5건이 직렬화 키라는 **실측 기반 정정**을 Task 3에서 별도 태스크로 분리하고, 그 사실을 인벤토리 표와 Task 5의 문서 갱신에 전파했다.
- [x] Task 3의 TDD 순서가 "먼저 초록 → 일부러 빨강 → 다시 초록"임을 명시했다. 빨강을 건너뛰면 테스트가 무의미하다는 것도 적었다.
- [x] `CodingKeys`가 만들어낼 nesting 위반 3건을 Task 1에서 **선제적으로** 처리했다(태스크 순서 의존성을 Task 3 Interfaces에 명시).
- [x] 완료 기준이 "경고 0"이 아니라 "경고 5건"임을 Global Constraints·Task 5 Step 1·roadmap 문구 세 곳에 못박았다 — 검증 단계가 스스로 실패하지 않도록.
- [x] 동작 무변경의 증거를 "기존 테스트 350개 전체 통과"로 두고, 자동 테스트가 얇은 `MapViewRepresentable`에는 시뮬레이터 육안 확인을 추가했다.
- [x] 사용자의 GPX Xcode 설정 변경을 커밋에 섞지 않도록 Global Constraints에 명시하고, 모든 커밋을 경로 명시 `git add`로 적었다.
- [x] 실기기 QA 면제 판정의 근거(`workflow.md` 3항)와 그 면제가 성립하기 위한 조건 2개를 적었다.
- [x] §8.3의 미이행 관문(사용자의 "아직도 초라한가" 판정)이 이 마일스톤이 아니라 **아카이빙 전** 관문임을 구분해 기록했다.

### advisor 리뷰 반영 (2026-07-27)

- [x] **Task 4가 `function_body_length`를 warning에서 error로 승격시킬 뻔했다.** 250·251·298·311행이 전부 `updateUIView`(236~340행, 현재 91줄, error 임계값 100) 안이라, 원안의 "인자 한 줄씩 펼치기"는 +13줄로 100을 넘겨 pre-commit 훅에 막혔을 것이다. 함수 내부 4줄을 2줄짜리 최소 나눔(+4)으로 교체하고, 검증에 `grep -c "error:"`와 실제 줄 수 확인을 추가했다 — 경고 **건수**만 세면 severity 승격을 못 잡는다.
- [x] **Task 4 Step 2가 이 사이클의 Global Constraint를 스스로 어겼다.** 원안은 `toCL` 클로저를 추출해 `map` 구조를 바꿨는데, 이는 "이름·줄바꿈·린트 설정뿐"이라는 제약을 넘어 리뷰어가 범위 초과로 반려할 수 있는 유일한 변경이었다. 순수 줄바꿈으로 교체했다(중첩 `$0` 섀도잉은 현재 코드에 이미 있는 형태).
- [x] **새 테스트 파일이 `project.pbxproj`를 건드리는지 확인했다.** `TraceTests`가 `PBXFileSystemSynchronizedRootGroup`이라 자동 편입되므로 안전하다 — 아니었다면 사용자의 GPX 설정 변경과 같은 파일에 섞여 부분 스테이징이 필요했을 것이다. Task 3에 근거와 함께 명시했다.
