# Trace 로드맵

워크플로의 **"현재 위치" 단일 출처.** MVP(우산) ↔ 마일스톤(superpowers 1사이클) 매핑과
진행 상태를 한 장으로 본다. frank의 `active_*.txt` 상태파일 묶음을 이 파일이 대체한다.

- 단위 정의·흐름 규칙: `docs/agent-rules/workflow.md`
- 아카이빙: `/trace-archive` (`docs/prompts/trace-archive.md`)
- 마일스톤 후보 풀: `docs/backlog.md`

상태 표기: `[ ]` 미착수 · `[~]` 진행 중 · `[x]` 완료

## 진행 중 / 예정

### MVP16 — 러닝/코스 UI 개편 (후보)   (상태: 킥오프 대기)

> MVP15 중 미리 다듬은 방향 스펙 2건을 재료로 킥오프에서 새 눈으로 검토 후 확정한다 —
> 항목 1: 탭/시트/페이지 구조 개편(커스텀 탭바 + 코스탭 커스텀 시트 + 러닝탭 나이키식 전체화면),
> 항목 2: 그리기 제스처 개편(한 손가락=지도 이동, 그리기=롱프레스-드래그). 사전 리뷰(2026-07-19)
> 보완점 반영됨(트래킹 중 탭바 동작·탭 구성 등 킥오프 의제). 백로그 "포인트 구간 지도 폴리라인
> 표시"의 편입 여부도 킥오프에서 결정. 시작 방식은 MVP12식 design-direction 전용 사이클 검토.
> 스펙: `docs/superpowers/specs/2026-07-18-run-ui-restructure-direction.md`

### MVP15 — 러닝 경험 보강   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp15/`](history/mvp15/))

> 코스 연동(다음 MVP) 전에 러닝 기둥의 기능·디테일을 보강했다 — 실사용 피드백 5건이 재료.
> 시작 카운트다운(3-2-1 발화, 백그라운드에도 계속), 종료 홀드 진행 링, 발화 문안 통일·속도
> 조정, 목표 거리·시간 직접 입력(단위 상시 표시·직전값 프리필), 달리면서 포인트 찍기(구간
> 거리 발화, 잠금화면 Live Activity 버튼, 이벤트 스트림 저장, 기록 상세 구간 표·마커·삭제).
> 러닝 탭 UI 구조 개편은 MVP16 후보로 백로그에 씨앗만. 회고: [`260719_mvp15_completion_retro`](history/mvp15/260719_mvp15_completion_retro.md)

- [x] **run-detail-polish** — 시작 카운트다운 + 종료 홀드 링 + 발화 문안·속도 정비 + 목표 직접 입력 (경량 사이클: 태스크별 리뷰만, subagent-driven-development로 Task 6개 전부 구현·리뷰 완료). 플랜: `history/mvp15/2026-07-17-run-detail-polish.md` · 실기기 QA 통과(2026-07-18): `history/mvp15/2026-07-18-run-detail-polish-device-checklist.md`, 후속 피드백(카운트다운 예열, 발화 속도 분리, 콜드 스타트 TTS 엔진 예열) 전부 반영 완료(커밋 50c5fd9, adfbf64)
- [x] **run-waypoints** — 포인트 찍기: 트래킹 버튼·즉시 발화, 잠금화면 버튼(무세션 가드), additive 스키마 확장, 기록 상세 표시·삭제 (표준 사이클: Task 8개 전부 구현·태스크별 리뷰 통과 + 최종 브랜치 리뷰(opus), 발견사항 4건 반영 후 Ready to merge: Yes, 커밋 d3f39c0). 플랜: `history/mvp15/2026-07-18-run-waypoints.md` · 실기기 QA 통과(2026-07-19): `history/mvp15/2026-07-18-run-waypoints-device-checklist.md`(포인트 삭제 병합·재번호 재확인 포함). 후속 피드백(지도 위 경로 표시)은 별도 스코프 필요해 `docs/backlog.md`로 이월

### MVP14 — 기본 러닝 경험 완성   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp14/`](history/mvp14/))

> 러닝 기둥을 "진짜 러닝앱" 수준으로 끌어올렸다 — 일시정지/재개(수동), km 스플릿(엔진 +
> 기록 상세, 과거 기록 소급), 러닝 오디오 안내(km 경계 = 거리·총시간·평균 페이스, 상태 전환
> 발화, 덕킹으로 음악 공존), 목표 설정(자유/거리/시간, 절반·달성 안내, 달성 후 트래킹 유지).
> 코스 연동(코스 골라 뛰기)은 다음 MVP. 사이클 3개: ①+②(표준, 각각 최종 브랜치 리뷰(opus))
> / ③(경량 — 열린 결정 없음, 태스크별 리뷰만). 세 사이클 모두 실기기 QA 통과 — 사이클
> 3부터는 GPX 시뮬레이션(Xcode Simulate Location)으로 실제로 뛰지 않고 QA를 진행하는
> 방식을 확립했다. 회고: [`260717_mvp14_completion_retro`](history/mvp14/260717_mvp14_completion_retro.md)

- [x] **run-pause-resume** — 수동 일시정지/재개: `RunSession` 상태 확장, 멈춘 시간 제외 계산, 트래킹 UI 버튼, 일시정지 구간 저장(additive), Live Activity 일시정지 표시. Task 7개 구현 완료(각 태스크 리뷰 통과 + 최종 브랜치 리뷰(opus)에서 요약 화면 평균 페이스 버그 발견·수정), 실기기 QA 통과(2026-07-16, 시나리오 1~6 전부 통과). 이월 확인(강제종료 잠금화면 정리·배터리 체감)은 `docs/backlog.md`로 재이월. 플랜: `history/mvp14/2026-07-15-run-pause-resume.md`
- [x] **run-splits-audio** — km 스플릿 엔진(Domain 순수 로직, 라이브·소급 공용) + 기록 상세 스플릿 표 + 음성 안내(TTS·덕킹·백그라운드 오디오, km 경계/상태 전환 발화). Task 7개 구현 완료(각 태스크 리뷰 통과 + 최종 브랜치 리뷰(opus) Ready to merge: Yes), 실기기 QA 진행 중 발견된 버그(기록 상세 "평균 페이스"와 "킬로미터별 페이스" 표의 시간 기준 불일치 — GPS 신호 대기 시간이 스플릿 계산에서 누락됨) 발견·수정(세션 활동 시간 기준으로 통일). 실기기 QA 통과(2026-07-17, 핵심 시나리오 1~5·7 전부 통과, 시나리오 6은 부분 확인). 이월 확인(연속 발화 안 겹침 재확인·강제종료 카드 정리는 통과했으나 배터리·GPS 정확도는 미확인)은 `docs/backlog.md`로 이월. 플랜: `history/mvp14/2026-07-16-run-splits-audio.md`
- [x] **run-goal** — 시작 모드 선택(자유/거리/시간) + 트래킹 중 진행률 + 목표 발화(절반/달성), 목표 정보 기록 저장. Task 7개 구현 완료(각 태스크 리뷰 sonnet 전부 Approved, Critical/Important 0건 — 경량 사이클 결정에 따라 최종 브랜치 리뷰는 생략). 실기기 QA는 GPX 파일(Xcode Simulate Location)로 진행 — 거리(3km)·시간(5분, 피커 최소값) 목표 각각 절반/달성 발화 각 1회, 달성 후에도 트래킹 계속(평소 km 안내로 복귀), 일시정지 시간 목표 판정 제외, 자유 러닝 회귀, 화면잠금+음악 덕킹, 트래킹 화면 진행률 UI, 기록 상세 목표 표시, 과거 기록 호환까지 9개 시나리오 전부 통과(2026-07-17, 사용자 실기기 확인). 플랜: `history/mvp14/2026-07-17-run-goal.md`

### MVP13 — 자유 러닝 트래킹 + 기록   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp13/`](history/mvp13/))

> Trace의 두 번째 기둥 "러닝(기록)"을 세운다 — 코스 탐색과 독립적으로, 일반 러닝앱처럼
> 그냥 뛰어도 시작→GPS 트래킹→종료 요약→기록 저장이 되는 기능. 탭 구조(코스/러닝) 도입.
> 측정은 GPS 열(경로·거리·시간·페이스·고도)만 — 심박 등 HealthKit/워치 연동은 이후 MVP.
> 코스 연동(코스 골라 뛰기 + 계획 vs 실제 비교)도 다음 MVP. 사이클 2개: ①+②(표준) / ③(경량,
> ① 실기기 QA 결과를 저장 스키마에 반영하기 위해 분리). 사이클 1(Task 10개 + 최종 브랜치
> 리뷰(opus))·사이클 2(Task 5개, 경량 — Task별 리뷰만) 모두 실기기 QA 통과. 전체 테스트
> 228개 그린. 회고: [`260715_mvp13_completion_retro`](history/mvp13/260715_mvp13_completion_retro.md)

- [x] **run-tracking** — 탭 구조 + 러닝 탭(대기→트래킹→종료 요약), 연속 GPS 스트림(백그라운드 포함), 필터링·파생값(거리·시간·페이스·고도) 실시간 계산. 저장 없음
- [x] **run-live-activity** — 잠금화면 Live Activity + Dynamic Island: 트래킹 중 거리·시간·페이스 실시간 표시 (Widget Extension 타깃 신설)
- [x] **run-record-save** — 기록 저장(SwiftData, 타임스탬프 샘플 스트림 스키마) + 기록 목록/상세, 실기기 QA 통과(2026-07-15)

### MVP12 — 달리기 기록 착수 전 기반 정비: Swift 6 + 디자인   (상태: ✅ 완료 · 아카이빙됨 → [`history/mvp12/`](history/mvp12/))

> 달리기 기록(차기 MVP)이 새 화면과 persistence 확장을 얹기 전에 기반을 정비했다.
> 코드는 Swift 6 언어 모드 전환(동시성 경고 ~40건 일괄 정리)으로, 외관은 기존 목업("Trace 경로
> 짜기 v2") 기반 디자인 시스템을 플래너 화면 전체(탑바·FAB·시트·구간리스트·핀/폴리라인·저장/목록/
> 왕복/redo)에 적용하는 것으로. design-apply 완료 선언(2026-07-12) 이후에도 실사용 중 바텀시트
> 버그(드래그-리사이즈 3단계 확장, 안전영역 피드백 루프로 상태바 가림, 헤더 베이스라인 정렬로
> 로딩 중 움찔거림, FAB 스택이 collapsed 시트에 가려지던 문제)가 연속 발견돼 같은 브랜치에서
> 추가 수정(2026-07-13). 전체 테스트 178개 그린, 실기기 QA 체크리스트 통과.
> 회고: [`260713_mvp12_completion_retro`](history/mvp12/260713_mvp12_completion_retro.md)

- [x] **design-direction** — 기존 목업 검토 → 디자인 시스템 추출 + 미커버 화면(코스 저장/목록·왕복·redo) 확장 설계. 노브 기본값·SF 네이티브 폰트·시스템 테마 연동(인앱 토글 제거) 확정(2026-07-10 인터뷰). 경량 사이클(문서 전용)
- [x] **swift6-migration** — 암묵 isolation 정리, 명시 @MainActor 감사, Sendable 정합, 동시성 문법 현대화, `SWIFT_VERSION = 6` 전환 + 경고 0. 실기기 크래시(MapKit NSObject 서브클래스 격리 오상속) 발견 후 격리 기본값 전략을 반대 방향(기본 nonisolated + 명시 @MainActor)으로 재전환
- [x] **design-apply** — 확정된 디자인 시스템을 플래너 화면 전체에 적용. 토큰·탑바·FAB·시트·구간리스트·핀/폴리라인·저장/목록/왕복/redo 재배치까지 P1 전 범위 적용 완료. P2 6건은 `docs/backlog.md`로 이연. 완료 선언 후에도 바텀시트 안전영역 피드백 루프·헤더 베이스라인 정렬(`HStack(alignment: .firstTextBaseline)` → `.top`)·FAB 스택 가림 버그를 추가로 수정(2026-07-13) — 상세: `docs/solutions/ui-bugs/`

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
