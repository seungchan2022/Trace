# 2026-06-26 하루 회고

> 이 회고는 밀린 뒤 커밋 기록을 바탕으로 재구성했습니다. 그날의 느낀 점·감정은 정확히 기억나지
> 않아 생략하고, 무엇을 왜 했는지 위주로 정리합니다.

## 오늘 뭘 했나

MVP4 `mkmap-migration` 마일스톤의 핵심 작업일. SwiftUI `Map`이 그리기 모드에서 오버레이 제스처를
제대로 못 받는 한계에 부딪혀, `MKMapView`를 `UIViewRepresentable`로 직접 감싸는 `MapViewRepresentable`을
새로 만들고, `CoursePlannerPage`를 여기에 통합했다.

- `ae5f662` MapViewRepresentable 코어 구현 — 카메라 동기화(무한루프 방지), `MKPolyline` 오버레이,
  `ColoredPinAnnotation`을 Coordinator 패턴으로.
- `9613c26` 제스처 추가 — 1손가락 드로우(`UIPanGestureRecognizer`), 탭, 기본 팬을 2손가락으로 변경해
  드로우와 충돌 방지.
- `1f1d0a5` 핀 갱신 버그 수정 — `pinsChanged`가 위도만 비교해서 동서 이동 시 핀이 안 갱신되던 결함,
  리뷰 중 발견.
- `24ed5e7` overlay 비교 보강 + 끝점 추가 + tapGR 초기화 — 드로우 종료 시 마지막 터치 좌표 누락, overlay
  교체 조건이 개수만 보던 것 보강.
- `c0b254a` CoursePlannerPage를 SwiftUI Map에서 MapViewRepresentable로 최종 통합.

## 핵심 의사결정과 이유

- **SwiftUI Map → MKMapView 마이그레이션**: SwiftUI `Map`으로는 커스텀 오버레이 제스처(드로우)를
  안정적으로 받을 수 없다는 한계가 이전 MVP3에서 이미 확인됐고, 이번에 실제 교체를 실행.
- **팬 제스처를 2손가락으로 전환**: 1손가락을 드로우 제스처가 쓰기 때문에, 지도 자체 이동은
  2손가락으로 분리해 충돌을 피함.
- **핀/오버레이 비교 로직을 좌표 단위로 보강**: "개수만 비교"나 "위도만 비교" 같은 얕은 비교가
  실제로 놓치는 케이스(동서 이동, 끝점 누락)가 있어 리뷰 중에 바로 잡음.

## 배운 것 / 내일 할 일

- Coordinator 패턴으로 UIKit 뷰를 감쌀 때, 상태 비교 로직(오버레이 교체 여부, 카메라 갱신 여부)을
  얕게 짜면 특정 방향의 이동만 놓치는 버그가 잘 생긴다는 걸 확인.
- 다음 날(06-27)은 그리기 모드 제스처 마무리 + MVP4 아카이빙, MVP5 착수로 이어짐.
