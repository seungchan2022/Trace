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
