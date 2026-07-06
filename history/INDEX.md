# History Index

완료된 MVP 아카이브. 각 MVP는 마일스톤(spec+plan) + 완료 회고 (+ 학습 `concepts.md`)로 구성된다.
갱신은 `/trace-archive`가 수행한다. 단위·흐름 규칙은 `docs/agent-rules/workflow.md` 참고.

> 일일 회고(`history/daily-retro/<YYMMDD>_daily_retro.*`)는 `/daily-retro` 산출물로, 이 인덱스와 별개다.

---

## MVP1 — 러닝 코스 계획 (2026-06-17 ~ 06-20)

> 지도에서 코스를 계획하고 거리를 재는 핵심 경험. iOS / SwiftUI / MapKit. 마일스톤 2개 + 구조 정리.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [route-planner 설계](mvp1/2026-06-17-route-planner-mvp-design.md) | 지도 화면 + 두 포인트 거리재기, 포트-어댑터 |
| 플랜 | [route-planner 플랜](mvp1/2026-06-17-route-planner-mvp.md) | Task 1~7, TDD ViewModel→도메인→어댑터→UI |
| 구조 | [폴더 구조 개편](mvp1/2026-06-17-folder-restructure-course-planning.md) | CoursePlanning 도메인 정렬 (Domain/Infrastructure/Pages) |
| 기획 | [marker-draw-snap 설계](mvp1/2026-06-20-marker-draw-snap-mvp-design.md) | 그리기→스냅, DrawnPathSampler + MKDirections walking |
| 플랜 | [marker-draw-snap 플랜](mvp1/2026-06-20-marker-draw-snap-mvp.md) | Task 1~6 (소급 완료), 스파이크로 스위트스폿 실측 |
| QA | [실기기 체크리스트](mvp1/2026-06-20-marker-draw-snap-device-checklist.md) | 마커-스냅 실기기 검증 항목 |
| 회고 | [MVP1 완료 회고](mvp1/260622_mvp1_completion_retro.md) | Keep/Problem/Surprise, 기술부채, 다음 방향 |

---

## MVP10 — 제스처 정합성 (탭 보류 확정·픽셀 판정·2손가락 튜닝·attach 방향 판정 재설계) (2026-07-04 ~ 07-06)

> 탭 즉시 확정을 "0.3초 보류 → 확정/취소"로 교체(더블탭·원핑거 줌 분리), 그리기 시작점 근접 판정
> 화면 24pt 기준 전환, 두손가락 제스처 경쟁 튜닝. 실기기 QA에서 발견된 attach 방향 판정 버그(근접·
> 원거리 양쪽 모두 스트로크 끝점을 무시하던 근본 원인)를 4번째 마일스톤으로 편입해 해결. 마일스톤
> 4개 + 실기기 QA 버그 4건(마커 라벨/깜빡임, 두손가락 줌아웃, attach 방향 판정) 수정·재검증.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [gesture-consistency 설계](mvp10/2026-07-04-gesture-consistency-design.md) | 탭 판별기(TapClassifier), 화면 픽셀 히트 판정, 두손가락 delegate 조정 |
| 플랜 | [gesture-consistency 플랜](mvp10/2026-07-04-gesture-consistency.md) | Task 1~6, TDD TapClassifier→픽셀 히트→delegate→QA |
| 기획 | [attach-nearest-fallback 설계](mvp10/2026-07-05-attach-nearest-fallback-design.md) | attach 규칙 4 재설계(시작점 단일 최근접 비교), 이후 근접·원거리 끝점 대칭 처리로 확장 |
| 플랜 | [attach-nearest-fallback 플랜](mvp10/2026-07-05-attach-nearest-fallback.md) | Task 1~3, subagent-driven-development로 실행, 전체 브랜치 리뷰(opus) clean |
| QA | [실기기 체크리스트](mvp10/2026-07-04-gesture-consistency-device-checklist.md) | 시나리오 1~19, 버그 4건 발견·수정·재검증 완료 |
| 회고 | [MVP10 완료 회고](mvp10/260706_mvp10_completion_retro.md) | 적대적 서브에이전트 리뷰가 반례 2회 적발, advisor의 과신 지적, 사용자의 재분류 정정 |

---

## MVP9 — 편집 정합성 (왕복·핀·redo) (2026-07-03 ~ 07-04)

> attach 이어붙이기 규칙을 순서 규칙(반전은 출발점 연장 단일 예외)으로 교체, 끝점 근접 탭 왕복, 닫힌
> 코스 병합 핀, 경유점 마커, redo. 마일스톤 1개(태스크 8개) + 실기기 QA 버그 6건(그리기 모드 라우팅
> 스냅, 핀 선택 애니메이션, 병합 배지 위치, 경유점 z-order 3차 수정, 거리 라벨 위치) 수정.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [edit-consistency 설계](mvp9/2026-07-03-edit-consistency-design.md) | attach 규칙 1~4, 핀 히트 분기·왕복·무시·안내, 병합 핀·경유점, redo |
| 플랜 | [edit-consistency 플랜](mvp9/2026-07-03-edit-consistency.md) | Task 1~8, subagent-driven-development로 실행, 전체 브랜치 리뷰(opus) clean |
| QA | [실기기 체크리스트](mvp9/2026-07-04-edit-consistency-device-checklist.md) | 3차례 실기기 QA, 버그 6건 발견·수정·재확인, 2건은 다음 MVP로 이연 |
| 회고 | [MVP9 완료 회고](mvp9/260704_mvp9_completion_retro.md) | 검증 스탬프 신선도 재발, 애노테이션 z-order 신뢰 불가, 실기기 디버그 로그로 버그/설계문제 구분 |

---

## MVP8 — 코스 편집·가독성 UX 마무리 (2026-07-02 ~ 07-03)

> 구간 패널 최대 높이(40%)+스크롤+자동 추적, 그리기 모드 핀치 줌 네이티브 복원, 겹치는 경로(왕복 등)
> 좌표 오프셋 렌더링. 마일스톤 2개 + 실기기 QA 버그 1건(스크롤 인디케이터 패딩) 수정.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [course-ux-polish 설계](mvp8/2026-07-02-course-ux-polish-design.md) | 패널 40% 상한(지도 높이 기준) + 채팅 앱 방식 자동 스크롤, 핀치 줌 네이티브 복원 |
| 플랜 | [course-ux-polish 플랜](mvp8/2026-07-02-course-ux-polish.md) | Task 1~4, TDD SegmentPanelLogic→패널 뷰→핀치 삭제→QA |
| 기획 | [overlap-offset 설계](mvp8/2026-07-02-overlap-offset-design.md) | 점-대-선분 감지·생성 순서 우선·4m×n 오프셋·실거리 15m 테이퍼·핀 지점 예외 |
| 플랜 | [overlap-offset 플랜](mvp8/2026-07-02-overlap-offset.md) | Task 1~5, TDD 기하 원시 함수→Resolver→테이퍼→지도 연동→QA |
| QA | [실기기 체크리스트](mvp8/2026-07-03-mvp8-course-ux-device-checklist.md) | 마일스톤 1+2 통합, 실기기 테스트 결과 반영 |
| 회고 | [MVP8 완료 회고](mvp8/260703_mvp8_completion_retro.md) | 임시 print+실기기 로그로 겹침 오프셋 정상 동작 확정, 탭 자동 연결과의 결합 이슈 발견, 핀 라벨링 백로그 |

---

## MVP7 — 코스 편집 UX 개선 (2026-07-01)

> 탭 자동 연결(A) + 그리기 스트로크=세그먼트(A-2) + 지도 위 구간 색상·거리 라벨(B) + 실시간 구간 패널(E) + 실기기 QA 버그 3건(undo/prepend 색상, 도착 마커 미표시, 위치 버튼 오작동) 수정. 마일스톤 1개 + 버그 3건.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [course-edit-ux-panel 설계](mvp7/2026-07-01-course-edit-ux-panel-design.md) | 탭 자동 연결 + 구간 시각화 + 실시간 패널, C/D 버그는 범위 밖으로 분리 |
| 플랜 | [course-edit-ux-panel 플랜](mvp7/2026-07-01-course-edit-ux-panel.md) | Task 1~5, TDD handleMapTap→그리기 스트로크→팔레트→지도 렌더링→패널 |
| QA | [실기기 체크리스트](mvp7/2026-07-01-course-edit-ux-panel-device-checklist.md) | 시나리오 1~7 + 제스처/견고성/의도 일치, C/D 해결 반영 |
| 회고 | [MVP7 완료 회고](mvp7/260701_mvp7_completion_retro.md) | segmentIndex/colorKey 분리, ContinuationBroadcaster로 재진입 버그 테스트화, roadmap 소급 등록 교훈 |

---

## MVP6 — 탭↔그리기 통합 + undo/clear 통합 (2026-06-29)

> CourseEditSession Application 레이어 도입. 탭 경로 누적, 탭↔그리기 자동 이어붙이기, 모드 무관 undo/clear 구현. 마일스톤 1개 + QA 버그 2건 수정.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [course-edit-session 설계](mvp6/2026-06-29-course-edit-session-design.md) | CourseEditSession 오케스트레이터, attach/undo/clear, 4쌍 방향 판단 + gap 라우팅 |
| 플랜 | [course-edit-session 플랜](mvp6/2026-06-29-course-edit-session.md) | Task 1~3, TDD CourseEditSession→ViewModel→View |
| 회고 | [MVP6 완료 회고](mvp6/260629_mvp6_completion_retro.md) | nil 케이스 설계 누락, Xcode 26 파일 자동 감지, SDD ledger 효과 |

---

## MVP5 — 경로 이어붙이기 + 조작 개선 (2026-06-27 ~ 06-28)

> 탭↔그리기 양방향 경로 이어붙이기(CourseSegment 세그먼트 모델), 2손가락 pan UX 보완, iOS 18 Observable 크래시 원인 규명 + 문서화, 실기기 QA 후 핀·라벨 UX 버그 수정. 마일스톤 4개.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [MVP5 설계](mvp5/2026-06-27-mvp5-design.md) | 세그먼트 모델 설계, 2손가락 pan 수정 방향, iOS 버전 전략 |
| 플랜 | [path-stitching 플랜](mvp5/2026-06-27-mvp5-path-stitching.md) | Task 1~8, TDD CourseSegment→history→toggleDrawingMode→MapView |
| QA | [실기기 체크리스트](mvp5/2026-06-28-mvp5-path-stitching-device-checklist.md) | 탭/그리기 혼합, 2손가락 제스처, 핀·라벨 검증 |
| 회고 | [MVP5 완료 회고](mvp5/260628_mvp5_completion_retro.md) | 핀 소스 이중화 버그, 라벨 UX 오판, preDrawTapState 패턴 |

---

## MVP4 — MKMapView 마이그레이션 + 드로우 정밀도 (2026-06-26 ~ 06-27)

> SwiftUI Map 제스처 한계 해결: MKMapView(UIViewRepresentable) 교체 + 드로우/탭/2손가락 제스처 재설계. DrawnPathSampler 루프 경로 버그 수정(누적거리 기반). 마일스톤 2개.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [MVP4 설계](mvp4/2026-06-26-mvp4-design.md) | MKMapView 래핑 아키텍처, 제스처 분리, DrawnPathSampler 수정 |
| 플랜 | [mkmap-migration 플랜](mvp4/2026-06-26-mkmap-migration.md) | Task 1~3, MapViewRepresentable + Coordinator + CoursePlannerPage 통합 |
| 플랜 | [drawing-precision 플랜](mvp4/2026-06-26-drawing-precision.md) | Task 1~2, TDD 누적거리 기반 샘플러 + 스로틀 감지 |
| QA | [실기기 체크리스트](mvp4/2026-06-27-mvp4-device-test.md) | mkmap-migration + drawing-precision 실기기 검증 항목 |
| 회고 | [MVP4 완료 회고](mvp4/260627_mvp4_completion_retro.md) | 브랜치 꼬임, makeUIView GR silent no-op, 핀치 UX 부자연스러움 |

---

## MVP3 — UX 개선 + 스로틀 강화 (2026-06-24 ~ 06-25)

> MVP2 실기기 피드백 반영: 카메라 점프 제거, 비연속 구간 방향 감지, 증분 라우팅, 스로틀 에러 안내. 2손가락 지도 이동은 SwiftUI Map 제스처 한계로 보류.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [MVP3 설계](mvp3/2026-06-24-mvp3-ux-throttle-design.md) | 카메라 복원 + 방향 감지 + 증분 계산 + 스로틀 감지 + 2손가락(보류) |
| 플랜 | [MVP3 플랜](mvp3/2026-06-24-mvp3-ux-throttle.md) | Task 1~7 (Task 7 보류), SDD 실행 |
| QA | [실기기 체크리스트](mvp3/2026-06-25-mvp3-device-checklist.md) | 카메라/그리기/스로틀 검증 항목 |
| 회고 | [MVP3 완료 회고](mvp3/260625_mvp3_completion_retro.md) | SwiftUI Map 제스처 한계 발견, MKMapView 교체 방향 |

---

## MVP2 — UX 개선 + 스로틀 완화 (2026-06-23)

> MVP1 실기기 피드백 반영: 단일 모드 전환, 위치 UX, 모드 표시, 구간 캐시, 디바운스. 마일스톤 2개.

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [MVP2 설계](mvp2/2026-06-23-mvp2-ux-throttle-design.md) | UX 개선 6항목 + 스로틀 완화 요구사항 |
| 플랜 | [MVP2 플랜](mvp2/2026-06-23-mvp2-ux-throttle.md) | Task 1~6, TDD ViewModel→View→캐시→디바운스→검증 |
| QA | [실기기 체크리스트](mvp2/2026-06-23-mvp2-ux-throttle-device-checklist.md) | 9플로우 36항목 실기기 검증 |
| 회고 | [MVP2 완료 회고](mvp2/260623_mvp2_completion_retro.md) | Keep/Problem/Surprise, iOS 18 버그 대응, 기술부채 |
