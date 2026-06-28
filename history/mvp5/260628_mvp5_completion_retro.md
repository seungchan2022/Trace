# MVP5 완료 회고 (2026-06-28)

## Keep (잘 된 것)

- **세그먼트 모델 설계가 깔끔했다.** `CourseSegment` 열거형 하나로 탭/그리기 구분을 흡수하고, `PlannedCourse`가 segments 배열을 좌표·거리 computed property로 투명하게 노출한 구조가 ViewModel 복잡도를 줄였다.
- **history 기반 상태 기계.** tap→draw 시 현재 세션 leg를 history에 봉인하고, draw→tap 시 누적 좌표를 drawn 세그먼트로 봉인하는 패턴이 직관적이고 undo/clear까지 자연스럽게 확장됐다.
- **실기기 QA가 추가 버그를 잡았다.** 시뮬레이터로 발견하지 못한 핀 역전 버그, 라벨 UX 오류를 실기기에서 확인해 수정 완료했다.
- **`preDrawTapState` 패턴.** 그리기 진입 전 탭 상태를 저장해 아무것도 안 그리고 복귀할 때 원상복원하는 방어 로직이 실기기 QA에서 검증됐다.

## Problem (아쉬운 것)

- **라벨 UX 방향성을 처음부터 잘못 잡았다.** "전환 대상"을 표시하는 토글 라벨 패턴을 선택했다가 사용자 지적 후 "현재 상태" 표시로 수정했다. UX 결정은 먼저 묻거나 원칙을 확인하고 진행했어야 한다.
- **핀 소스 이중화 문제가 설계 단계에서 예견되지 않았다.** 탭 모드는 `startCoordinate`, 그리기 모드는 `course.coordinates`를 쓰는 모드별 분기가 자연스럽게 생겼다가 실기기 버그의 원인이 됐다. 처음부터 "핀은 항상 course에서 파생"으로 설계했어야 했다.
- **iOS 시뮬레이터 버전 이슈가 여전히 열려 있다.** iOS 18.x 런타임 크래시는 문서화로 처리했지만 iOS 17 근처에서 테스트하는 전략은 미결이다.

## Surprise (예상 못했던 것)

- **`accumulatedCoordinates.last`를 `startCoordinate`로 쓰는 버그.** draw→tap 복귀 시 경로 끝점을 출발점으로 저장했는데, prepend 케이스에서 B(도착)가 출발로 표시되는 버그가 나왔다. "핀은 course에서 파생"으로 통일하면서 해결됐다.
- **`XCTAssertEqual(Optional<Double>, accuracy:)` 컴파일 에러.** `XCTUnwrap`으로 언래핑 후 사용해야 한다는 것을 테스트 작성 중에 발견했다.

## 기술부채

- **핀치 줌 UX.** 커스텀 UIPinchGestureRecognizer가 내장 MKMapView 핀치보다 부자연스럽다 (MVP4에서 이월, backlog 유지).
- **iOS 17 근처 런타임 테스트.** iOS 26.5 우회 중 — 배포 전 멀티버전 전략 결정 필요.
