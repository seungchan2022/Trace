# trace-study 학습 범위 설계

> 작성: 2026-07-31 · 브랜치: `feature/trace-study-redesign`
> 배경: `docs/backlog.md` "trace-study 스킬 검토 — 학습 범위를 어디까지 잡을지부터"
> 이 문서는 **무엇을 어디까지 공부할지**를 정한다. 절차는 `.agents/skills/trace-study/SKILL.md`에 있다.
>
> **이 문서의 수명:** §3 덩어리 표와 §4 순서는 따라잡기 9개가 끝나면 다시 읽을 일이 없다.
> §7 기각 기록과 §1 배경은 결정을 되돌리려 할 때 읽는다.
> **처분(옮길지·지울지·둘지)은 9개가 끝난 시점에 판단한다** — 지금 정하지 않는다.
>
> ⚠️ **옮기거나 지울 때 같이 고칠 것:** `.agents/skills/trace-study/SKILL.md`가 이 경로를 두 곳에서
> 가리킨다(머리말 · `[0]` 따라잡기 분기). 경로만 바꾸면 되고, 스킬 로직은 안 바뀐다.
> 참고로 이건 MVP 스펙이 아니라 워크플로 스펙이라 `trace-archive`가 자동으로 옮기지는 않는다
> (`docs/workflow-audit.md`와 같은 부류).

## 1. 왜 하는가

Trace는 바이브코딩으로 만들어졌고, 사용자는 코드 내부를 거의 보지 않았다.

**목적은 "참여"다** — 검증이 아니라. (2026-08-02 정정. 이전 문장은 *"내가 만들었다고 말하려면
그만큼은 알아야 한다"*였는데, 그건 **자격 증명** 프레이밍이라 "얼마나 알아야 충분한가"에 답이 없었다.)

두 가지를 구분한다.

- **검증하려고 이해한다** — "이거 맞아?" 엄지 올리거나 내리거나. 이 역할은 **줄어드는 게 맞다.**
  에이전트가 점점 잘한다.
- **참여하려고 이해한다** — 한 바퀴 돌 때마다 내가 바뀌고, **그 바뀐 내가 다음 아이디어를 낸다.**
  머릿속에 개념 구조가 있어야 남에게 묻지 않고 빠르게 재조합할 수 있다.

Trace는 MVP18, 19, 20을 계속 돌린다. 그래서 검증 능력이 아니라 **다음 MVP를 스스로 설계할 수
있느냐**가 기준이다. 이건 "얼마나 알아야 하나"에 답이 있다.

역할별로 나누면 이렇게 갈린다 — **디자이너는 제품을, PM은 구조와 결정을, 개발자는 그 원리까지** 안다.
사용자는 개발자(신입 iOS)이므로 세 번째다.

### 인지 부채 (cognitive debt)

이해가 출하된 코드보다 뒤처지면 쌓이는 빚. 기술 부채의 유비이고, Margaret-Anne Storey가 퍼뜨렸다.
잠깐은 넘어가지지만 언젠가 청구서가 온다 — *"바이브코딩이 잘 되다가 어느 순간 무슨 일이 일어나는지
전혀 모르겠고, 더 이상 참여할 수 없는 상태가 된다."*

**이 학습은 그 빚을 갚는 일이다.** 그래서 총량이 아니라 **참여 가능선까지**가 목표다.

> 근거: Geoffrey Litt(Notion), *"Understanding is the new bottleneck"*, AI Engineer World's Fair 2026.
> 검토 경위와 기각 항목은 §10.

### 기준선

> **C로 공부한다 → 시간이 지나면 B 정도로 가라앉는다 → 다시 보면 C로 돌아온다.**

- 넘어갈 때 **대충 넘어가지 않는다.** 이해 안 하고 지나간 것은 나중에 복원이 안 된다(복원할 게 없다).
- **다 외울 필요는 없다.** 학습 문서가 기억의 바깥쪽 절반을 맡는다.
- 그래서 문서의 목적은 "예쁜 정리본"이 아니라 **"다시 읽으면 10분 안에 복원되는 것"**이다.

## 2. 무엇을 알아야 하는가 — 깊이 정의

| 층 | 내용 | 목표 |
|---|---|---|
| **A** | 무엇을 만들었나 (제품 설명) | 통과점 |
| **B** | 어떤 부품이 있고 왜 그걸 골랐나 (**순서 없음**) | 평소 말하는 높이 |
| **C** | 각 부품이 **무엇을 받아 무엇을 보장하는가** + **어떤 순서로 이어지는가** | **목표** |
| **D** | 그 보장을 코드로 어떻게 구현했나 (한 줄 한 줄) | **안 간다** — 필요할 때 연다 |

C의 예 (`DrawnPathSampler`): *"좌표 목록을 받아 120m 간격으로 솎아낸 목록을 돌려준다. 시작·끝점은 반드시 남긴다.
간격은 직선거리가 아니라 **누적거리**로 잰다 — 직선으로 재면 루프 코스에서 점이 사라지는 버그가 났었다."*
D의 예: *"`for`문이 `prev`를 들고 `accumulated`에 더하고, 120을 넘으면 append 후 0으로 리셋한다."*

### C를 고르고 D를 뺀 근거 (2026-08-02 보강)

이 선택은 서로 모르는 두 사람이 다른 길로 와서 같은 곳에 선다.

- **Litt**은 "참여"의 재료가 **머릿속 개념 구조**라고 본다(§1). 코드 텍스트가 아니다.
- **Benoit Schillings**(Google DeepMind VP Research)는 정반대 입장에서 출발한다 — 코드 읽기는
  어셈블리처럼 사라진다고 예측한다. 그런데 인간에게 남긴 역할이 **아키텍처와 귀납적 사고**
  (*"시스템을 훨씬 넓은 맥락에서 보고 패턴을 찾아 결정하는 것"*)이고, AI가 아직 못하는 곳도
  *"극단적 복잡도를 관리 가능한 조각으로 쪼개는 능력"*이라고 짚는다.

**둘 다 한 줄씩 읽기(D)를 부정하고, 둘 다 구조(C)에 인간 가치를 놓는다.**

신입에게는 함의가 하나 더 있다. 예전에는 **코드를 직접 쓰면서** 구조를 배웠는데 그 경로가 막히고
있다(Trace 자체가 그렇게 만들어졌다). 그러면 구조는 **의도적으로** 배우는 수밖에 없다 —
이 학습이 존재하는 이유다.

> 근거: Benoit Schillings, *"Software engineering is not about writing code"*, AI Engineer 2026.

### 범위에서 제외하는 것

- **UI·레이아웃** — 커스텀 탭바 만드는 법, 시트 detent 비율, FAB 배치, 대시보드 레이아웃, 저장 목록 UI.
  이건 자주 바뀌고(백로그 open 25건 중 대부분이 UI다), **그 화면을 건드리는 MVP가 오면 그때 배운다.**
- **테스트 작성법** — XCTest 문법·TDD 실천은 별개 주제. 읽기만 한다(§5).
- **일반 문법 지식** — Swift 동시성 문법 자체 등. 흐름에서 처음 나올 때만 그 자리에서 다룬다.

## 3. 학습 덩어리 9개

**한 덩어리 = 한 세션.** 파일 경로는 실측했다(2026-07-31). MVP 문서는 `docs/roadmap.md`로 어느 MVP인지
찾은 뒤 그 MVP의 **design·kickoff 문서만** 연다(plan·checklist는 재료가 아니다 — §7 근거).

| # | 덩어리 | 주요 코드 | 테스트 | MVP 문서 |
|---|---|---|---|---|
| **0** | **앱 구조** | `Trace/App/` 7파일 323줄, 특히 `DependencyContainer`(95줄) | 전체 43개 파일 **이름만** 훑기 | MVP12 `swift6-migration` |
| **1** | 손으로 그은 선이 도로 경로가 되는 법 | `MapViewRepresentable.handleDraw`, `DrawnPathSampler`(24줄), `MapKitCoursePlanningService`(85줄), `CoursePlannerPageViewModel.routeStrokeAndAttach` | `DrawnPathSamplerTests` `SnappedRouteTests` `RouteCacheTests` `ThrottleDetectionTests` | MVP4 `mkmap-migration`·`drawing-precision`, MVP16 `draw-gesture` |
| **2** | 구간을 이어붙이고 재는 법 | `CourseEditSession`(301줄), `CourseSegment`, `CourseCoordinate+Geo`(63줄) | `CourseEditSessionTests` `CourseSegmentTests` `CourseRoundTripInsertTests` `CourseCoordinateGeoTests` | MVP5 `path-stitching`, MVP6, MVP9 `edit-consistency`, MVP10 `attach-nearest-fallback` |
| **3** | 지도 위에 표시하는 법 | `MapViewRepresentable`의 `rendererFor`(오버레이)·`viewFor`(어노테이션), `ColoredPinAnnotation`, `SegmentDistanceAnnotation`, `SegmentPalette`, `OverlapOffsetResolver` | `SegmentPaletteTests` `OverlapOffsetResolverTests` | MVP7 `course-edit-ux-panel`, MVP8 `overlap-offset` |
| **4** | GPS가 거리·페이스가 되는 법 | `RunTrack` `RunSample` `RunStats` `RunPauseInterval` `RunSplit`(Domain), `RunSession`(Application) | `RunTrackTests` `RunSessionTests` `RunPauseIntervalTests` `RunSplitCalculatorTests` `RunStatsCalculatorTests` | MVP13 `run-tracking`, MVP14 `run-pause-resume`·`run-splits-audio` |
| **5** | 백그라운드에서 계속 도는 법 | `Config/Trace-Info.plist`의 `UIBackgroundModes`(**location, audio** 2개), `RunLocationTracker`, `CoreLocationService`, `ContinuationBroadcaster` | `ContinuationBroadcasterTests` | MVP13 `run-tracking`, MVP14 `run-splits-audio` |
| **6** | 소리 내는 법 | `SpeechVoiceAnnouncer`(`.playback`+`.duckOthers`, 예열은 `.ambient`+`.mixWithOthers`), `RunAudioCoach`, `RunAnnouncementBuilder` | `RunAudioCoachTests` `RunAnnouncementBuilderTests` | MVP14 `run-splits-audio`, MVP15 `run-detail-polish` |
| **7** | 잠금화면 위젯 | `RunActivityAttributes`(Domain 25파일 중 **유일하게 Foundation 아닌 것**), `RunActivityController`, `TraceWidgets/RunLiveActivityWidget`(141줄), `MarkRunWaypointIntent` | `RunWaypointIntentActionTests` | MVP13 `run-live-activity`, MVP15 `run-waypoints` |
| **8** | 저장하는 법 | `SwiftDataCourseRepository` `SwiftDataRunRecordRepository` `CoursePersistenceDTO` `RunPersistenceDTO` | `SwiftDataCourseRepositoryTests` `SwiftDataRunRecordRepositoryTests` `RunPersistenceDTOWireFormatTests` | MVP11 `course-save`, MVP13 `run-record-save`, MVP17 `lint-cleanup`(저장 키 사건) |

### 0번이 담는 것

1. **레이어 6개** — Domain / Application / Infrastructure / Pages / App / DesignSystem
2. **의존 방향** — **Domain 25개 파일 중 24개가 `import Foundation` 하나뿐**이다(나머지 1개는 ActivityKit이 강제).
   SwiftData·MapKit·CoreLocation·AVFoundation을 **전혀 모른다.**
3. **프로토콜 경계(포트/어댑터)** — 위치·저장·음성·길찾기가 전부 프로토콜 뒤에 있다.
   코드 주석이 그대로 말한다: *"Domain은 CoreLocation을 모른다"*, *"Domain은 AVFoundation을 모른다"*
4. **MVVM** — Page + PageViewModel 쌍
5. **DIContainer** — 조립 지점. ①프로토콜로 들고 있음 ②`live()`/`uiTesting()` 두 벌로 갈아끼움
   ③**하나만 만들어 공유해야 하는 것**(`runHistoryViewModel`, `voiceAnnouncer` — 파일에 이유가 주석으로 있음)
6. **동시성 규칙** — 기본 nonisolated(= Swift 원래 동작), 필요한 데만 `@MainActor` 명시.
   **`SWIFT_DEFAULT_ACTOR_ISOLATION`은 Xcode 템플릿이 넣어준 것을 지운 것**이다(`6c28cbd` 도입 → `85e4899` 제거,
   현재 프로젝트 파일에 0건). 이유는 실기기 크래시 — MainActor 기본이 MapKit `NSObject` 서브클래스까지 오상속.
   **설정이 지금 없으므로 코드만 봐서는 안 나온다.**
7. **테스트 전략** — 단위 43파일(5,968줄) vs UI 2파일. 무엇을 자동 검증하고 무엇을 실기기 QA로 넘기나

## 4. 순서와 근거

`0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8`

두 원칙으로 정했다.

- **데이터가 흐르는 순서** — 만든다(1) → 붙인다(2) → 보여준다(3) / 잰다(4) → 살려둔다(5) → 쓴다(6·7)
- **심장 먼저, 소비자 나중** — 4를 모르면 6·7이 무엇을 받는지 모른다

0번이 맨 앞인 이유는 나머지 8개가 전부 그 골격 위에 얹혀 있기 때문이다.
8번이 맨 뒤인 이유는 코스(2)와 러닝(4) **둘 다** 저장하기 때문이다.

## 5. 한 세션이 도는 방식 — 근거만. 절차는 스킬에 있다

> ⚠️ **절차의 단일 출처는 `.agents/skills/trace-study/SKILL.md`다.** 이 절에 절차를 복사해 두었더니
> 2026-08-04에 스킬만 고쳐지고 이 절이 옛 내용으로 남아 두 문서가 어긋났다(당시 1번 항목이
> "동작 순서에 번호를 붙여 보여준다"였는데, 그날 파트 축이 **만드는 순서**로 바뀌었다).
> 아래는 그때 남길 값이 있다고 판단한 **근거**만이고, 하는 방법은 스킬을 본다.

- **문서 ↔ 코드 불일치 검사를 넣은 이유** — frank 스킬 `[1-C]`에 있던 단계인데 Trace 46줄
  버전에서 깎여나갔다. 되살린다.
- **테스트는 이름만 읽는 이유** — 한글로 쓰여 있어 이름이 그대로 명세가 된다
  (예: `test_수직정확도가_나쁜_샘플은_고도계산에서_제외된다`). 세션당 5분이면 되고,
  헷갈리는 보장이 있을 때만 그 테스트 **하나**를 연다.
- **짧은 Domain 파일을 통째로 읽는 이유** — Domain은 25파일 834줄로 파일당 평균 33줄이다.
  큰 파일(`MapViewRepresentable` 688줄)만 해당 함수로 좁힌다.
- **확인 문제를 "뭐가 깨질까요"로 내는 이유** —
  [Stack Overflow 개발자 설문](https://survey.stackoverflow.co/2025/ai)에서 AI 코드에 대한 1위 불만이
  *"거의 맞는데 딱 맞지는 않다"*(66%)인데, 그 실패 모드는 **C를 알아야만 보인다**(결정도 구조도 옳고
  돌아가기까지 하며, 약속한 것을 조금 다르게 지킬 뿐이라서). 확인 문제가 그 연습이다.

**막히면 리팩터링하지 않는다.** 대신 *"내가 몰라서인가, 코드가 나빠서인가"*를 판정하고,
코드가 나쁜 것이면 `docs/backlog.md`에 적고 넘어간다. 읽기 어려운 남의 코드를 그대로 읽는 게 실무 능력이다.

## 6. 산출물과 진행 상태를 어디에 두나

| 무엇 | 어디 | 왜 |
|---|---|---|
| 덩어리별 학습 문서 | `docs/study/<번호>-<슬러그>.md` | 기능 단위. MVP 단위가 아니다(§7) |
| **진행 상태(9개 체크박스)** | **`docs/superpowers/plans/2026-07-31-trace-study-catchup.md`** | **`/trace-init`이 이 경로의 `- [ ]`를 읽는다** |

두 파일 모두 **아직 없다** — 학습을 실제로 시작할 때 만든다. 이 문서는 위치만 정한다.

**진행 상태 위치가 이 설계의 급소다.** frank는 로드맵을 `history/study/`에 뒀는데 재진입 장치와 연결되지 않았고,
6단계 중 2단계 반에서 2.5개월째 멈춰 있다. Trace의 `/trace-init`은 `docs/superpowers/plans/*.md`의 체크박스를
읽어 "Task N까지 완료, 다음은 N+1"을 복원하므로, **체크박스를 거기 두면 새 세션이 자동으로 위치를 찾는다.**
스킬을 고칠 필요도 없다.

## 7. 기각한 것과 이유

| 기각안 | 이유 |
|---|---|
| **MVP 순서대로 순회** | **죽은 코드를 배우게 된다.** SwiftUI Map(MVP1~3)은 MVP4에서 교체, 러닝 탭 지도(MVP13)는 MVP16에서 제거, 기록 화면은 두 번 이사, 초안 자동 저장·가로모드·커스텀 두손가락 팬은 삭제됐다. MVP13을 순서대로 공부하면 지금 없는 화면을 배운다 |
| 레이어 순회(Domain→Pages) | 사용자 행동과 무관해 **흐름이 안 생긴다.** "흐름으로 이해한다"는 학습 방식과 정면 충돌 |
| 14덩어리 전면 C(UI 포함) | 완주 불가. frank가 6단계에서 멈춘 것보다 총량이 크다. 그리고 "개발자도 코드베이스 전체를 균일한 C로 알지 않는다"는 판단과 모순 |
| 5덩어리로 축소(안 바뀔 것만) | 오디오·백그라운드·위젯이 빠졌다. 그건 **"기능적인 부분"의 한복판**이라 기준이 틀렸다 |
| 동시성·테스트를 별도 세션으로 | **"개념은 흐름에서 처음 나올 때만"이라는 자체 원칙 위반.** 따로 빼면 Swift 문법 공부가 된다. 전역 결정만 0번에 넣는다 |
| plan·checklist 문서까지 재료로 | "대기 화면" 하나가 25개 파일에 걸린다(design 7 + kickoff 2 + plan 9 + checklist 9). **design·kickoff 9개만**이 "왜"를 담고, 로드맵 요약으로 거르면 2~3개로 준다 |
| 학습 중 리팩터링 | 순서가 거꾸로(이해 못 한 것은 개선 대상을 못 고른다) + 검증 부담이 학습보다 큼 + 읽기 쉽게 바꿔놓고 읽으면 실무 능력이 안 는다 |

## 8. 앞으로(따라가기)

이 9개는 **밀린 것을 따라잡는 일회성 작업**이다. MVP18부터는 다르게 간다.

| | 따라잡기(이번) | 따라가기(MVP18~) |
|---|---|---|
| 단위 | 지금 있는 기능 9개 | 그 MVP |
| 재료 | 로드맵으로 필터 → design·kickoff 2~3개 + 현재 코드 | 방금 쓴 문서 1~2개 + 방금 만든 코드 |
| 시점 | 지금부터 순차 | **MVP 종료 직후** (`trace-archive` 다음) |
| 횟수 | 한 번 | 계속 |

**둘은 같은 문서에 쌓인다.** MVP18이 기록 탭을 고쳤으면 해당 덩어리 문서 아래에
*"MVP18에서 이렇게 바뀜 — 이유는 …"*을 덧쓴다. 이러면 학습 문서가 항상 현재 앱과 일치하고,
§7의 "죽은 코드" 문제가 앞으로는 발생하지 않는다.

## 9. `trace-study` 스킬 (재작성 완료 2026-07-31)

현재 46줄. **frank `study` 스킬(412줄)의 압축본**이며, 뼈대는 같고 실행에 필요한 부분이 전부 깎였다.
frank 것을 통째로 되살리지 않는다 — 알려진 실패(콜드 재시작·중도 정지)를 막는 것만 가져온다.

**되살릴 것:** 진행 상태 파일 + 재개 절차 · 문서↔코드 불일치 검사 · 노트 형식(💡 선제 답변 블록쿼트, 번호 흐름) · 확인 문제 기록 보존(오답 포함)

**안 가져올 것:** mermaid CLI 파이프라인 · HTML 생성 · Claude Sunset 테마 CSS
(Trace는 markdown 우선이고, 다 가져오면 412줄로 돌아간다)

**고칠 것:** ①단위를 MVP → 기능으로 ②목적을 "면접 설명" → §1 기준선으로 ③산출물을 "정리본" → "10분 복원용"으로

### 호출 방식 (하나의 스킬, 두 진입점)

```
/trace-study          → 진행 상태 파일에서 다음 덩어리 (따라잡기)
/trace-study MVP18    → 그 MVP가 건드린 덩어리에 덧씀 (따라가기)
```

두 모드로 스킬을 **나누지 않는다.** §5의 8단계 중 다른 것은 **1단계(대상 고르기)뿐**이고
나머지 7단계와 산출물 형태가 같다. 나누면 그 7단계가 복사되고, 한쪽만 고치면 어긋난다.
(frank 스킬도 같은 구조였다 — `/study MVP1` 또는 인자 없이 `/study`.)

### 무엇이 스킬에 있고 무엇이 여기 있나

**갈라놓은 기준은 "매번 필요한가"이다.**

| | 어디 | 왜 |
|---|---|---|
| 깊이 기준(B/C/D), 범위 밖, 절대 원칙 | **스킬** | 매 세션 필요 — 짧아서 스킬에 넣어도 안 길어진다 |
| 세션 절차 8단계, 노트 형식, 저장 형식 | **스킬** | 매 세션 필요 |
| **따라잡기 9덩어리 표(§3)·순서(§4)** | **이 스펙** | **일회성.** 9개를 다 끝내면 다시 안 본다 |
| 설계 근거, 기각한 것(§7) | 이 스펙 | 결정을 되돌리려 할 때만 |

**그래서 MVP18부터는 스킬만 보면 된다.** 스펙을 읽는 것은 **따라잡기 모드(`/trace-study` 인자 없음)**에서
§3의 덩어리별 파일·테스트·문서 목록을 가져올 때뿐이다.

| 파일 | 바뀌는 주기 | 읽히는 시점 |
|---|---|---|
| 스킬 `SKILL.md` | 거의 안 바뀜 | **매 호출** |
| 이 스펙 | 정하면 끝 | 따라잡기 대상을 고를 때 |
| 진행 상태(plans) | 세션마다 | `/trace-init` + 스킬 |
| 학습 결과물 `docs/study/` | 세션마다 쌓임 | 복습할 때 |

주기가 다른 것을 한 파일에 두지 않는다 — `docs/agent-rules/authoring.md`의
*"lean entry point, one rule one home, index over duplication"*과 같은 이유다.

## 10. 외부 자료 검토 (2026-08-02, `trace-video-review`)

학습 착수 직전에 사용자가 영상 5링크를 가져왔다. **실제로는 강연 4개**였다(`x3e_Yl4NNHY`가
`iv60GIHpijE`와 같은 Litt 강연 — 전자가 한영자막 원본, 후자가 한국어 요약본).
Litt·Schillings 두 편은 `yt-dlp`로 **영어 원본 자막**을 받아 전문을 읽었다.

**결론: 설계를 뒤집는 것은 없었다. 목적 문장이 정확해졌고(§1), C 선택의 독립 근거가 생겼다(§2).**

### 반영하지 않은 것과 이유

| 안 | 이유 |
|---|---|
| **Litt의 `explain-diff` gist 설치** | **이미 있고 더 낫다.** `ce-explain`이 같은 일을 하는데, 사후 퀴즈가 아니라 **예측 후 공개**다(해설을 보기 전에 "이 변경이 뭘 할 것 같나"를 먼저 묻는다). 퀴즈를 HTML 안에 박지 않는 것도 의도적이다 — *"채점은 세션에서 해야 한다"*. `docs/workflow-audit.md` §5-6의 `trace-study` ↔ `ce-explain` 미해결 항목을 이걸로 닫는다 |
| **퀴즈를 게이트로 (통과 못 하면 ✅ 안 켬)** | Litt의 규칙이 작동하는 건 **외부 강제력**(*"팀에 리뷰 보내기 전에"*) 때문이다. Trace는 솔로라 해설을 쓴 에이전트가 몇 분 뒤 문제를 내고 스스로 채점하는 꼴이라 독립 검사가 아니다. 게이트를 세게 걸수록 완주가 어려워지고, 그게 frank가 멈춘 방식이다(§7) |
| **마이크로월드·예측먼저·코드 노출을 스킬에 명문화** | **절차라서 0세션 경험으로 정하면 안 된다.** 셋 다 규칙 없이 세션에서 그냥 해볼 수 있다 — 효과를 본 뒤에 적는다. `docs/backlog.md`에 트리거와 함께 이연 |
| **Google I/O 세션 (T자형 역량·스펙 주도 개발·관측성)** | 조직 얘기라 솔로 프로젝트에 옮길 게 없다. 스펙 주도 개발은 Trace가 이미 한다(design→kickoff→plan→checklist) — 확인일 뿐 도입이 아니다 |
| **Vasuman Moza / FDE 툴링** | 무관. 엔터프라이즈에 에이전트를 심는 B2B 방법론이고 코드 이해와 관계없다 |

### 따라잡기에는 거의 안 붙는다

Litt의 기법은 전부 **diff 모양**이다 — "방금 바뀐 것"을 "이미 알던 것"에 대한 차이로 설명한다.
**따라잡기(§3의 9덩어리)에는 diff가 없다.** 그래서 수확은 아직 한 번도 안 돌려본 **따라가기(§8)**에
있고, 그건 MVP18이 끝나야 돌아간다. 그때는 9세션치 경험이 쌓여 있다 — 지금 정하는 것보다 낫다.
9덩어리 표와 기각 이유까지 스킬에 넣으면 frank의 412줄로 돌아간다.
