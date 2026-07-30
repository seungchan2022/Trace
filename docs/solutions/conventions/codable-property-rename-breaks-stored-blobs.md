---
title: "저장된 blob의 키는 프로퍼티 이름에 묶여 있다 — 이름을 바꾸기 전에 Codable인지 먼저 확인한다"
date: 2026-07-30
category: conventions
module: RunTracking persistence
problem_type: convention
component: RunPersistenceDTO
severity: critical
applies_when:
  - "린트 경고(identifier_name 등)를 근거로 프로퍼티 이름을 일괄 변경하려 할 때"
  - "짧거나 의미를 알기 어려운 프로퍼티 이름을 정리하려 할 때"
  - "Codable 타입의 필드를 추가·삭제·개명할 때"
tags:
  - codable
  - swiftdata
  - persistence
  - lint
  - data-loss
---

## Context

MVP17 `lint-cleanup` 마일스톤에서 SwiftLint `identifier_name` 경고 28건을 정리하려 했다.
킥오프 스펙(§8.2)은 서면 검토만으로 이 경고들을 "의미를 알 수 없는 축약 로컬 변수"로 분류했다.

실행 직전 재확인에서 그중 5건이 로컬 변수가 아니라는 것이 드러났다 —
`RunPersistenceDTO`의 `t`·`s`·`e`·`d`는 **SwiftData에 저장된 JSON blob의 키**였다.

그대로 이름을 바꿨다면 사용자 기기에 쌓인 기존 러닝 기록이 전부 해독 불가가 된다.
게다가 **새로 설치한 환경에서는 증상이 없다** — 저장된 데이터가 없으니 인코딩과 디코딩이
새 이름으로 일관되게 동작한다. 실기기 QA로도 잡히지 않는 경로였다.

## Guidance

**Codable 타입의 프로퍼티 이름은 코드 식별자가 아니라 저장 포맷 계약이다.**
`CodingKeys`가 없으면 프로퍼티 이름이 곧 wire 키가 되고, 이름을 바꾸는 순간 계약이 깨진다.

세 단계로 처리한다.

1. **이름을 바꾸기 전에 그 타입이 `Codable`을 채택하는지 확인한다.**
   채택한다면 그 프로퍼티는 저장 포맷의 일부다.
2. **`CodingKeys`로 wire 문자열을 먼저 고정한다.** 그러면 필드 이름은 자유롭게 바꿔도
   저장 포맷이 움직이지 않는다.
3. **포맷을 테스트로 못박는다.** 실제 blob을 디코딩하는 테스트와, 새로 인코딩한 결과의
   키 집합을 검사하는 테스트 둘 다 둔다.

`Trace/Infrastructure/Persistence/SwiftData/RunPersistenceDTO.swift`는 이 순서를 적용한 뒤
파일 상단에 경고를 남겨두었다.

```swift
// ⚠️ 저장 키는 CodingKeys가 고정한다(용량을 아끼려 압축한 이름이다). 필드 이름은 자유롭게
// 바꿔도 되지만 CodingKeys의 문자열을 바꾸면 이미 저장된 기록을 못 읽는다.
// RunPersistenceDTOWireFormatTests가 이를 지킨다.
```

## Why This Matters

린트는 "짧은 이름 = 나쁜 이름"으로만 본다. **의도적인 압축을 구분하지 못한다.**

`t`·`s`·`e`·`d`는 읽기 어려워서 짧은 게 아니라, 러닝 한 번에 수천 개씩 쌓이는 샘플의
저장 용량을 줄이려고 일부러 한 글자로 만든 것이다. 린트 경고를 그대로 따랐다면
설계 의도를 지우면서 데이터까지 잃었을 것이다.

이 실패 경로의 위험한 점은 **조용하다는 것**이다.

- 컴파일은 통과한다
- 테스트도 통과한다 (기존 테스트가 새로 만든 객체만 다룬다면)
- 신규 설치 환경에서는 아무 증상이 없다
- **기존 사용자의 기기에서만, 앱을 업데이트한 뒤에 기록이 사라진다**

발견 시점이 배포 후라면 복구할 방법이 없다. 저장된 blob은 이미 옛 키로 쓰여 있는데
코드는 새 키만 찾기 때문이다.

## When to Apply

- 린트 경고를 근거로 이름을 **일괄** 변경할 때 (자동 수정 포함)
- `swiftlint --fix`처럼 도구가 알아서 고치도록 맡길 때 — 이 경로가 가장 위험하다
- Codable 타입에 필드를 추가·삭제할 때 (추가는 대체로 안전하나 디코딩 실패 조건을 확인한다)
- 저장소 스키마를 손대는 모든 작업

해당 없는 경우: 진짜 로컬 변수, 함수 파라미터, `Codable`을 채택하지 않는 타입.

## Examples

**바꾸기 전 — 프로퍼티 이름이 곧 저장 키다**

```swift
struct Sample: Codable {
    let timestamp: Date
    let lat: Double
    let lon: Double
    let alt: Double
    let spd: Double
}
// 저장된 blob: {"timestamp": ..., "lat": ..., "spd": ...}
// spd → speed 로 바꾸면 기존 blob의 "spd" 키를 못 찾는다
```

**고친 뒤 — `CodingKeys`가 계약을 고정한다**

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
```

**테스트로 못박기** (`TraceTests/RunPersistenceDTOWireFormatTests.swift`)

```swift
func test_저장된_blob이_그대로_해독된다() throws { ... }

func test_새로_저장한_blob도_같은_키를_쓴다() throws {
    XCTAssertEqual(Set(sample.keys), ["t", "lat", "lon", "alt", "spd"])
    XCTAssertEqual(Set(pause.keys), ["s", "e"])
    XCTAssertEqual(Set(waypoint.keys), ["t", "lat", "lon", "d"])
}
```

두 테스트가 짝이다. 앞의 것은 **과거에 저장된 데이터**를 읽을 수 있는지, 뒤의 것은
**앞으로 저장할 데이터**가 같은 키를 쓰는지 확인한다. 하나만 있으면 한쪽 방향의 회귀를 놓친다.

## References

- 적용 커밋: `954af3f` — 저장 키를 CodingKeys로 고정
- 발견 경위: `history/mvp17/260727_mvp17_completion_retro.md` (Keep · Surprise 절)
- 킥오프의 최초 오분류: `history/mvp17/2026-07-21-mvp17-run-history-kickoff-design.md` §8.2
