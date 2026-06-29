# MVP6 완료 회고 — 탭↔그리기 통합 + undo/clear 통합

작성일: 2026-06-29

---

## Keep (잘 된 것)

**CourseEditSession 단일 책임 분리**
ViewModel에 섞여 있던 경로 편집 상태(방향 판단, gap 라우팅, 세그먼트 병합)를 Application 레이어 `CourseEditSession`으로 분리한 것이 핵심 성과다. `attach()` 1호출 = 1 undo 단위라는 계약이 명확해지면서 dangling gap 시나리오가 구조적으로 제거됐다.

**QA 버그를 코드 분석으로 정확히 예측**
실기기 QA에서 보고된 두 버그(pendingTapStart 핀 미표시, draw 방향 오표시)의 근본 원인을 코드 레벨에서 완전히 파악한 뒤 수정했다. 사용자가 이미지를 보여주지 않아도 됐다.

**SDD ledger 활용**
컨텍스트 압축이 발생해도 `.git/sdd/progress.md`로 작업 위치를 즉시 복원했다. 컨텍스트 소실로 인한 작업 중복이 없었다.

---

## Problem (아쉬운 것)

**draw 방향 감지 설계 누락**
설계 단계에서 "첫 스트로크에서 `accumulatedCoordinates`가 비어 있다"는 케이스를 명시적으로 다루지 않았다. `StrokeDirectionResolver`에 nil을 전달하면 `.initial`만 반환되는 동작이 있었음에도 `incrementalRoute`의 호출부에서 이를 처리하지 않았다. QA 단계에서 발견됐다.

**`course` computed의 표시 순서 미연결**
방향 감지(`strokeEntries.first?.direction`)를 `course` computed의 prepend/append 순서에 연결하는 로직이 초기 구현에서 누락됐다. 방향을 올바르게 감지해도 화면에 반영되지 않는 불일치였다.

**메모리 룰 위반 (실행 방식 재질문)**
`feedback-default-execution-subagent.md`가 있음에도 계획 완료 후 실행 방식을 다시 물어봤다. writing-plans 스킬 템플릿의 "실행 방식 선택" 단계를 메모리 우선으로 재점검해야 했다.

---

## Surprise (예상 밖)

**Xcode 26 PBXFileSystemSynchronizedRootGroup**
`Application/CoursePlanning/CourseEditSession.swift` 신규 파일을 디스크에 추가하자 `project.pbxproj` 수정 없이 자동으로 빌드에 포함됐다. Xcode 26의 파일 시스템 동기화 그룹 기능으로, 이전 MVP 경험과 달라 처음엔 당황했으나 이점이 컸다.

**SourceKit 인덱싱 지연**
파일을 추가하거나 수정할 때마다 SourceKit이 "Cannot find type X in scope" 오류를 반복 표시했다. 실제 빌드 오류가 아니라 IDE 인덱싱 지연임을 `xcodebuild test`로 확인해야 했다. 진단 도구를 신뢰하지 말고 빌드 결과를 신뢰해야 한다는 원칙을 재확인했다.

---

## 마일스톤별 핵심 의사결정

| 마일스톤 | 결정 | 이유 |
|---|---|---|
| course-edit-session | gap + 새 세그먼트를 하나의 merged entry로 저장 | dangling gap 제거, undo 1회 = 완전한 사용자 액션 단위 보장 |
| course-edit-session | `accumulatedCoordinates`는 draw 진입 시 빈 배열로 시작 | 씨드 초기화 방식이 prepend 케이스에서 `dropFirst()` 슬라이싱을 깨뜨렸던 MVP5 교훈 |
| QA fix | pendingTapStart를 `else if` 밖으로 분리 | course 존재 여부와 핀 표시를 독립적으로 제어 |
| QA fix | 첫 스트로크에서 session 끝점을 context로 전달 | accumulated가 빈 배열일 때 방향 감지 불가 문제 해결 |

---

## 남은 기술부채

- **`reversed()` 케이스타입 보존 테스트 없음** — tapped.reversed() → tapped, drawn.reversed() → drawn 검증 미비 (`backlog.md` 추가 검토 필요)
- **`errorMessage = errorMessage` no-op** — `toggleDrawingMode` draw→tap 분기의 self-assignment (기능적 영향 없음)
- **`appendStroke` 모드 가드 없음** — draw 모드가 아닐 때 호출 시 방어 코드 없음
- **prepend + gap 통합 테스트 없음** — session 시작점에 붙이는 경로에 gap이 포함된 케이스
- **핀치 줌 UX** — 그리기 모드 2손가락 핀치가 내장 MKMapView보다 부자연스러움 (MVP4부터 이어진 open 항목)

---

## 다음 MVP 방향

- **실기기 QA 회고 반영** — 이번 QA에서 발견된 draw 방향 오표시 유형은 "설계에서 nil 케이스 명시" 원칙으로 예방 가능. 스펙 작성 시 빈 배열/nil 경계 케이스를 명시적으로 기술하는 관행 추가.
- **핀치 줌 UX** — 백로그 open 항목. 내장 MKMapView 핀치 복원 또는 대안 탐색.
- **코스 저장/불러오기** — 계획한 코스를 저장하고 다시 열어 편집하는 기능.
