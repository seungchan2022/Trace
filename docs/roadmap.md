# Trace 로드맵

워크플로의 **"현재 위치" 단일 출처.** MVP(우산) ↔ 마일스톤(superpowers 1사이클) 매핑과
진행 상태를 한 장으로 본다. frank의 `active_*.txt` 상태파일 묶음을 이 파일이 대체한다.

- 단위 정의·흐름 규칙: `docs/agent-rules/workflow.md`
- 아카이빙: `/trace-archive` (`docs/prompts/trace-archive.md`)
- 마일스톤 후보 풀: `docs/backlog.md`

상태 표기: `[ ]` 미착수 · `[~]` 진행 중 · `[x]` 완료

## 진행 중 / 예정

### MVP12 — 달리기 기록 착수 전 기반 정비: Swift 6 + 디자인   (상태: 진행 중 · 킥오프 2026-07-10)

> 달리기 기록(차기 MVP)이 새 화면과 persistence 확장을 얹기 전에 기반을 정비한다.
> 코드는 Swift 6 언어 모드 전환(동시성 경고 ~40건 일괄 정리, `docs/backlog.md` 2026-07-08 항목)으로,
> 외관은 기능 프로토타입 상태인 "러닝 전" 화면 전체에 디자인 시스템을 입히는 것으로.
> 디자인은 사용자가 Claude Design으로 만든 기존 목업("Trace 경로 짜기 v2", 다크=Cyber/라이트=Glass
> 하이브리드)을 기반으로 하고, 코드 적용은 Swift 6 사이클 완료 후에 진행한다 —
> 새 디자인 코드가 처음부터 Swift 6 모드에서 작성되게.

- [x] **design-direction** — 기존 목업("Trace 경로 짜기 v2") 검토 → 디자인 시스템 추출 + 미커버 화면(코스 저장/목록·왕복·redo) 확장 설계. 노브 기본값·SF 네이티브 폰트·시스템 테마 연동(인앱 토글 제거) 확정(2026-07-10 인터뷰). 경량 사이클(문서 전용), 스펙: `docs/superpowers/specs/2026-07-10-design-direction-design.md`
- [ ] **swift6-migration** — 암묵 isolation 정리, 명시 @MainActor 감사, Sendable 정합, 동시성 문법 현대화, `SWIFT_VERSION = 6` 전환 + 경고 0 (사이클 1)
- [ ] **design-apply** — 확정된 디자인 시스템을 플래너 화면·구간 패널·저장/목록 sheet에 적용 + UX 보류 항목(구간 패널 prepend 스크롤 등) 재검토 (사이클 2)

### MVP11 — 코스 저장 + 구간 왕복   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp11/`](history/mvp11/))

> 완성한 코스에 이름을 붙여 저장·목록·불러오기·삭제(SwiftData, 미래 "코스 골라서 달리기"의 기반)하고,
> 구간 패널에서 구간 왕복(역방향만 붙여 정확히 2× — 실기기 QA에서 3× 버그 발견 후 재설계)과 전체
> 왕복을 추가했다. 초안 자동 저장·복원은 도입 후 실사용 판정으로 제거(완전 종료 시 빈 상태 시작).
> 저장 알럿 줌아웃 버그는 4회 증상 패치 실패 → 세션 리셋 → 인수인계 문서 → 근본 수정(keyboard
> avoidance, `.ignoresSafeArea(.keyboard)`)의 전 과정을 거침 — 인수인계 문서가 작동한 첫 사례.
> 실기기 QA 전 시나리오 통과(2026-07-08). 부수 발견(SwiftData affinity)은 즉시 수정, Swift 6
> 동시성 리팩토링은 `docs/backlog.md`로.
> 회고: [`260708_mvp11_completion_retro`](history/mvp11/260708_mvp11_completion_retro.md)

- [x] **course-save** — 이름 저장/목록 sheet/불러오기/삭제, `CourseRepositoryProtocol` + SwiftData 어댑터 (초안 자동 저장은 2026-07-08 제거)
- [x] **roundtrip-insert** — 구간 패널 왕복 버튼: 자유 끝 구간에서 역방향만 붙여 정확히 2배 거리(2026-07-08 버그 수정) + 전체 왕복 버튼 추가
- [x] **map-zoom-during-alert-bugfix** — 저장 알럿 텍스트 입력 중 지도 줌아웃 버그 해결: SwiftUI keyboard avoidance의 프레임 축소가 근본 원인, `.ignoresSafeArea(.keyboard)` body 최상위 적용(2026-07-08, 실기기 확인). 상세: `history/mvp11/2026-07-08-map-zoom-during-alert-bugfix.md` · 교훈: `docs/solutions/design-patterns/swiftui-keyboard-avoidance-shrinks-representable.md`

### MVP10 — 제스처 정합성 (탭 보류 확정·픽셀 판정·2손가락 튜닝·attach 방향 판정 재설계)   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp10/`](history/mvp10/))

> 탭/그리기 제스처가 iOS 관례대로 섞이지 않게 한다: 탭 즉시 확정을 "0.3초 보류 → 확정/취소"로
> 교체해 더블탭·원핑거 줌과 분리하고, 그리기 시작점 근접 판정을 화면 픽셀 기준으로 바꾸고,
> 그리기 모드 두손가락 제스처 경쟁을 튜닝한다. 실기기 QA에서 발견된 attach 방향 판정 버그(근접·
> 원거리 양쪽 모두 스트로크 끝점을 무시하던 근본 원인)까지 4번째 마일스톤으로 편입해 해결.
> 실기기 QA 전체 재검증 완료(2026-07-06).
> 회고: [`260706_mvp10_completion_retro`](history/mvp10/260706_mvp10_completion_retro.md)

- [x] **tap-pending-commit** — 탭 보류 확정(판별기 도입, 더블탭/원핑거 줌 시 취소, 임시 마커), 자체 디바운스 대체
- [x] **draw-start-pixel-snap** — 그리기 시작점 근접 판정을 실거리 20m → 화면 24pt 기준으로 교체
- [x] **two-finger-gesture-tuning** — 두손가락 탭줌아웃 ↔ 커스텀 두손가락 팬 경쟁 delegate 조정 + 실기기 튜닝
- [x] **attach-nearest-fallback** — 그리기 방향 무관 attach 판정 재설계: 근접 판정에 한해 끝점 대칭 처리 추가, 원거리(규칙 4)도 스트로크 양끝 중 더 가까운 쪽(anchor) 기준 단일 상대 비교로 확장. 스펙: `history/mvp10/2026-07-05-attach-nearest-fallback-design.md` · 플랜: `history/mvp10/2026-07-05-attach-nearest-fallback.md`

### MVP9 — 편집 정합성 (왕복·핀·redo)   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp9/`](history/mvp9/))

> 이어붙이기 규칙을 "새 구간 시작점 기준 + 그린 방향 존중"으로 교체해 왕복 모호성을 원천 제거하고,
> 탭 왕복(끝점 근접 탭), 닫힌 코스 병합 핀, 경유점 마커, redo(앞으로 돌리기)로
> 코스 편집 경험의 정합성을 마무리한다. 코스 저장(다음 MVP 후보)의 데이터 모델 리스크도 함께 줄인다.
> 회고: [`260704_mvp9_completion_retro`](history/mvp9/260704_mvp9_completion_retro.md)

- [x] **edit-consistency** — attach 시작점 규칙 교체(자동 방향 감지 제거), 끝점 근접 탭 왕복, 닫힌 코스 병합 핀, 경유점 마커, redo

### MVP8 — 코스 편집·가독성 UX 마무리   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp8/`](history/mvp8/))

> 지도 위 경로 표현과 편집 조작을 마무리한다: 구간 패널 스크롤 제한, 핀치 줌 네이티브 복원,
> 겹치는 경로 좌표 오프셋 렌더링. 이후 기능(코스 저장 등)이 독립적으로 붙을 기반.
> 실기기 QA(2026-07-03) 완료: 구간 패널 스크롤 인디케이터 패딩 버그 수정,
> 겹침 오프셋은 실기기 디버그 로그로 정상 동작 확인. 발견된 부수 이슈(탭 모드 왕복 불가,
> 왕복 시 출발/도착 핀 라벨 혼동 등)는 `docs/backlog.md`로 이관.
> 회고: [`260703_mvp8_completion_retro`](history/mvp8/260703_mvp8_completion_retro.md)

- [x] **course-ux-polish** — 구간 패널 최대 높이(화면 ~40%) + 초과 시 스크롤 + 최신 구간 자동 스크롤, 그리기 모드 핀치 줌 네이티브 복원(커스텀 pinchGR 삭제)
- [x] **overlap-offset** — 겹침 구간 감지(점별 거리 비교) + 진행 방향 수직 좌표 오프셋(~4m) 표시 전용 렌더링

### MVP7 — 코스 편집 UX 개선   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp7/`](history/mvp7/))

> 탭 자동 연결(A) + 그리기 스트로크=세그먼트(A-2) + 지도 위 구간 색상·거리 라벨(B) + 실시간 구간 패널(E)을 구현하고, 실기기 QA에서 나온 버그 3건(undo/prepend 색상 안정성, 도착 마커 미표시, 위치 버튼 오작동)도 같은 브랜치에서 수정한다.

- [x] **course-edit-ux-panel** — 탭 자동 연결, 그리기 스트로크=세그먼트 통일, 세그먼트 색상+거리 라벨, 실시간 구간 패널, QA 버그 3건(undo/prepend, 도착 마커, 위치 버튼) 수정

### MVP6 — 탭↔그리기 통합 + undo/clear 통합   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp6/`](history/mvp6/))

> CourseEditSession Application 레이어 도입으로 탭 경로 누적, 탭↔그리기 자동 이어붙이기, 모드 무관 undo/clear를 올바르게 구현한다.

- [x] **course-edit-session** — CourseEditSession Application 오케스트레이터, ViewModel 전면 교체, View undo 통합, QA 버그 2건 수정

## MVP 목록

### MVP5 — 경로 이어붙이기 + 조작 개선   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp5/`](history/mvp5/))

> 탭↔그리기 양방향 경로 이어붙이기(세그먼트 모델), 그리기 모드 2손가락 UX 보완, iOS 18 Observable 크래시 원인 규명 + 문서화, 실기기 QA 후 핀·라벨 UX 버그 수정.
> 회고: [`260628_mvp5_completion_retro`](history/mvp5/260628_mvp5_completion_retro.md)

- [x] **path-stitching** — CourseSegment 세그먼트 모델, history 기반 탭↔그리기 경로 이어붙이기, undo/clear history 반영
- [x] **two-finger-pan-ux** — 2손가락 pan 부호 수정, pitch/rotate 비활성화, 그리기 오염(멀티터치 가드) 수정
- [x] **test-ios-versions** — iOS 18 `@Observable` malloc 크래시 원인 규명 + `docs/solutions/` 문서화
- [x] **pin-label-ux** — 실기기 QA 후 핀 소스 통일(course 기준), 라벨 현재 상태 표시, draw→tap 핀 버그 수정

### MVP4 — MKMapView 마이그레이션 + 드로우 정밀도   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp4/`](history/mvp4/))

> MVP3 보류 항목(2손가락 지도 이동) 해결: SwiftUI Map → MKMapView(UIViewRepresentable) 교체.
> DrawnPathSampler 루프 경로 버그(누적거리 기반)도 함께 수정.
> 회고: [`260627_mvp4_completion_retro`](history/mvp4/260627_mvp4_completion_retro.md)

- [x] **mkmap-migration** — SwiftUI Map → MKMapView 마이그레이션, 드로우/탭/2손가락 제스처
- [x] **drawing-precision** — DrawnPathSampler 누적거리 기반 교체, 스로틀 감지 확인

### MVP3 — UX 개선 + 스로틀 강화   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp3/`](history/mvp3/))

> MVP2 실기기 피드백 반영: 카메라 점프 제거, 비연속 구간 방향 감지, 증분 라우팅, 스로틀 에러 안내.
> 그리기 중 지도 이동(2손가락)은 SwiftUI Map 제스처 한계로 보류 → MKMapView 교체와 함께 다음 MVP.
> 회고: [`260625_mvp3_completion_retro`](history/mvp3/260625_mvp3_completion_retro.md)

- [x] **camera-restore** — UserDefaults 카메라 저장/복원, 서울시청 초기값, 백그라운드 저장
- [x] **stroke-pipeline** — 자동 방향 감지(4쌍 비교 + reverse) + 증분 계산(새 구간만 라우팅) + 스로틀 감지/안내
- [ ] ~~**drawing-pan**~~ — 보류: SwiftUI Map 위 오버레이 제스처 전달 불가, MKMapView 교체 필요

### MVP2 — UX 개선 + 스로틀 완화   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp2/`](history/mvp2/))

> MVP1 실기기 피드백 반영: 상호작용 모델 정리, 위치 UX, 모드 표시, 스로틀 완화.
> 회고: [`260623_mvp2_completion_retro`](history/mvp2/260623_mvp2_completion_retro.md)

- [x] **ux-polish** — 단일 모드 전환, 위치 시작 화면, 권한 알럿, 모드 표시, 코스 핀
- [x] **throttle-mitigation** — 구간 캐시 + 디바운스

### MVP1 — 러닝 코스 계획   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp1/`](history/mvp1/))

> 지도에서 코스를 계획하고 거리를 재는 핵심 경험.
> 회고: [`260622_mvp1_completion_retro`](history/mvp1/260622_mvp1_completion_retro.md)

- [x] **route-planner** — 지도 화면 세팅 + 두 포인트 사이 거리재기 (+ folder-restructure 구조 정리)
- [x] **marker-draw-snap** — 그리기로 경로를 그리고 거리 표시 + 마커

<!-- 이후 MVP는 킥오프 시 아래에 추가. 형식:
### MVP2 — <이름>   (상태: 킥오프 | 진행 중 | 완료)
> <한 줄 가치>
- [ ] <마일스톤 슬러그> — <설명>
-->
