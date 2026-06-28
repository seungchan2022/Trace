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
