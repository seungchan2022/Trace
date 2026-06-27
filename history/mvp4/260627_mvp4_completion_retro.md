# MVP4 완료 회고 (2026-06-27)

## Keep — 잘 된 것

- **MKMapView 마이그레이션 방향 선택이 옳았다.** SwiftUI Map의 제스처 hit-test 소유권 문제는 UIViewRepresentable 래핑으로 완전히 해결됐다. 1손가락 드로우 + 2손가락 지도 이동이 실기기에서 동작한다.
- **SDD(Subagent-Driven Development)가 복잡한 마이그레이션에 효과적이었다.** Task별 fresh subagent + 리뷰 사이클이 overlay 비교 버그(count-only → count+좌표), longitude 비교 누락 등을 리뷰 단계에서 잡았다.
- **실기기 테스트를 MVP 종료 전에 진행한 것.** 시뮬레이터에서 검증 불가능한 제스처 버그(2손가락 이동, 핀치)를 실기기에서만 발견할 수 있었다.
- **DrawnPathSampler TDD.** 누적거리 기반 교체를 테스트 6개 먼저 작성 → 구현 → 전부 통과 순으로 진행해 루프 경로 버그를 구조적으로 제거했다.

## Problem — 문제가 된 것

- **두 브랜치 동시 진행으로 git 그래프 꼬임.** mkmap-migration과 drawing-precision을 같은 base에서 동시에 진행했더니 커밋 날짜가 겹쳐 시각적으로 브랜치가 끼어드는 현상 발생. 조치: drawing-precision을 mkmap-migration 위에 rebase 후 FF 머지로 선형화. 예방책은 git.md에 추가했다.
- **makeUIView 시점 내장 GR silent no-op.** MKMapView의 내부 UIPanGestureRecognizer에 `minimumNumberOfTouches = 2`를 설정하는 방식이 실기기에서 동작하지 않았다. makeUIView 시점에 내부 GR이 아직 없는 것이 원인. `isScrollEnabled / isZoomEnabled` 토글 방식으로 재설계했다.
- **drawing-precision 브랜치 위치 오류.** 이전 세션에서 브랜치를 잘못된 base에 생성해 삭제·재생성하는 과정에서 혼선이 있었다.

## Surprise — 예상과 달랐던 것

- **스로틀 에러 감지가 이미 맞았다.** 실기기 로그를 보니 `GEOErrorDomain Code=-3`이 발생하고, isThrottled 조건에 이미 포함되어 있었다. Task 2(스로틀 감지 수정)는 코드 변경 없이 완료.
- **핀치 UX가 내장 MKMapView 핀치보다 부자연스럽다.** 커스텀 UIPinchGestureRecognizer가 동작하기는 하지만 가속도·감도가 내장과 다르다. 백로그로 이동.
- **탭↔그리기 모드 경로 이어붙이기는 구조 변경이 필요하다.** 단순히 course를 유지하는 것만으로는 안 되고, course 데이터 모델을 세그먼트 배열로 확장해야 한다. 다음 MVP로.

## 마일스톤별 핵심 의사결정

### mkmap-migration
- `MapViewRepresentable`(UIViewRepresentable) + Coordinator(MKMapViewDelegate) 분리 채택
- updateUIView에 카메라 threshold(0.0001) + overlay count+좌표 비교 게이트로 무한루프 방지
- 제스처: 최종적으로 `isScrollEnabled/isZoomEnabled` 토글 + 커스텀 pan/pinch(그리기 모드) 방식 채택

### drawing-precision
- 직선거리(start↔end) 기반 → 획을 따라 이동한 누적거리 기반으로 교체 (루프 경로 붕괴 버그 근본 수정)
- minSpacingMeters=120m 유지 (실기기 스로틀 테스트 통과 기준)

## 남은 기술부채 (→ backlog)

- **핀치 UX 개선**: 커스텀 핀치 감도·가속도를 내장 MKMapView 수준으로 개선
- **탭↔그리기 경로 이어붙이기**: course 데이터 모델 세그먼트 배열 확장 + 모드 전환 시 이전 경로 연장

## 다음 MVP 방향

백로그 항목 중 우선 후보:
- 탭↔그리기 경로 이어붙이기 (사용자 요청, UX 핵심)
- 핀치 UX 개선 (품질 개선)
- 그 외 backlog.md 항목 검토
