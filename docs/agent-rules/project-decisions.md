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
- Swift 언어 모드: Swift 6 (2026-07-10, MVP12) — 격리 기본값은 클래식 모델(기본 nonisolated, Swift 툴체인 원래 기본값) + UI/상태 타입에 명시적 `@MainActor`. `SWIFT_DEFAULT_ACTOR_ISOLATION`은 미설정. 최초 `MainActor` 기본 전략(Task 1~7)에서 2026-07-11 전환 — 이유: 프레임워크 연동 타입(MapKit `NSObject` 서브클래스)이 기본 MainActor로 격리를 잘못 물려받아 실제 크래시가 난 사례(커밋 `18fa11a`) 발견, 프레임워크 연동이 많은 코드베이스에는 기본 무격리가 더 안전한 실패 모드로 판단. 새 타입 작성 시: SwiftUI View/ViewModel/@Observable 등 main-thread 상태를 다루는 타입에만 명시적 `@MainActor`를 붙인다.
- 프레젠테이션 공용 레이어: `Trace/DesignSystem/`(Tokens.swift + Component/) 신설 — Pages와 별도 계층, 추후 모듈 분리 대상 (결정 2026-07-11, MVP12 design-apply). 상세: `docs/superpowers/specs/2026-07-10-design-direction-design.md` §4
- design-apply 범위: P1(토큰·탑바·FAB·시트·구간리스트·핀/폴리라인·저장/목록/왕복/redo 재배치)만 적용, P2(시트 드래그 리사이즈·지도 halo·km 마커·점선 애니메이션·다크 글로우·커스텀 저장 다이얼로그)는 백로그로 이연 (결정 2026-07-11, 킥오프 인터뷰). 상세: `docs/superpowers/specs/2026-07-10-design-direction-design.md` §5
- 바텀시트 배경 모양: 위쪽 모서리만 둥글고(UnevenRoundedRectangle) 배경이 화면 하단까지 확장(.ignoresSafeArea(edges: .bottom)), 콘텐츠는 안전영역 유지 — 풀블리드 지도 위 네이티브 바텀시트처럼 보이도록 (결정 2026-07-11/12, design-apply 진행 중 제품 피드백으로 추가)
- 바텀시트 라이트 모드 반투명 → 완전 불투명 솔리드로 변경 (스펙 §1.3의 "라이트=Glassmorphism, 유리 재질" 원칙에서 이탈, 결정 2026-07-12, 사용자). 이유: 실기기 확인 결과 라이트 모드에서 지도 텍스트/폴리라인이 시트 리스트 위로 그대로 겹쳐 보여 거의 읽을 수 없었음 — 사용자 판단은 "글래스처럼 보이는 게 오히려 아무것도 잘 안 보이는 문제". `Surface.colorset` 라이트 알파를 0.740→1.000으로 변경, 다크와 동일하게 완전 불투명 처리. **주의**: 향후 리뷰에서 라이트 모드를 다시 반투명으로 "고치지" 말 것 — 스펙과의 불일치는 의도된 것.
- "출발 지정됨" 상태 칩 제거 (스펙 §2 "출발 지정됨(민트 점)" 상태에서 이탈, 결정 2026-07-12, 사용자). 이유: 기존 로직이 구간이 몇 개든 특정 구간을 선택 중이 아니면 항상 "출발 지정됨"을 표시해 사실상 의미 없는 상태였음. 경로가 있으면 선택된 구간(없으면 최신 구간) 번호 칩만 표시하고, 경로 자체가 없으면 칩을 아예 띄우지 않는다. `StatusChipKind.startSet` 케이스 삭제됨.
- 구간 선택 시 지도 위 halo 하이라이트 — P2 백로그 항목이었으나 트리거 조건("카메라 핏만으로 선택 구간 식별이 어렵다는 피드백")이 실제로 충족돼 지금 구현으로 당김 (결정 2026-07-12, 사용자). `MapViewRepresentable`에 `SegmentHaloPolyline` 3-pass 렌더링 추가(케이싱 아래 넓고 옅은 accent 스트로크). `docs/backlog.md`의 해당 항목은 완료 처리.
- 바텀시트 드래그-리사이즈 — P2 백로그 항목이었으나 트리거 조건("탭 토글이 답답하다는 피드백")이 실제로 충족돼 지금 구현으로 당김 (결정 2026-07-12, 사용자). 그래버(handle) + sheetHeader 배경(뒷면 레이어)에 `DragGesture` 부착 — sheetHeader/시트 전체에 *직접*(래핑) 걸면 내부 Button들과 히트테스트가 충돌해 전부 먹통이 되는 회귀가 실기기에서 확인됨(2026-07-12), 배경 레이어는 안전. 처음엔 2단계(collapsed/expanded)로 구현했으나 사용자 피드백으로 **3단계**(`SheetDetent`: collapsed/medium/full)로 확장 — 탭은 collapsed↔medium만, "full"은 드래그로만 도달. 구간 개수는 단계에 영향 없음(순전히 제스처로만 전환). **정정(2026-07-13)**: "경로가 비어 있으면 드래그 방향과 무관하게 항상 collapsed로 복귀"는 더 이상 사실이 아니다 — 실기기 확인 결과 "빈 경로일 때 버튼을 누르면 시트가 올라가는데 드래그로는 안 된다"는 불일치가 지적되어, 드래그도 탭 토글과 동일하게 경로 유무와 무관하게 `steppedUp`/`steppedDown`으로 단계만 이동하도록 변경됨 — 탭과 드래그의 동작이 달라선 안 된다는 원칙으로 통일. DragGesture.onEnded에서 곧바로 상태를 쓰면 "Modifying state during view update" 경고가 발생해 DispatchQueue.main.async로 한 틱 지연. `docs/backlog.md`의 해당 항목은 완료 처리.
- 바텀시트 full 디텐트 상한 계산 — top safe area를 형제 뷰(bottomSheet) 크기 계산에 되먹이면 피드백 루프가 생겨 시트가 상태바/다이내믹 아일랜드를 실제로 덮는 버그가 있었다(2026-07-13). `topSafeAreaInset`은 한 번 측정한 값보다 작은 값을 무시(ratchet-up)하도록 고쳤고, 여유값(`sheetTopMargin`)을 12pt→40pt로 늘렸다. 상세: `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`.
- 바텀시트 헤더(`sheetHeader`) 정렬 — `HStack(alignment: .firstTextBaseline)`이었으나, StatusChip의 `.calculating`(첫 자식 ProgressView)과 `.route`(첫 자식 Text) variant가 서로 다른 암묵적 베이스라인을 노출해 로딩 전환마다 헤더 전체 높이가 흔들리는 버그가 있었다(2026-07-13). `.top` 정렬로 변경해 해결. 상세: `docs/solutions/ui-bugs/firsttextbaseline-alignment-jiggle-with-mixed-child-types.md`.
- FAB 스택(되돌리기/앞으로/초기화/현재위치) 위치 — 두 가지 문제가 겹쳐 있었다(2026-07-13, 사용자 스크린샷+실기기 확인).
  1. **collapsed 상태에서도 이미 가려짐**: `fabStack`이 화면 하단에서 고정 16pt(`padding(.bottom, 16)`)였는데, 그 자리가 이미 collapsed 바텀시트 영역과 겹쳐서 되돌리기 1개만 보이고 앞으로/초기화/현재위치 3개는 시트 뒤에 가려 애초에 안 보이고 있었다(스펙에도 없던 순수 버그). 고정 16pt를 `grabberTotalHeight + sheetHeaderHeight + 16`(= collapsed 시트 실제 높이 + 16pt 여유)으로 바꿔 4개 버튼이 항상 collapsed 시트 위에 뜨도록 수정.
  2. **원 스펙 "현재 위치는 항상 노출" 폐기**: 시트 상단 기준으로 동적으로 띄우는 방안도 검토했으나 full 디텐트에서 시트 상단이 topBar 높이까지 올라와 겹치는 문제가 있어 기각. 대신 현재 위치 버튼도 undo/redo/clear와 동일하게 시트가 collapsed가 아니면 같이 숨기도록 스펙을 의도적으로 변경(원 스펙 "항상 내 위치"에서 이탈). 펼친 상태는 지도 가시 영역 자체가 작아 재가운데맞춤 가치가 낮다고 판단; 실사용 중 불편하면 재검토.
  - 실기기 사용 후 여전히 불편하면 추가 조정 예정 — 지금은 임시 확정이 아니라 "일단 이렇게 두고 써본다" 단계.

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
