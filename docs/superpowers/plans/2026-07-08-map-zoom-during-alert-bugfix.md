# 지도 줌아웃 버그 — 저장 알럿 텍스트 입력 중 (인수인계)

> **다음 세션 시작점.** `/trace-init`으로 이 문서가 잡히면, Task 1부터 이어서 진행한다.
> 이전 세션에서 4차례 수정 시도가 전부 증상 패치에 그쳐, 사용자 판단으로 세션을 리셋했다
> (근거: `docs/solutions/workflow-issues/session-reset-after-repeated-fix-failures.md`).
> **워킹 트리는 이 조사 이전 상태로 완전히 되돌려져 있다(2026-07-08) — 이전 시도의 코드는 남아있지 않다.**

## 증상

`docs/qa/2026-07-07-course-save-roundtrip-device-checklist.md` 시나리오 3(저장 이름 입력) 실기기 QA에서 발견.
코스 저장 알럿(`CoursePlannerPage.swift`의 `isSavePromptPresented`)에서 이름 `TextField`에 텍스트를 입력하는 동안
지도가 순간적으로 줌아웃되고, 알럿이 저장/취소로 닫히면 원래 줌 레벨로 복원된다.

## 확정된 근본 메커니즘 (실기기 로그로 확인 완료 — 재조사 불필요)

알럿의 `TextField`가 포커스를 받아 키보드가 뜨면
→ `MapViewRepresentable`이 감싸는 `MKMapView`의 프레임(`bounds`)이 일시적으로 리사이즈됨
  (실측 로그: bounds size 572.67 ↔ 298.67 등, `updateUIView` 호출 시점마다 다름)
→ MapKit이 새 프레임에 맞춰 `region`(특히 `span`)을 **자체적으로 재계산**
→ 그 값이 `mapViewDidChangeVisibleRegion` 델리게이트를 통해 SwiftUI `@Binding var region`에
  그대로 반영되어 줌 레벨이 사라짐.

이 인과관계 자체는 확정됐다. **미해결인 것은 "왜 알럿의 키보드가 지도 뷰의 bounds를 리사이즈하는가"** — 이 질문은
시도 1 이후 한 번도 다시 조사되지 않았다.

## 막다른 시도 4회 (전부 되돌려짐 — 그대로 재시도 금지)

모두 `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` / `CoursePlannerPage.swift`에 대한 변경이었다.

1. **`.ignoresSafeArea(.keyboard, edges: .all)` 추가** — 사용자 확인 결과 "여전히 똑같이 버그가 발생해"로 실패.
   ⚠️ **이 시도는 제대로 검증되지 않았을 수 있다** — 어느 뷰 계층에 적용했는지, 그리고 그 결과 `bounds` 리사이즈
   자체가 실제로 안 막혔는지를 로그로 확인하지 않은 채 되돌려졌다. Task 1은 이 시도를 로그와 함께 다시 하는 것이다.
2. **bounds 리사이즈 감지 시 즉시(동기) `setRegion`으로 원래 region 복원** — 근본 메커니즘을 로그로 확정하는 데는
   성공했으나, `updateUIView` 안에서 동기로 `setRegion`을 호출한 결과 `mapViewDidChangeVisibleRegion`이 같은
   뷰 업데이트 사이클 안에서 동기로 재호출되어 **"Modifying state during view update, this will cause undefined
   behavior."** 경고를 유발함.
3. **`mapViewDidChangeVisibleRegion`의 상태 갱신을 `DispatchQueue.main.async`로 다음 런루프에 지연** — 경고는
   사라졌지만, "저장 버튼을 눌러도 지도가 복원되지 않고 줌아웃된 채 남음"이라는 **회귀**가 발생함.
4. **`suppressRegionWriteback` 플래그(알럿 표시 중 writeback 차단) + bounds-반응 `setRegion`도 async 지연** —
   경고 소멸 유지 + 복원 동작(저장 버튼 누르면 원래대로) 회복. 그러나 **타이핑 중 줌아웃 자체는 미해결로 남음.**

### 왜 이 4개를 전부 실패로 봐야 하는가

전부 "지도 프레임이 리사이즈된 **이후** 그 값을 SwiftUI 상태에 어떻게 반영할지"(막기/지연/보정)에 대한
반응이었다. 되짚어보면 시도 3의 async 지연조차 근본 수정이 아니라, 시도 2 자신이 만든 부작용(동기
`setRegion` 호출)을 수습한 것이었다 — 패치가 패치를 낳는 패턴. **왜 프레임 자체가 리사이즈되는지**를
막는 시도는 시도 1 한 번뿐이었고, 그마저 제대로 검증되지 않았다.

## 다음 세션이 할 일

- [ ] **Task 1: bounds 리사이즈 자체를 막을 수 있는지 로그로 처음부터 재검증한다.**
  `docs/solutions/workflow-issues/live-only-bug-temp-print-debugging.md` 컨벤션을 따른다 — `MapViewRepresentable.updateUIView`
  진입 시 `uiView.bounds`를 임시 `print()`로 찍고, 알럿을 띄우기 전/텍스트 입력 중/알럿 닫은 후 세 시점을 실기기에서
  비교한다. `.ignoresSafeArea(.keyboard, edges: .all)`를 body 최상위(예: `CoursePlannerPage.body` 전체, `mapView`가
  아니라)에 적용한 뒤 같은 로그로 재검증한다. bounds가 그래도 바뀐다면 SwiftUI의 자동 keyboard-avoidance가 원인이
  아니라는 뜻이므로 Task 2로 넘어간다.
- [ ] **Task 2: (Task 1에서 레이아웃 층위로 못 막는 것이 확인되면) 구조적 대안을 사용자와 상의한다.**
  가설: `.alert(...) { TextField(...) }`는 내부적으로 `UIAlertController`를 띄우는데, 이게 SwiftUI의
  keyboard-avoidance 경로 밖에서 시스템 레벨로 프레젠팅 뷰의 레이아웃에 영향을 줄 수 있다. 이 경우 저장 이름
  입력을 시스템 `.alert` 대신 커스텀 `.sheet` + `TextField`로 바꾸는 것도 옵션이다 — 이건 다운스트림 패치가
  아니라 UI 컴포넌트를 바꾸는 결정이므로, 근거(로그)를 들고 먼저 사용자에게 제안하고 승인받은 뒤 진행한다.
- [ ] **Task 3: 수정 후 실기기에서 세 가지를 모두 확인한다.**
  ① 텍스트 입력 중에도 줌 레벨 유지 ② 저장/취소로 알럿 닫을 때 상태 이상 없음(애초에 안 바뀌었으니 "복원"이랄
  것도 없어야 정상) ③ Xcode 콘솔에 "Modifying state during view update" 경고 없음.
- [ ] **Task 4: 임시 print 전부 제거 확인.**
  `git diff --stat`으로 조사용 코드가 하나도 안 남았는지 확인 후 실제 수정 커밋.

## 금지 사항

`suppressRegionWriteback` 플래그, bounds-반응 `setRegion` 보정 — 둘 다 이미 시도되어 **증상만 가리고 근본
원인(bounds가 왜 리사이즈되는가)은 안 건드리는 것으로 확인됨.** 재도입하지 말 것. 새 수정이 이 두 메커니즘과
비슷한 모양(리사이즈 이후 반응)이 되려 한다면, Task 1로 돌아가 레이아웃 층위를 다시 의심할 것.

## 관련 파일

- `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`
- `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- QA 체크리스트: `docs/qa/2026-07-07-course-save-roundtrip-device-checklist.md` (시나리오 3)
- 디버깅 컨벤션: `docs/solutions/workflow-issues/live-only-bug-temp-print-debugging.md`
- 세션 리셋 판단 근거: `docs/solutions/workflow-issues/session-reset-after-repeated-fix-failures.md`
