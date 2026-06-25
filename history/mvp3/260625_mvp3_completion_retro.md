# MVP3 완료 회고 (2026-06-25)

## Keep — 잘한 것

- **증분 계산 설계가 효과적**: 전체 재라우팅 → 새 구간만 계산으로 바꾸면서 MKDirections 호출 수를 근본적으로 줄임. 스로틀 체감 개선.
- **자동 방향 감지**: 4쌍 거리 비교 + 스트로크 reverse로 prepend/append를 자연스럽게 처리. 역주행 버그 방지.
- **카메라 복원**: UserDefaults에 백그라운드 전환 시 1번 저장, 재실행 시 즉시 복원. 점프 완전 제거.
- **Advisor 리뷰 효과**: 스펙 확정 전 advisor 리뷰에서 증분 계산 설명 오류, prepend 역주행 버그, 카메라 동작 모호성 3건을 잡아냄.

## Problem — 문제

- **2손가락 지도 이동 실패**: SwiftUI Map 위에 오버레이를 올리는 구조에서는 UIKit 제스처 전달이 근본적으로 불가능. Phase 1(interactionModes 변경) → Phase 2(UIViewRepresentable) 모두 실패. hit-test 소유권 문제는 사전 리서치로 발견하기 어려웠음.
- **스로틀 에러 domain 미확인**: `GEOErrorDomain Code=-3`이 실제 기기에서 작동하는지 검증하지 못함. 실기기 테스트에서 "경로를 계산할 수 없습니다"만 표시. 디버그 로깅 추가했으나 실제 domain/code 확인 필요.
- **서울시청 폴백 초기값 누락**: `.automatic` 초기값이 서울시청 표시를 방해 — 실기기에서 발견. 시뮬레이터에서는 위치가 빨리 잡혀서 드러나지 않았음.

## Surprise — 예상 밖

- **SwiftUI Map과 UIKit 제스처의 벽**: SwiftUI의 `.simultaneousGesture`, `.highPriorityGesture`는 Map 내부의 UIKit 제스처에 영향을 주지 않음. 두 제스처 시스템이 완전히 분리되어 있다는 사실은 심층 리서치로 밝혀짐.
- **MKMapView 교체가 유일한 해법**: 그리기 + 지도 이동을 동시에 하려면 같은 UIView에 제스처를 붙여야 함. 이건 SwiftUI Map → MKMapView(UIViewRepresentable) 교체를 의미하고, 다음 MVP의 핵심 작업이 됨.

## 마일스톤별 핵심 의사결정

### camera-restore
- UserDefaults 저장 — 카메라 위치 정도의 단순 값에는 SwiftData 불필요
- 백그라운드 전환 시 1번 저장 — 매 카메라 이동마다 저장하는 건 과도
- 복원 후 현재 위치 이동 안 함 — 사용자가 보던 곳을 유지, "내 위치" 버튼으로 수동 이동

### stroke-pipeline
- 항목 2(방향 감지) + 4(증분 계산)를 통합 — 같은 ViewModel 파이프라인을 건드리므로 분리하면 throwaway 작업 발생
- 4쌍 거리 비교 + reverse — 2쌍(시작점만 비교)으로는 prepend 역주행 발생
- 되돌리기 시 전체 재구축 — 연결 구간까지 정확히 빼기 어렵고, undo는 드물어 성능 영향 미미

### drawing-pan (보류)
- Phase 1 실패 → Phase 2 실패 → 리서치 결과 MKMapView 교체 필요
- 현 MVP 범위를 넘으므로 다음 MVP로 이관

## 남은 기술부채 (→ backlog)

- 그리기 중 지도 이동 → `docs/backlog.md` "SwiftUI Map → MKMapView 교체"
- 스로틀 에러 메시지 미표시 → `docs/backlog.md` "스로틀 에러 메시지 미표시"
- Pair4 테스트 커버리지 누락 (StrokeDirectionResolver prepend+reverse)
- isLoading 미리셋 수정 완료 (a1b62c2)

## 다음 MVP 방향

- **MKMapView 교체**가 핵심 — 그리기 중 지도 이동 + 향후 커스텀 제스처 확장의 기반
- 교체 시 MapPolyline/Marker/UserAnnotation → MKOverlay/MKAnnotation delegate 방식 전환
- 스로틀 에러 domain/code 실기기 확인 후 정확한 감지 적용
