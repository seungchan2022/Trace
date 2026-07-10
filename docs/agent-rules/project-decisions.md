# Project Decisions

This file records defaults until the user chooses otherwise.

## Current Defaults

- App name: `Trace`
- Repository: `seungchan2022/Trace`
- Platform: iOS
- Language: Swift
- UI framework: SwiftUI
- Minimum iOS version: iOS 17.0
- Xcode project: `Trace.xcodeproj`
- Xcode scheme: `Trace`
- Bundle identifier: `com.luke.Trace`
- Test targets: `TraceTests`, `TraceUITests`
- Test framework: XCTest
- Presentation architecture: MVVM
- Dependency injection: `DependencyContainer` with protocol-based services
- Architecture direction: page-first MVVM presentation with Clean Architecture boundaries
- Modularization: not active yet, but code should be structured so `Domain`, `Application`, `Infrastructure`, and `Pages` can later move into Swift Package modules
- Persistence: SwiftData, local-only (결정 2026-07-07, MVP11) — Domain의 `CourseRepositoryProtocol` 뒤에 격리, SwiftData `@Model`은 `Trace/Infrastructure/Persistence/SwiftData/` 어댑터 내부 전용(도메인 모델과 분리, 좌표 배열은 Codable `Data`로 저장). 초안(작업 중 코스)은 편집 연산 확정 시마다 + 백그라운드 진입 시 자동 저장하고 redo 스택은 저장하지 않는다. 이름 저장 코스는 스냅샷 의미론(저장 후 편집해도 저장본 불변, 중복 이름 허용). 상세: `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md` §2
 **(2026-07-08 정정)** 초안(작업 중 코스) 자동 저장·복원은 제거됨 — 완전 종료 후에는
 빈 상태로 시작. 저장 코스(이름 붙여 저장) 기능은 이 결정과 무관하게 SwiftData로 유지.
- Backend: none by default
- Authentication: none by default
- Analytics: none by default
- Monetization: none by default
- Product focus: plan a running route before the run, not record completed runs
- First MVP: tap start and destination on a map, show an actual walking route and total distance
- Course planning provider for MVP: Apple `MapKit` / `MKDirections` with `.walking`
- Course planning provider architecture: port-and-adapter via `CoursePlanningServiceProtocol`
- Course planning domain boundary: course planning models live under `Trace/Domain/CoursePlanning/Entity`; course planning protocols live under `Trace/Domain/CoursePlanning/Protocol`
- Course planning infrastructure boundary: concrete provider adapters live under `Trace/Infrastructure/CoursePlanning/{Provider}`
- Course planner page boundary: page code lives under `Trace/Pages/CoursePlannerPage`; page-only subviews live under `UIComponent` and use `{PageName}Page+{Role}Component.swift` filenames
- Course planner state: iOS 17+ Observation API with `@Observable`, not `ObservableObject` / `@Published`
- Course planner concurrency: Swift 6 style `async`/`await` with `@MainActor` UI state isolation
- Map/routing sequencing: build provider-agnostic features first; keep the map SDK confined to the page view (`CoursePlannerPage`). Do not swap the map display or routing provider preemptively. The eventual swap is a localized view-layer rewrite, not a feature rebuild — feature logic lives in the ViewModel/Domain/Infrastructure layers (the ViewModel does not import MapKit).
- MapKit walking routes in Korea: verified working on 2026-06-20 by calling the real `MKDirections` `.walking` path with Korean coordinates (강남→역삼 849m, 시청→광화문 1007m; control SF 1226m, all returned routes). Routing is therefore not a near-term blocker; an earlier assumption that it fails in Korea was wrong.
- Course attach rule: "그린 방향 = 달리는 방향" — MVP3의 자동 방향 감지(4쌍 거리 비교 + 스트로크 뒤집기)는 왕복 시 판정이 흔들려 MVP9(2026-07-03)에서 제거. 임계값(20m) 기반 순서 규칙으로 교체: ① 닫힌 코스면 무조건 append ② 시작점이 도착점 근접이면 append ③ 시작점이 출발점 근접이면 반전 prepend(출발 방향 연장 — 유일한 반전 예외) ④ 그 외 원거리 스트로크는 양끝 중 두 핀 어느 쪽에든 더 가까운 쪽(anchor — "어느 끝이 더 가까운가"도 단일 상대 비교 `<`로 정하며, 스트로크 양끝 4쌍 독립 비교가 아니다)을 골라 그 anchor를 두 끝점과 최근접 비교(탭 nearestEndpoint와 동일, 마진 없는 `<=`)해 출발점 쪽이면 반전 prepend + gap 라우팅, 도착점 쪽이면 gap append (MVP10 재설계, 2026-07-05; 원거리도 양끝 대칭 처리로 확장, 2026-07-06 — 닫힌 코스는 이 로직 밖이라 규칙 ①이 그대로 적용됨). 단, 근접(threshold 이내) 판정에 한해서만 끝점도 대칭적으로 봐서, 반대 방향(먼 지점→핀 근처)으로 그은 스트로크도 놓치지 않게 했다: 시작점이 두 핀 모두에서 멀어도 끝점이 출발점/도착점에 근접하면, 두 근접 여부가 동시에 참일 수 있는 경우(근접-루프)에도 순서 의존 없이 `<=` 상대 비교로 결정한다(실기기 QA 전 스크린샷 검토, 2026-07-05). 상세: `history/mvp9/2026-07-03-edit-consistency-design.md`(구 규칙 이력) + `history/mvp10/2026-07-05-attach-nearest-fallback-design.md`.
- Planning/spec document language: Korean by default
- Development tooling: Codex and Claude Code are used interchangeably across sessions; rules, prompts, plans, and git are shared in the repo, while only the entry file (`AGENTS.md` / `CLAUDE.md`) and the command directory are tool-specific. See `docs/agent-rules/dual-tool.md`.
- Workflow plugins: `superpowers`, `compound-engineering`, and `XcodeBuildMCP` are installed in both tools; every execute→review cycle ends with `ce-compound` to capture reusable lessons. See `docs/agent-rules/skills.md` and `docs/prompts/setup-claude.md`.
- Advisor usage (Claude Code): consult the Opus advisor only at decision points (approach choice, recurring failure, completion check), not every turn; the advisor advises while the main model writes. See `docs/agent-rules/dual-tool.md`. (Which model/effort/advisor the user runs is per-tool config set with `/model` `/effort` `/advisor`, not a repo rule.)
- Swift 언어 모드: Swift 6 (2026-07-10, MVP12) — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 유지 + 비-UI 타입(nonisolated)·Domain 프로토콜(nonisolated protocol) 명시 전략. 새 타입 작성 시 이 규칙을 따른다. 상세: `docs/superpowers/specs/2026-07-10-swift6-migration-design.md` §1

## Decisions the User May Need to Make Later

- Whether data is local-only or synced
- Whether login is required
- Privacy constraints
- App icon/name/subtitle
- Whether TestFlight, App Store release, or private use is the target
- When to replace `MapKit` with a Korea-focused map/routing provider — trigger is a *measured* quality gap (render real Korean walking routes and compare against Naver/Kakao), not an untested assumption. Provider choice (Naver/Kakao/Tmap) is a separate later decision; pedestrian routing availability differs by provider.
- ~~When to add course saving after the route planner MVP works~~ — MVP11(2026-07-07)에서 착수. 백로그 제거(2026-07-04)는 기능 불필요가 아니라 "방향성 없는 자동 1순위" 방지였고, 브레인스토밍으로 러닝 전→중→후 그림을 세운 뒤 그 기반으로 착수
- **MKDirections 스로틀 완화** — MVP3(2026-06-25)에서 증분 계산(새 구간만 라우팅)으로 해결. 60초당 50요청 근본 한계는 유지되나 체감 개선. 근본책(맵매칭 제공자)은 여전히 미래 옵션.
- **SwiftUI Map → MKMapView 교체 시점** — 그리기 중 지도 이동(2손가락 패닝)을 위해 필요. SwiftUI Map 위 오버레이로는 UIKit 제스처 전달 불가 (hit-test 소유권 문제). 교체 시 MapPolyline/Marker/UserAnnotation을 MKOverlay/MKAnnotation delegate 방식으로 전환. 리서치 완료(2026-06-25).
- **iOS 18.x @Observable malloc 크래시** — Apple 런타임 버그 (swiftlang/swift#87316, #85663). `@MainActor` 클래스 해제 시 `swift_task_deinitOnExecutorImpl()`이 정적 메모리를 `free()` → SIGABRT. 결정: iOS 26+ 시뮬레이터 사용이 근본 우회책. iOS 18에서 테스트해야 할 경우 ViewModel에 `nonisolated deinit { }` 추가. 상세: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`.

## Decision Policy

- If a decision affects architecture, privacy, persistence, account creation, cost, or App Store behavior, ask the user.
- If a decision is only local code style or project organization, choose the documented default and update this file.
