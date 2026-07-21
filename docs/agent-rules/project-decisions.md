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
- 프레젠테이션 공용 레이어: `Trace/DesignSystem/`(Tokens.swift + Component/) 신설 — Pages와 별도 계층, 추후 모듈 분리 대상 (결정 2026-07-11, MVP12 design-apply). 상세: `history/mvp12/2026-07-10-design-direction-design.md` §4
- design-apply 범위: P1(토큰·탑바·FAB·시트·구간리스트·핀/폴리라인·저장/목록/왕복/redo 재배치)만 적용, P2(시트 드래그 리사이즈·지도 halo·km 마커·점선 애니메이션·다크 글로우·커스텀 저장 다이얼로그)는 백로그로 이연 (결정 2026-07-11, 킥오프 인터뷰). 상세: `history/mvp12/2026-07-10-design-direction-design.md` §5
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

- **제품 구조: 두 독립 기둥** (결정 2026-07-13, MVP13 킥오프) — 기존 "러닝 전→중→후" 로드맵(2026-07-07)을 정정: 러닝(기록)은 코스 탐색(계획)의 부속 단계가 아니라 **독립 기둥**이다. 일반 러닝앱처럼 코스 없이 그냥 뛰어도 되고, 코스 연동(코스 골라 뛰기 + 계획 vs 실제 비교)은 두 기둥 위의 제3의 경험(별도 MVP). 앱 루트는 `TabView`(코스/러닝) — 풀스크린 진입·허브 분기 대안은 기각. 상세: `docs/superpowers/specs/2026-07-13-run-tracking-design.md` §0·§3
- **러닝 측정 범위: GPS 열만 + 샘플 스트림 원칙** (결정 2026-07-13, MVP13) — 이번 기둥의 측정은 CLLocation에서 나오는 것(경로·거리·시간·페이스·고도)으로 한정. 심박·케이던스·칼로리는 Apple Watch 없이 사실상 불가라 워치 연동 MVP로 이연(그때 HealthKit 심층 조사 — 일반 HealthKit은 entitlement+동의만으로 사용 가능함은 확인됨, 기관 협력 불요. 기능 없이 entitlement만 미리 넣는 것은 YAGNI+심사 리스크라 기각). 미래 대비의 실체는 저장 스키마의 "기록 = 타임스탬프 샘플 스트림 묶음" 원칙 — 심박은 나중에 스트림 하나를 옆에 추가(additive). 상세: 같은 스펙 §2
- **러닝 위치 API: `@MainActor` + `CLLocationManager` delegate** (결정 2026-07-13, MVP13) — 기존 `CoreLocationService` 선례와 일관. iOS 17 `CLLocationUpdate.liveUpdates`는 기각: `LiveConfiguration(.fitness)`는 있으나 `allowsBackgroundLocationUpdates` 미적용(`CLBackgroundActivitySession` 별도 관리 필요), `desiredAccuracy`·`distanceFilter` 세밀 제어 부재. 권한은 "앱 사용 중" + Background Modes(location)로 충분(Always 불필요, 러닝앱 표준). 상세: 같은 스펙 §4
- **러닝 지도: SwiftUI `Map` + 폴리라인 스로틀** (결정 2026-07-13, MVP13) — 러닝 화면은 표시 전용이라 SwiftUI Map으로 시작(플래너가 MKMapView로 간 이유인 그리기 제스처 소유권 문제가 없음). 자라는 폴리라인 갱신은 3초/20m 스로틀, 본 러닝 QA에서 프레임 드랍 확인 시 MKMapView 표시 전용 래퍼로 폴백. 상세: 같은 스펙 §4
- **사이클 1 완료 후 추가 검증: 실기기 왕복 데이터 대조** (2026-07-14) — 같은 경로를 반대 방향으로 2회 실행한 DEBUG 덤프를 원시 GPS로 재계산해 화면 표시값(거리·페이스·고도)과 오차 없이 일치함을 확인, 정확도/고도 필터의 실전 동작도 검증됨. 버그 없음, 순수 확인. 상세: `docs/backlog.md` MVP13 QA 섹션.
- **러닝 기록 저장 트리거: 자동 저장** (결정 2026-07-14, MVP13 사이클 2 `run-record-save` 킥오프 브레인스토밍 중) — 러닝 종료(요약 화면 진입) 시 별도 확인 없이 바로 SwiftData에 저장(코스처럼 이름 붙여 저장할지 묻지 않음 — 러닝은 소장품이 아니라 활동 이력이라는 판단). 아주 짧은 러닝도 일단 저장(임계값 없음), 삭제는 목록 화면에서 가능.
- **러닝 기록 저장 스키마·화면** (결정 2026-07-14, 같은 브레인스토밍에서 확정) — ① 샘플 필드 범위: 원시 5필드(시각·위도·경도·고도·속도) 전부, 다운샘플링 없음(QA 실측으로 용량 무해 확인 — 최적화는 원본이 있는 한 나중에 가능, 역방향 불가). 정확도 2필드는 저장 제외(사이클 1 §2 확정 유지). GPS 공백 구간 별도 저장 없음(시각 간격에서 파생 가능 — 사이클 1 이연 결정 종결). ② 거리·시간·고도 상승은 목록 성능용 캐시로 컬럼 병행 저장. ③ 러닝 기록은 코스와 **별도 스토어 파일**(마이그레이션 리스크 0). ④ 목록 입구는 러닝 탭 대기 화면 버튼(통계가 커지면 그때 탭 승격 — 되돌리기 쉬운 결정). 상세: `docs/superpowers/specs/2026-07-14-run-record-save-design.md`

- **MVP14 기본 러닝 경험 완성 — 킥오프 결정 묶음** (결정 2026-07-15, 브레인스토밍) — ① 일시정지는 **수동만**(자동 일시정지는 GPS 오판 튜닝 부담으로 기각, "누르는 걸 까먹는다" 피드백 트리거로 백로그). 일시정지 중에도 GPS 스트림은 유지하되 미적산(재개 즉각성 우선), 시간·페이스·스플릿·목표 판정은 전부 "일시정지 제외 활동 시간" 기준. ② km 경계 오디오는 **거리+총시간+전체 평균 페이스**(직전 km 페이스 아님 — 일상 러닝 거리에선 평균이 더 직관적이라는 사용자 판단, 나이키런 방식). 직전 km 페이스는 기록 상세 스플릿 표 전담. ③ 발화는 km 경계 + 상태 전환(시작/일시정지/재개/종료 요약), **모드 무관 공통**(자유 러닝에도 항상). ④ 음악 공존은 **덕킹**(`.duckOthers`, 발화 순간만 세션 활성화 후 복원) + Background Modes `audio` 추가 — 설계 상수 "러닝 중 = 화면 꺼짐/백그라운드". ⑤ 목표는 자유/거리/시간 3모드, 절반·달성 각 1회 발화, **달성 후에도 트래킹 계속**. ⑥ 스키마는 additive만: 일시정지 구간 명시 저장(GPS 끊김과 구분 불가라 파생 불가), duration 캐시 = 활동 시간, 목표 타입·값 옵셔널 저장, 스플릿은 저장 안 함(샘플에서 파생). ⑦ 일시정지 진입점은 앱 내 버튼만 — 잠금화면(Live Activity) 인터랙티브 버튼은 스펙 리뷰에서 "화면 꺼짐 상수와 충돌" 지적됐으나 사용자 판단으로 이연(일시정지 사용 빈도 낮음, 쓰는 상황이면 어차피 폰을 꺼냄; "잠금 해제 번거로움" 피드백 트리거). ⑧ 장시간 일시정지는 무대응(스트림·세션 유지, 배터리 불만 피드백 트리거). 상세: `docs/superpowers/specs/2026-07-15-run-experience-design.md`

- **오디오 세션 활성화 실패 시 발화 스킵** (결정 2026-07-16, run-splits-audio 플랜 — 스펙 §5 이연 결정의 종결) — 백그라운드에서 `.playback` 활성화가 실패(통화 중 등)하면 그 발화는 버린다(재시도 없음). 재시도는 시점이 지난 값을 읽게 되고(다음 km 경계 발화가 곧 온다), 통화 중 TTS 개입도 부적절하다는 판단. 플랜: `docs/superpowers/plans/2026-07-16-run-splits-audio.md`

- **MVP15 러닝 경험 보강 — 킥오프 결정 묶음** (결정 2026-07-17, 브레인스토밍 + 스펙 리뷰) — ① 코스 연동보다 러닝 기둥 보강 우선(두 기둥을 잇기 전에 러닝 기능이 단단해야 연동 QA에서 원인 분리 가능). ② 포인트(달리면서 구간 거리 찍기)는 기록 저장까지(B안) — 타임스탬프+좌표+누적거리 캐시의 additive 스트림. 코스 변환(C안)은 코스 연동 MVP로 이연(GPS 폴리라인 코스와 라우팅 코스의 공존 설계 필요). ③ 시작 카운트다운 3-2-1: 숫자 발화 포함(덕킹은 한 번만), 권한·정확도 프롬프트는 카운트다운 전 완료, 종료 시 GPS 미확보면 세션 시작 후 "신호 확보 중" 전이, 백그라운드 진입에도 계속 진행("시작 누르고 바로 잠금"이 표준 흐름). ④ 목표 거리·시간 직접 입력(km/분): 단위 상시 표시 + 직전값 프리필 + 인라인 에러. ⑤ 잠금화면 포인트 버튼 도입(LiveActivityIntent, 무세션 no-op 가드) — 잠금화면 일시정지 버튼은 계속 미도입(빈도·흐름 잣대에서 반대 결론). ⑥ 오탭 복구는 기록 상세 포인트 개별 삭제로(연타 임계값 없음 유지). ⑦ 러닝 탭 UI 구조 개편(대기 화면 지도 제거 검토 등)은 MVP16 후보로 백로그 씨앗만. 상세: `history/mvp15/2026-07-17-run-detail-waypoints-design.md`

- **MVP16 러닝/코스 UI 개편 — 킥오프 결정 묶음** (결정 2026-07-19, 브레인스토밍) — ① 범위: 방향 스펙 항목 1(탭/시트/페이지 구조)+항목 2(그리기 제스처)+포인트 구간 폴리라인 표시(MVP15 QA 이월)를 전부 MVP16으로 편입. ② 탭 구성: 2탭(코스/러닝) 유지 — 기록 탭 승격은 안 함(MVP13 "통계 커지면 승격" 트리거 미충족, 커스텀 탭바라 이후 추가 비용 작음), 기록 목록·상세는 러닝 탭 안 전체화면 페이지. ③ 트래킹 중 탭바 숨김 — 러닝 중 앱 내 탭 전환 진입점 자체를 제거(트래킹 중 조작은 일시정지/종료/포인트(MVP15) 셋 — 포인트 버튼 유지, 배치는 ui-direction), 탭바는 **요약 화면을 닫고 대기 화면에 복귀해야** 다시 보임(문서 리뷰 후 확정), 자유 전환은 실사용 필요 확인 시 확장(트리거). ④ 러닝 탭 지도 완전 제거 — 트래킹 화면만이 아니라 **러닝 탭 전체**(목표 설정 대기·GPS 탐색 포함, 문서 리뷰 후 확정), 숫자 중심 전체화면, "허전함" 실기기 감각 확인 시 복원 검토(트리거). ⑤ 커스텀 크롬(탭바+시트) 베팅 확정 — VoiceOver·Dynamic Type·세이프에어리어 직접 책임을 인지하고 진행(세이프에어리어는 기지 영역, 나머지는 소비용), 구현 중 제스처 충돌·접근성 비용이 마일스톤 범위를 넘으면 시스템 컴포넌트 복귀 재평가(트리거, `presentationBackgroundInteraction` 경로). ⑥ 마일스톤 4개: ui-direction(경량·문서 전용, MVP12 방식) → tab-restructure → run-fullscreen → draw-gesture. ⑦ 실험 코드·참고 캡처는 `docs/refs/`로 이전 완료. 상세: `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md`

- **카운트다운을 `RunSession.State.countingDown`으로 승격** (결정 2026-07-20, MVP16 run-fullscreen Task 1) — 카운트다운(3-2-1)은 그동안 `RunPageViewModel`의 뷰 전용 상태였고, 그동안 `RunSession.state`는 `.idle`이라 탭바 숨김 판정(`AppTab.isTabBarHidden(runState:)`)이 걸리지 않았다. 이 틈에서 tab-restructure 실기기 QA(2026-07-20)가 갇힘 버그를 발견했다: 카운트다운 중 다른 탭으로 이동 → 트래킹 시작 → 탭바 숨김 → 원래 있던 탭에 탭바 없이 갇힘. 그 자리에서는 `RootView`에 "트래킹이 시작되면 러닝 탭으로 강제로 끌고 온다"는 `onChange` 우회(`feature/mvp16-tab-restructure` 커밋 `c7d55fe`)로 증상만 막아 두었다. run-fullscreen에서 `RunSession.State`에 `countingDown` 케이스를 추가해 카운트다운을 세션 상태로 승격시킴으로써, 탭바 숨김이 "뷰가 무엇을 하고 있는가"가 아니라 "세션이 어떤 상태인가"라는 단일 함수로만 결정되게 만들었다 — `prepareStart`의 첫 `await`(정확도 게이트) 이전 동기 구간에서 상태를 올려, 그 await를 기다리는 동안에도 탭 전환 창이 열리지 않는다. 이 구조 변경으로 `RootView`의 강제 탭 전환 우회를 제거했다 — 우회가 막던 "카운트다운 중인데 탭바가 살아 있는" 전환 창 자체가 더 이상 존재하지 않기 때문이다. 상세: `docs/superpowers/plans/2026-07-20-run-fullscreen.md` Task 1 "배경 — 왜 카운트다운을 세션 상태로 올리는가".

- **Live Activity 요청을 카운트다운 시작 시점으로 앞당김** (결정 2026-07-21, MVP16 run-fullscreen 실기기 QA 중 발견) — MVP15 킥오프에서 "시작 누르고 바로 잠금이 표준 흐름"이라고 이미 못박았는데도(위 MVP15 결정 묶음 ③), 실제로는 이 흐름에서 잠금화면 카드가 안 생기는 문제가 있었다. 원인: ActivityKit은 **새 Live Activity를 앱이 포그라운드일 때만 시작**할 수 있는데(백그라운드 요청은 조용히 실패), `RunActivityController`가 실제 트래킹이 시작되는 시점(`.tracking`)에야 요청을 보내고 있었다 — 카운트다운(3초)+GPS 확보 시간 동안 이미 화면이 잠겨 있으면 그 시점엔 앱이 백그라운드라 요청이 실패한다(`try?`가 에러를 삼켜 조용히). 수정: 요청 시점을 `.countingDown`(시작 버튼을 누른 바로 그 순간 — 항상 포그라운드 보장)으로 앞당기고, 카운트다운~GPS 확보 중엔 같은 카드를 `ContentState.isPreparing=true`로 갱신해 "출발 준비 중…" 문구만 보여주다가 실제 트래킹이 시작되면 내용만 거리·시간으로 바꾼다(요청은 한 번만, 갱신은 백그라운드에서도 항상 가능). 사용자 확인: 카운트다운 중 카드가 보이는 것 자체는 허용(A안 채택). 상세: `Trace/Application/RunTracking/RunActivityController.swift`, `Trace/Domain/RunTracking/RunActivityAttributes.swift`, `TraceWidgets/RunLiveActivityWidget.swift`.

- **그리기 제스처 방향 A(롱프레스-드래그) 유지 확정 + 스크롤 잠금 소유권 이전** (결정 2026-07-21, MVP16 draw-gesture 플랜 작성 중) — 킥오프 §2.5가 확정한 "한 손가락 = 항상 지도 이동, 그리기 = 롱프레스-드래그"를 플랜 작성 시점에 한 번 더 재검토했고, **그대로 간다.** 근거는 현재 모델(한 손가락 = 그리기)이 실사용에서 이미 불편으로 확인됐다는 것 — 사용자가 지도를 옮기려는 본능적 한 손가락 드래그로 원치 않는 선을 반복해서 그었다. A는 "한 손가락 = 이동"을 두 모드 모두에서 참으로 만들어 그 원인을 제거한다. 미채택 B(이동/그리기 서브 토글, 흐름 끊김)·C(두 손가락 팬 + 가장자리 자동 스크롤, 증상 완화만)의 기각 사유는 지금도 유효하다. **구현 구조:** 지도 스크롤 잠금의 소유권을 "모드 경계"에서 "스트로크 생명주기"로 옮긴다 — 그리기 모드가 두 하위 상태(대기=지도 이동 가능 / 스트로크 진행 중=지도 고정)를 갖고, 잠금은 롱프레스 `.began`에서 걸고 `.ended`/`.cancelled`에서 푼다. 인식기는 `UILongPressGestureRecognizer` 하나로 충분하다(인식 후에도 `.changed`가 계속 오므로 "꾹 + 드래그"가 한 인식기로 처리됨 → `require(toFail:)` 함정 회피). 이로써 커스텀 두손가락 팬(MVP10 산물)은 존재 이유가 사라져 제거한다. **주의(다음 세션용):** "XcodeBuildMCP로 롱프레스-드래그를 합성할 수 없다"는 것은 **자동화 도구의 한계이지 설계 결함이 아니다** — 실기기의 진짜 손가락은 이 동작을 문제없이 한다. 이 둘을 혼동해 A안을 재검토하지 말 것. A안의 진짜 반증 조건은 킥오프가 정한 것 하나뿐이다: 실기기에서 홀드·드래그 중 지도가 같이 움직이는 것. 상세: `docs/superpowers/plans/2026-07-21-draw-gesture.md`

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
