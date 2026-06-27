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
- Persistence: undecided
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
- Planning/spec document language: Korean by default
- Development tooling: Codex and Claude Code are used interchangeably across sessions; rules, prompts, plans, and git are shared in the repo, while only the entry file (`AGENTS.md` / `CLAUDE.md`) and the command directory are tool-specific. See `docs/agent-rules/dual-tool.md`.
- Workflow plugins: `superpowers`, `compound-engineering`, and `XcodeBuildMCP` are installed in both tools; every execute→review cycle ends with `ce-compound` to capture reusable lessons. See `docs/agent-rules/skills.md` and `docs/prompts/setup-claude.md`.
- Advisor usage (Claude Code): consult the Opus advisor only at decision points (approach choice, recurring failure, completion check), not every turn; the advisor advises while the main model writes. See `docs/agent-rules/dual-tool.md`. (Which model/effort/advisor the user runs is per-tool config set with `/model` `/effort` `/advisor`, not a repo rule.)

## Decisions the User May Need to Make Later

- Whether data is local-only or synced
- Whether login is required
- Privacy constraints
- App icon/name/subtitle
- Whether TestFlight, App Store release, or private use is the target
- When to replace `MapKit` with a Korea-focused map/routing provider — trigger is a *measured* quality gap (render real Korean walking routes and compare against Naver/Kakao), not an untested assumption. Provider choice (Naver/Kakao/Tmap) is a separate later decision; pedestrian routing availability differs by provider.
- When to add course saving after the route planner MVP works
- **MKDirections 스로틀 완화** — MVP3(2026-06-25)에서 증분 계산(새 구간만 라우팅)으로 해결. 60초당 50요청 근본 한계는 유지되나 체감 개선. 근본책(맵매칭 제공자)은 여전히 미래 옵션.
- **SwiftUI Map → MKMapView 교체 시점** — 그리기 중 지도 이동(2손가락 패닝)을 위해 필요. SwiftUI Map 위 오버레이로는 UIKit 제스처 전달 불가 (hit-test 소유권 문제). 교체 시 MapPolyline/Marker/UserAnnotation을 MKOverlay/MKAnnotation delegate 방식으로 전환. 리서치 완료(2026-06-25).
- **iOS 18.x @Observable malloc 크래시** — Apple 런타임 버그 (swiftlang/swift#87316, #85663). `@MainActor` 클래스 해제 시 `swift_task_deinitOnExecutorImpl()`이 정적 메모리를 `free()` → SIGABRT. 결정: iOS 26+ 시뮬레이터 사용이 근본 우회책. iOS 18에서 테스트해야 할 경우 ViewModel에 `nonisolated deinit { }` 추가. 상세: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`.

## Decision Policy

- If a decision affects architecture, privacy, persistence, account creation, cost, or App Store behavior, ask the user.
- If a decision is only local code style or project organization, choose the documented default and update this file.
