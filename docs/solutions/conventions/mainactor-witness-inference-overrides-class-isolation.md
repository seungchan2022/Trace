---
title: "프로토콜을 채택하면 클래스의 @MainActor가 무시된다 — async 요구사항 한정"
date: 2026-08-04
category: conventions
module: Domain protocols / Infrastructure adapters
problem_type: convention
component: LocationServiceProtocol, CoursePlanningServiceProtocol, RunLocationStreamProtocol
severity: high
applies_when:
  - "Domain 프로토콜에서 @MainActor를 떼려 할 때"
  - "@MainActor 클래스가 '자기 자신의 프로퍼티를 nonisolated context에서 못 만진다'는 에러를 낼 때"
  - "구현체에 nonisolated를 붙이면 컴파일이 통과한다는 유혹이 생길 때"
tags:
  - concurrency
  - mainactor
  - swift6
  - se-0461
  - protocol-conformance
---

# 요약

**`@MainActor` 클래스가 nonisolated한 `async` 프로토콜 요구사항을 witness하면, 클래스에 붙은
`@MainActor`가 그 멤버에 적용되지 않는다.** 멤버에 `@MainActor`를 **명시**해야 한다.

프로토콜 채택 한 줄이 있고 없고의 차이다. 채택이 없으면 클래스의 `@MainActor`는 정상 적용된다.

# 증상

```
error: main actor-isolated property 'manager' can not be mutated from a nonisolated context
error: call to main actor-isolated instance method 'addWaiter' in a synchronous nonisolated context
```

`@MainActor final class CoreLocationService`가 **자기 자신의** `manager`를 못 만진다고 나온다.
클래스에 `@MainActor`가 분명히 붙어 있는데도 그렇다.

# 최소 재현 (10줄)

```swift
protocol P { func f() async }

@MainActor final class C: P {
    var x = 0
    func f() async { x += 1 }   // ❌ error
}
```

```bash
swiftc -swift-version 6 \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  -typecheck repro.swift
```

이 두 upcoming feature는 이 프로젝트의 `SWIFT_APPROACHABLE_CONCURRENCY = YES`가 켜는 것들이다.

# 원인

`@MainActor`가 멤버에 적용되는 것은 **추론**이다. 프로토콜 witness가 되면 **요구사항으로부터의
격리 추론**도 함께 걸린다. Swift 6.2의 [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)이
nonisolated한 `async` 요구사항을 `nonisolated(nonsending)`(호출자 액터에서 실행)로 바꿔놓았기
때문에, **멤버에 명시가 없으면 요구사항 쪽 격리가 클래스 쪽 추론을 이긴다.**

멤버에 직접 쓴 `@MainActor`는 추론이 아니라 **명시**라서 둘 다 이긴다.

⚠️ **이것이 의도된 설계인지 컴파일러 빈틈인지는 확인하지 못했다.** SE-0461 원문에 프로토콜
witness와 격리 추론의 상호작용이 **아예 나오지 않는다**(원문 확인함). 관련 이슈로 보이는
[swiftlang/swift#86976](https://github.com/swiftlang/swift/issues/86976)은 **반대 방향**
(conformance가 격리로 잘못 추론됨) 사례라 근거가 되지 않는다. **"Swift 버그"라고 단정하지 말 것.**

# 검증한 해법 매트릭스 (2026-08-04, Swift 6.2 / Xcode 26)

| 방법 | 결과 | 비고 |
|---|---|---|
| 아무 조치 없음 | ❌ | 위 증상 |
| **멤버에 `@MainActor` 명시** | ✅ | **채택한 방법** |
| 프로토콜에 `@MainActor` | ✅ | 원래 상태 — Domain이 실행 컨텍스트를 강제하게 됨 |
| 격리된 conformance (`extension C: @MainActor P`) | ❌ | **동기 요구사항에는 통하나 async에는 안 통함** |
| 요구사항을 `@concurrent`로 | ❌ | |
| `nonisolated` + `await MainActor.run { }` | ✅ | 🛑 **금지** — 아래 참조 |
| `SWIFT_APPROACHABLE_CONCURRENCY = NO` | ✅ | 프로젝트 전체 동시성 모델 후퇴 |
| **요구사항이 동기(`async` 없음)** | ✅ | `InferIsolatedConformances`가 격리 conformance를 추론해 해소 |
| 프로토콜 채택 자체가 없음 | ✅ | 클래스 `@MainActor`가 정상 적용 |

# 🛑 `nonisolated`를 붙이지 말 것

`nonisolated`만 붙이면 컴파일이 안 된다(메인 액터 상태 접근 불가). 통과시키려면 모든 상태 접근을
`await MainActor.run { }`으로 감싸야 하는데, **그 순간 동작이 바뀐다** — 메서드 전체가 메인에서
한 덩어리로 돌던 것이 "잠깐 들렀다 나오기"의 연속이 되어 사이사이에 끼어들기가 생긴다.

`CoreLocationService`의 `ContinuationBroadcaster`(겹친 요청을 같은 결과로 묶는 로직)가 정확히
이 끼어들기에 깨지는 코드다. 그리고 *"메인 아니어도 된다"*고 선언했다가 실제로는 메인이어야
했던 것이 **MVP12에서 실기기 크래시를 낸 방식**이다(`18fa11a`).

멤버 `@MainActor` 명시는 **동작을 바꾸지 않는다.** 원래 메인에서 돌던 것을 컴파일러에게 다시
말해줄 뿐이다.

# 적용한 곳

- `CoreLocationService.currentLocation()`
- `MapKitCoursePlanningService.route(from:to:)`
- `RunLocationTracker.requestSessionFullAccuracy()`

# 언제 이 3줄을 지울 수 있나

**기다릴 필요 없다. 지우고 빌드하면 답이 나온다.** 통과하면 Swift가 이 자리를 채운 것이므로
지워도 된다. 2026-08-04 기준 Swift 6.2에서는 깨진다.

의미상 이 일을 맡아야 할 문법은 **격리 conformance**(`extension C: @MainActor P`)인데, 위
매트릭스대로 아직 `async` 요구사항을 커버하지 못한다. 그것이 확장되면 3줄은 사라질 수 있다.

# 더 근본적인 해법 (마일스톤 규모)

`CLLocationManager`를 actor로 감싸 **요구사항에서 `async`를 없애면** 이 문제 자체가 소멸한다
(위 매트릭스의 "요구사항이 동기" 행). 백그라운드 위치 구현체가 실제로 필요해지는 시점이 그
트리거다. 정비 사이클에서 할 일이 아니다.

# 곁다리 소득 — 테스트 스텁에서 `@MainActor` 9개 제거

이 작업 중 테스트 스텁 9개(`StubCoursePlanningService`·`SpyMapKitService`·`MockRunLocationStream`
등)가 `@MainActor`를 달고 있는 것을 발견했다. 카운터를 올리고 값을 돌려주는 게 전부라 **메인
스레드가 전혀 필요 없는** 것들이었고, 프로토콜에서 `@MainActor`가 빠지자 오히려 걸림돌이 됐다.
전부 제거했고 테스트 383개가 그대로 통과한다.

**교훈: 프로토콜에 `@MainActor`가 붙어 있으면 구현체들이 "필요해서"가 아니라 "따라서" 붙는다.**
프로토콜에서 떼면 진짜로 필요한 곳이 어디인지가 드러난다.
