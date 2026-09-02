# Trace 현재 기능 전수

현재 checkout에서 사용자가 실제로 이용할 수 있는 기능을 사용자 시나리오 순서로 정리한 사실 원본이다.
사용자와 다음 에이전트가 현재 제품을 이해하고, 이후 포트폴리오 사례를 뽑을 때 근거로 삼는 문서이며,
채용 담당자에게 그대로 제출하는 최종 포트폴리오 문구는 아니다.

- 기준 checkout: `main`의 `780a4ca` (이 문서를 추가한 커밋)
- 작성일: 2026-09-01
- 같은 내용의 시각판: [`current-features.html`](current-features.html) — 사용자 흐름을 그림으로
  보여주고 번호로 아래 항목과 잇는다. 정본은 이 문서이고, 그쪽은 읽기 편하게 만든 것이다.
- 제품 방향의 정본은 [제품 기준선](product-baseline.md), 진행 상태의 정본은 [로드맵](roadmap.md)이다.
- 갱신 시점: 마일스톤 실기기 QA 결과를 사용자가 수용했을 때 해당 흐름만 갱신하고,
  MVP 아카이빙 때 누락 여부를 마지막으로 확인한다. 규칙은 [제품 가시성 규칙](agent-rules/product-visibility.md)에 있다.

## 상태 범례

- `현재 제공`: 현재 코드에서 진입 경로와 동작 근거를 확인했다.
- `조건부·실험`: 특정 권한·환경·기기·설정 조건에서만 쓸 수 있다.
- `확인 필요`: 코드나 테스트만으로 실제 제공 여부를 확정하지 못했다.

## 1. 앱에 들어와 목적을 고른다

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|
| 앱을 처음 연다 | 코스 화면이 먼저 열려서, 오늘 어디를 뛸지 정하는 일부터 시작할 수 있다 | 현재 제공 | [`RootView.swift`](../Trace/App/RootView.swift) | [MVP16 UI 방향 설계](../history/mvp16/2026-07-19-mvp16-ui-direction-design.md) |
| 화면 아래 탭바를 누른다 | 코스·러닝·기록 세 화면을 오가며 달리기 전·중·후의 목적을 직접 고른다 | 현재 제공 | [`AppTab.swift`](../Trace/App/AppTab.swift) · [`AppTabTests`](../TraceTests/AppTabTests.swift) | [MVP16 킥오프 결정](../history/mvp16/2026-07-19-mvp16-ui-restructure-kickoff-design.md) |
| 러닝을 시작한 뒤 화면을 본다 | 카운트다운부터 요약을 닫을 때까지 탭바가 사라져, 달리는 동안 다른 화면으로 새지 않는다 | 현재 제공 | [`AppTab.isTabBarHidden`](../Trace/App/AppTab.swift) · [`AppTabTests`](../TraceTests/AppTabTests.swift) | [MVP16 완료 회고](../history/mvp16/260721_mvp16_completion_retro.md) |
| 러닝 탭에서 지난 기록을 찾는다 | 러닝 탭에는 기록으로 가는 진입점이 없고, 지난 기록은 항상 기록 탭에서 본다. 러닝 화면은 지금 시작하는 일만 다룬다 | 현재 제공 | [`TraceUITests`의 `testRunTabHasNoHistoryEntryPointAndHistoryTabShowsEmptyState`](../TraceUITests/TraceUITests.swift) | [MVP17 run-idle-polish 설계](../history/mvp17/2026-07-23-run-idle-polish-design.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md) |

## 2. 달리기 전 코스를 계획하고 관리한다

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|
| 지도에서 두 지점을 찍는다 | 직선이 아니라 실제로 걸을 수 있는 도보 경로와 그 거리를 확인한다 | 현재 제공 | [`CoursePlannerPageViewModel.handleMapTap`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`MapKitCoursePlanningService`](../Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift) · [`TraceUITests`](../TraceUITests/TraceUITests.swift) | [MVP1 코스 계획 설계](../history/mvp1/2026-06-17-route-planner-mvp-design.md) |
| 이미 만든 경로에 지점을 더 찍는다 | 가까운 쪽 끝점에 자동으로 이어붙어서, 어디에 붙일지 매번 지정하지 않아도 코스가 자란다 | 현재 제공 | [`CourseEditSession.attach`](../Trace/Application/CoursePlanning/CourseEditSession.swift) · [`CourseEditSessionTests`](../TraceTests/CourseEditSessionTests.swift) | [MVP9 편집 정합성 설계](../history/mvp9/2026-07-03-edit-consistency-design.md) · [MVP10 완료 회고](../history/mvp10/260706_mvp10_completion_retro.md) |
| 그리기 모드에서 지도를 꾹 눌러 선을 긋는다 | 머릿속에 있는 코스를 손으로 그리면 실제 도로에 맞춰진 경로로 바뀐다 | 현재 제공 | [`appendStroke`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`DrawnPathSampler`](../Trace/Domain/CoursePlanning/DrawnPathSampler.swift) · [`DrawnPathSamplerTests`](../TraceTests/DrawnPathSamplerTests.swift) | [그리기·스냅 설계](../history/mvp1/2026-06-20-marker-draw-snap-mvp-design.md) · [MVP16 draw-gesture 플랜](../history/mvp16/2026-07-21-draw-gesture.md) |
| 출발 핀을 탭한다 | 지금까지 만든 코스를 출발점으로 되돌아오는 왕복으로 닫는다 | 현재 제공 | [`handleMapTap`의 핀 분기](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`CoursePlannerViewModelTests`](../TraceTests/CoursePlannerViewModelTests.swift) | [MVP9 편집 정합성 설계](../history/mvp9/2026-07-03-edit-consistency-design.md) |
| 구간 목록에서 한 구간의 왕복 버튼을 누른다 | 코스 전체를 다시 그리지 않고 특정 구간만 왕복으로 늘려 거리를 맞춘다 | 현재 제공 | [`insertRoundTrip`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`CourseRoundTripInsertTests`](../TraceTests/CourseRoundTripInsertTests.swift) | [MVP11 코스 저장·왕복 설계](../history/mvp11/2026-07-07-course-save-roundtrip-design.md) |
| 시트에서 전체 왕복을 누른다 | 만든 코스 전체를 한 번에 왕복으로 만들어 거리를 두 배로 잡는다 | 현재 제공 | [`insertWholeCourseRoundTrip`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`CourseRoundTripInsertTests`](../TraceTests/CourseRoundTripInsertTests.swift) | [왕복 수정+전체 왕복 플랜](../history/mvp11/2026-07-08-roundtrip-fix-and-whole-course.md) |
| 방금 붙인 구간이 마음에 안 든다 | 되돌리기·다시하기·전체 지우기로 모드와 무관하게 편집을 취소한다 | 현재 제공 | [`undo`·`redo`·`clear`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`CourseEditSessionTests`](../TraceTests/CourseEditSessionTests.swift) | [MVP6 편집 세션 설계](../history/mvp6/2026-06-29-course-edit-session-design.md) |
| 지도 아래 시트를 편다 | 총거리와 구간별 거리·누적 거리를 한 목록에서 확인하고, 구간을 골라 지도에서 확인한다 | 현재 제공 | [`CoursePlannerPage+BottomSheetComponent`](../Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift) | [MVP7 구간 패널 설계](../history/mvp7/2026-07-01-course-edit-ux-panel-design.md) |
| 구간 목록을 아래로 끌어내린다 | 리스트 스크롤이 끝에 닿으면 그대로 시트가 접혀서, 손을 떼고 다시 잡지 않아도 된다 | 현재 제공 | [`ScrollEdgeState`](../Trace/Pages/CoursePlannerPage/ScrollEdgeState.swift) · [`ScrollEdgeStateTests`](../TraceTests/ScrollEdgeStateTests.swift) · [`TraceUITests`](../TraceUITests/TraceUITests.swift) | [MVP17 sheet-drag 설계](../history/mvp17/2026-07-26-sheet-drag-design.md) |
| 만든 코스에 이름을 붙여 저장한다 | 자주 뛰는 코스를 다음에 다시 만들지 않고 꺼내 쓴다 | 현재 제공 | [`saveCurrentCourse`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`SwiftDataCourseRepository`](../Trace/Infrastructure/Persistence/SwiftData/SwiftDataCourseRepository.swift) · [`SwiftDataCourseRepositoryTests`](../TraceTests/SwiftDataCourseRepositoryTests.swift) | [MVP11 코스 저장·왕복 설계](../history/mvp11/2026-07-07-course-save-roundtrip-design.md) |
| 저장한 코스 목록을 연다 | 코스를 이름·거리·저장일로 고르고, 불러오거나 스와이프로 삭제한다. 작업 중인 코스가 있으면 교체 여부를 먼저 확인한다 | 현재 제공 | [`CoursePlannerPage+CourseListComponent`](../Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+CourseListComponent.swift) · [`CoursePlannerViewModelPersistenceTests`](../TraceTests/CoursePlannerViewModelPersistenceTests.swift) | [MVP11 완료 회고](../history/mvp11/260708_mvp11_completion_retro.md) |
| 지도를 옮기다 현재 위치를 놓친다 | 현재 위치 버튼으로 지도를 지금 있는 곳으로 되돌린다 | 현재 제공 | [`recenterToCurrentLocation`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) | [MVP2 UX 설계](../history/mvp2/2026-06-23-mvp2-ux-throttle-design.md) |
| 앱을 껐다 다시 연다 | 마지막으로 보던 지도 위치에서 이어서 계획한다 | 현재 제공 | [`CameraStateStore`](../Trace/Infrastructure/Camera/CameraStateStore.swift) · [`CameraStateStoreTests`](../TraceTests/CameraStateStoreTests.swift) | [MVP3 UX·스로틀 설계](../history/mvp3/2026-06-24-mvp3-ux-throttle-design.md) |
| 경로 계산이 실패한다 | 도보 경로가 없거나 요청이 몰린 상황을 화면 위 안내로 구분해서 알려준다 | 현재 제공 | [`routeStrokeAndAttach`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`ThrottleDetectionTests`](../TraceTests/ThrottleDetectionTests.swift) · [`TraceUITests`](../TraceUITests/TraceUITests.swift) | [MVP3 UX·스로틀 설계](../history/mvp3/2026-06-24-mvp3-ux-throttle-design.md) |
| 왕복 구간이 같은 길 위에 겹친다 | 겹친 경로를 조금 벌려 그려서 어느 구간이 몇 번 지나가는지 눈으로 구분한다 | 현재 제공 | [`OverlapOffsetResolver`](../Trace/Pages/CoursePlannerPage/OverlapOffsetResolver.swift) · [`OverlapOffsetResolverTests`](../TraceTests/OverlapOffsetResolverTests.swift) | [MVP8 겹침 오프셋 설계](../history/mvp8/2026-07-02-overlap-offset-design.md) |

## 3. 코스 없이 러닝을 준비하고 기록한다

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|
| 러닝 탭을 연다 | 코스를 고르지 않아도 목표를 정하고 바로 달리기 시작한다 | 현재 제공 | [`RunPage.swift`](../Trace/Pages/RunPage/RunPage.swift) · [`TraceUITests`](../TraceUITests/TraceUITests.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) · [MVP17 run-idle-polish 설계](../history/mvp17/2026-07-23-run-idle-polish-design.md) |
| 목표를 고른다 | 자유·거리·시간 중에서 오늘의 기준을 정하고, 거리와 시간은 직접 입력한다. 직전에 쓴 값이 다시 채워진다 | 현재 제공 | [`RunPageViewModel`의 목표 상태](../Trace/Pages/RunPage/RunPageViewModel.swift) · [`RunGoalTests`](../TraceTests/RunGoalTests.swift) · [`RunPageViewModelTests`](../TraceTests/RunPageViewModelTests.swift) | [MVP14 러닝 경험 설계](../history/mvp14/2026-07-15-run-experience-design.md) |
| 시작 버튼을 누른다 | 3·2·1 숫자 음성과 햅틱으로 출발 시점을 맞추고, 잘못 눌렀으면 화면을 탭해 취소한다 | 현재 제공 | [`startTapped`·`cancelCountdown`](../Trace/Pages/RunPage/RunPageViewModel.swift) · [`RunPageViewModelTests`](../TraceTests/RunPageViewModelTests.swift) | [MVP15 run-detail-polish 플랜](../history/mvp15/2026-07-17-run-detail-polish.md) |
| GPS 신호를 기다린다 | 신호를 찾는 중임을 화면에서 보고, 오래 걸리면 취소해서 대기 화면으로 돌아온다 | 현재 제공 | [`RunSession.finishAcquiringCancelled`](../Trace/Application/RunTracking/RunSession.swift) · [`RunSessionTests`](../TraceTests/RunSessionTests.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |
| 달리는 중에 화면을 본다 | 지금까지의 거리·활동 시간·평균 페이스를 크게 확인하고, 목표를 정했으면 진행률까지 본다 | 현재 제공 | [`RunPage+StatsPanelComponent`](../Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift) · [`RunPageViewModelTests`](../TraceTests/RunPageViewModelTests.swift) | [MVP16 run-fullscreen 플랜](../history/mvp16/2026-07-20-run-fullscreen.md) |
| 신호등에서 멈춘다 | 일시정지하면 그동안의 시간과 거리가 기록에서 빠져서, 실제로 달린 시간 기준의 페이스가 유지된다 | 현재 제공 | [`RunSession.pause`·`resume`](../Trace/Application/RunTracking/RunSession.swift) · [`RunSessionTests`](../TraceTests/RunSessionTests.swift) · [`RunPauseIntervalTests`](../TraceTests/RunPauseIntervalTests.swift) | [MVP14 run-pause-resume 플랜](../history/mvp14/2026-07-15-run-pause-resume.md) · [MVP14 완료 회고](../history/mvp14/260717_mvp14_completion_retro.md) |
| 달리다가 포인트 버튼을 누른다 | 지금 지점을 표시해 두고, 직전 포인트에서 여기까지의 구간 거리를 화면 카드와 음성으로 바로 확인한다 | 현재 제공 | [`markWaypointTapped`](../Trace/Pages/RunPage/RunPageViewModel.swift) · [`RunSessionWaypointTests`](../TraceTests/RunSessionWaypointTests.swift) | [MVP15 run-waypoints 플랜](../history/mvp15/2026-07-18-run-waypoints.md) |
| 화면을 보지 않고 달린다 | 1킬로미터마다, 목표 절반과 달성 시점에, 그리고 종료할 때 거리·시간·평균 페이스를 음성으로 듣는다 | 현재 제공 | [`RunAudioCoach`](../Trace/Application/RunTracking/RunAudioCoach.swift) · [`RunAudioCoachTests`](../TraceTests/RunAudioCoachTests.swift) · [`RunAnnouncementBuilderTests`](../TraceTests/RunAnnouncementBuilderTests.swift) | [MVP14 run-splits-audio 플랜](../history/mvp14/2026-07-16-run-splits-audio.md) |
| GPS가 흔들린다 | 정확도가 낮은 위치는 거리 적산에서 빠지고, 신호가 약해지면 화면에 표시된다 | 현재 제공 | [`RunSession.ingest`](../Trace/Application/RunTracking/RunSession.swift) · [`RunSessionTests`](../TraceTests/RunSessionTests.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |
| 러닝을 끝낸다 | 종료 버튼을 길게 눌러야 끝나서, 달리는 중에 실수로 종료되지 않는다 | 현재 제공 | [`RunPage+StatsPanelComponent`의 종료 홀드](../Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift) | [MVP15 run-detail-polish 플랜](../history/mvp15/2026-07-17-run-detail-polish.md) |
| 요약 화면을 본다 | 방금 달린 거리·시간·평균 페이스를 확인하고, 기록이 자동으로 저장된 것을 그 자리에서 확인한다 | 현재 제공 | [`RunSummaryPanel`](../Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift) · [`RunSession.startRecordSave`](../Trace/Application/RunTracking/RunSession.swift) · [`SwiftDataRunRecordRepositoryTests`](../TraceTests/SwiftDataRunRecordRepositoryTests.swift) | [MVP13 기록 저장 설계](../history/mvp13/2026-07-14-run-record-save-design.md) |
| 저장이 실패한다 | 실패 사실을 요약 화면에서 보고 같은 기록을 다시 저장한다. 재시도해도 기록이 중복되지 않는다 | 현재 제공 | [`RunSession.retrySave`](../Trace/Application/RunTracking/RunSession.swift) · [`RunSessionTests`](../TraceTests/RunSessionTests.swift) | [MVP13 기록 저장 설계](../history/mvp13/2026-07-14-run-record-save-design.md) |

## 4. 지난 러닝을 돌아보고 관리한다

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|
| 기록 탭을 연다 | 이번 주·이번 달·전체 중 기간을 골라 총거리·횟수·총시간을 한눈에 본다 | 현재 제공 | [`HistoryPage+DashboardComponent`](../Trace/Pages/HistoryPage/UIComponent/HistoryPage+DashboardComponent.swift) · [`RunStatsCalculatorTests`](../TraceTests/RunStatsCalculatorTests.swift) | [MVP17 킥오프 결정](../history/mvp17/2026-07-21-mvp17-run-history-kickoff-design.md) |
| 대시보드의 그래프를 본다 | 최근 8주 주간 거리 막대로 요즘 얼마나 달리고 있는지 추이를 본다. 막대 수는 기간 선택과 무관하게 고정이다 | 현재 제공 | [`HistoryPageViewModel.weeklyBars`](../Trace/Pages/HistoryPage/HistoryPageViewModel.swift) · [`HistoryPageViewModelTests`](../TraceTests/HistoryPageViewModelTests.swift) | [MVP17 history-tab 플랜](../history/mvp17/2026-07-21-history-tab.md) |
| 아직 기록이 없다 | 빈 화면 대신 러닝을 마치면 기록이 자동 저장된다는 안내를 본다 | 현재 제공 | [`HistoryPage.swift`](../Trace/Pages/HistoryPage/HistoryPage.swift) · [`TraceUITests`](../TraceUITests/TraceUITests.swift) | [MVP17 history-tab 플랜](../history/mvp17/2026-07-21-history-tab.md) |
| 목록에서 기록 하나를 연다 | 그날 달린 경로를 지도 위에서 다시 보고, 거리·시간·평균 페이스를 확인한다 | 현재 제공 | [`HistoryRecordDetailView`](../Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift) · [`RunHistoryViewModelTests`](../TraceTests/RunHistoryViewModelTests.swift) | [MVP13 기록 저장 설계](../history/mvp13/2026-07-14-run-record-save-design.md) |
| 기록 상세를 내려본다 | 킬로미터별 페이스 표로 어느 구간에서 빨라지고 느려졌는지 확인한다 | 현재 제공 | [`RunSplitCalculator`](../Trace/Domain/RunTracking/Entity/RunSplit.swift) · [`RunSplitCalculatorTests`](../TraceTests/RunSplitCalculatorTests.swift) | [MVP14 run-splits-audio 플랜](../history/mvp14/2026-07-16-run-splits-audio.md) |
| 달리면서 찍은 포인트를 확인한다 | 지도 위 번호 마커와 구간 표로 포인트 사이 거리를 확인하고, 잘못 찍은 포인트는 지운다. 지운 구간의 거리는 앞뒤 구간에 합쳐진다 | 현재 제공 | [`RunWaypointsSection`](../Trace/Pages/HistoryPage/UIComponent/HistoryPage+RecordComponent.swift) · [`RunWaypointSegmentsCalculatorTests`](../TraceTests/RunWaypointSegmentsCalculatorTests.swift) · [`RunHistoryViewModelTests`](../TraceTests/RunHistoryViewModelTests.swift) | [MVP15 run-waypoints 플랜](../history/mvp15/2026-07-18-run-waypoints.md) · [MVP15 완료 회고](../history/mvp15/260719_mvp15_completion_retro.md) |
| 기록을 지운다 | 목록에서 스와이프해 지우되, 되돌릴 수 없다는 확인을 한 번 거친다 | 현재 제공 | [`RunHistoryViewModel.confirmPendingDelete`](../Trace/Pages/HistoryPage/RunHistoryViewModel.swift) · [`RunHistoryViewModelTests`](../TraceTests/RunHistoryViewModelTests.swift) | [MVP13 기록 저장 설계](../history/mvp13/2026-07-14-run-record-save-design.md) |
| 러닝을 마치고 기록 탭으로 간다 | 방금 저장된 기록이 목록에 이미 들어와 있다 | 현재 제공 | [`RootView`의 저장 완료 재조회](../Trace/App/RootView.swift) · [`DependencyContainer`](../Trace/App/DependencyContainer.swift) | [MVP13 완료 회고](../history/mvp13/260715_mvp13_completion_retro.md) |

## 5. 주 흐름을 보조하는 조건부 경험

이 절의 항목은 권한·기기·시스템 설정에 따라 있을 수도 없을 수도 있다. 일반 제공 기능과 섞어 읽지 않는다.

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|
| 위치 권한을 아직 안 줬다 | 왜 위치가 필요한지 안내를 보고 설정 화면으로 바로 이동한다. 권한이 없어도 코스 화면은 서울 기준 위치로 열린다 | 조건부·실험 | [`bootstrapLocation`](../Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift) · [`RunPage.swift`의 알럿](../Trace/Pages/RunPage/RunPage.swift) | [MVP2 UX 설계](../history/mvp2/2026-06-23-mvp2-ux-throttle-design.md) |
| 정확한 위치가 꺼져 있다 | 러닝 시작 시 이번 러닝에 한해 정확한 위치를 요청받고, 거부하면 시작하지 않고 이유를 안내받는다 | 조건부·실험 | [`RunSession.prepareStart`](../Trace/Application/RunTracking/RunSession.swift) · [`Config/Trace-Info.plist`](../Config/Trace-Info.plist) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |
| 달리는 중에 화면을 잠근다 | 잠금화면과 다이내믹 아일랜드에서 거리·시간·페이스를 확인한다. 시스템에서 라이브 액티비티를 껐으면 카드 없이 러닝만 진행된다 | 조건부·실험 | [`RunActivityController`](../Trace/Application/RunTracking/RunActivityController.swift) · [`RunLiveActivityWidget`](../TraceWidgets/RunLiveActivityWidget.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |
| 잠금화면에서 포인트를 찍는다 | 앱을 열지 않고 잠금화면 카드의 버튼으로 포인트를 찍는다. 라이브 액티비티가 없으면 이 버튼도 없다 | 조건부·실험 | [`MarkRunWaypointIntent`](../Trace/App/MarkRunWaypointIntent.swift) · [`RunWaypointIntentActionTests`](../TraceTests/RunWaypointIntentActionTests.swift) | [MVP15 run-waypoints 플랜](../history/mvp15/2026-07-18-run-waypoints.md) |
| 음악을 들으며 달린다 | 안내 음성이 나올 때만 음악이 잠깐 작아지고 다시 돌아온다 | 조건부·실험 | [`SpeechVoiceAnnouncer`](../Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift) · [`Config/Trace-Info.plist`의 `audio` 모드](../Config/Trace-Info.plist) | [MVP14 run-splits-audio 플랜](../history/mvp14/2026-07-16-run-splits-audio.md) |
| 달리는 중에 위치 권한이 회수된다 | 그때까지 모은 경로를 버리지 않고 요약과 저장으로 넘어간다. 아직 한 점도 못 모았으면 대기 화면으로 돌아간다 | 조건부·실험 | [`RunSession.streamEnded`](../Trace/Application/RunTracking/RunSession.swift) · [`RunSessionTests`](../TraceTests/RunSessionTests.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |
| 달리는 동안 화면을 끄거나 앱을 내린다 | 화면을 꺼도 경로 기록이 이어진다 | 확인 필요 | 백그라운드 위치 모드 선언([`Config/Trace-Info.plist`](../Config/Trace-Info.plist))과 권한 문구는 코드에 있으나, 실제 지속 여부는 실기기에서만 확정된다 | [MVP13 실기기 체크리스트](../history/mvp13/2026-07-14-run-tracking-device-checklist.md) |
| 앱을 강제 종료한 뒤 다시 연다 | 이전 러닝은 복구되지 않고 대기 상태로 시작하며, 잠금화면에 남아 있던 카드는 정리된다 | 조건부·실험 | [`RunActivityController.endOrphanedActivities`](../Trace/Application/RunTracking/RunActivityController.swift) | [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) |

## 현재 목록에 없는 것

아래는 지금 제공되지 않는 것이라 위 흐름에 넣지 않는다. 바뀐 이유는 각 회고에 있다.

- **러닝 탭의 지도**: 러닝 화면에서 지도를 완전히 제거했다. [MVP16 run-fullscreen 플랜](../history/mvp16/2026-07-20-run-fullscreen.md) · [MVP16 완료 회고](../history/mvp16/260721_mvp16_completion_retro.md)
- **러닝 탭의 이번 주 요약 줄**: 도입 후 실기기 확인을 거쳐 철회하고 목표 설정 흐름으로 대체했다. [MVP17 run-idle-polish 설계](../history/mvp17/2026-07-23-run-idle-polish-design.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)
- **코스 초안 자동 저장·복원**: 도입 후 제거해, 완전 종료 뒤에는 빈 상태로 시작한다. [초안 저장 제거 플랜](../history/mvp11/2026-07-08-remove-draft-persistence.md)
- **그리기 중 두 손가락 지도 이동**: 그리기 제스처를 롱프레스-드래그로 바꾸면서 제거했다. [MVP16 draw-gesture 플랜](../history/mvp16/2026-07-21-draw-gesture.md)
- **홈 화면 위젯**: 위젯 타깃에는 러닝 라이브 액티비티만 있고 홈 화면 위젯은 없다. [`TraceWidgetsBundle`](../TraceWidgets/TraceWidgetsBundle.swift)
- **저장한 코스를 골라 그 코스로 달리기**: 코스 계획과 러닝은 서로 독립된 기둥이고, 둘을 잇는 경험은 아직 없다. [제품 기준선](product-baseline.md) · [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md)
- **러닝 요약의 샘플 덤프 내보내기**: `#if DEBUG` 안에만 있어서 출시 빌드의 사용자에게는 노출되지 않는 QA 도구다. [`RunSampleDumpEncoder`](../Trace/Pages/RunPage/RunSampleDumpEncoder.swift)
