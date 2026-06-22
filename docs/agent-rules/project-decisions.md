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

## Decisions the User May Need to Make Later

- Whether data is local-only or synced
- Whether login is required
- Privacy constraints
- App icon/name/subtitle
- Whether TestFlight, App Store release, or private use is the target
- When to replace `MapKit` with a Korea-focused map/routing provider — trigger is a *measured* quality gap (render real Korean walking routes and compare against Naver/Kakao), not an untested assumption. Provider choice (Naver/Kakao/Tmap) is a separate later decision; pedestrian routing availability differs by provider.
- When to add course saving after the route planner MVP works
- **MKDirections 스로틀 완화 (다음 MVP 개선 1순위)** — 마커 그리기는 편집마다 전체 경로를 재라우팅해 60초당 50요청 한계(`GEOErrorDomain Code=-3`)에 쉽게 걸린다. 마커-스냅 MVP(2026-06-20)에서 기능은 동작 확인됐고 이 스로틀은 알려진 한계로 남김. 개선안: ① 이미 라우팅한 구간 캐싱(새 구간만 계산) ② 샘플 간격 확대/디바운스 ③ 근본책은 궤적 전체를 1요청으로 처리하는 맵매칭 제공자(Tmap/Valhalla) — 위 "MapKit 교체" 트리거와 연결됨.

## Decision Policy

- If a decision affects architecture, privacy, persistence, account creation, cost, or App Store behavior, ask the user.
- If a decision is only local code style or project organization, choose the documented default and update this file.
