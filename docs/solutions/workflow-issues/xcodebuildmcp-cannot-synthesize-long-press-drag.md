---
title: "XcodeBuildMCP는 홀드 후 이동(롱프레스-드래그) 제스처를 합성하지 못한다"
date: 2026-07-21
category: workflow-issues
module: QA workflow / Gesture verification
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - "그리기 제스처처럼 '누른 채 일정 시간 유지한 뒤 이동'하는 UIKit 제스처(UILongPressGestureRecognizer + 이동)의 동작 자체를 시뮬레이터 UI 자동화로 검증하려 할 때"
  - "XcodeBuildMCP의 drag/swipe/touch/long_press 툴로 '터치다운 유지 → 임계값 경과 후 이동'을 하나의 연속 터치로 합성하려 시도할 때"
tags: [xcodebuildmcp, simulator, ui-automation, long-press, gesture, touch-synthesis, real-device-qa, computer-use, macos-permissions]
---

# XcodeBuildMCP는 홀드 후 이동(롱프레스-드래그) 제스처를 합성하지 못한다

## Context

MVP16 draw-gesture 마일스톤(`history/mvp16/2026-07-21-draw-gesture.md` Task 3)에서
그리기 모드를 즉시 인식 팬에서 롱프레스-드래그(`UILongPressGestureRecognizer`, 0.25초 홀드 +
드래그)로 교체한 뒤, 이 핵심 동작 자체가 시뮬레이터에서 실제로 동작하는지 XcodeBuildMCP UI
자동화로 검증하려 했다. 네 개 프리미티브(`drag`, `swipe`, `touch`, `long_press`)를 모두
시도했지만 어느 것도 "터치다운을 유지한 채 임계값 경과 후 이동"을 합성하지 못했다.

## Guidance

1. **`drag` 툴은 이 환경에서 즉시 도구 오류로 실패한다**: `FBSimulatorHIDEvent does not
   support touch move events.` `preDelay` 파라미터를 줘도(0.25초 임계값보다 크게, 예: 0.5초)
   결과는 동일하다 — 제스처가 지도에 전혀 도달하지 못하는 단계에서 실패하므로, `preDelay`가
   "다운 후 대기"인지조차 판별할 수 없다.
2. **`swipe` 툴은 오류 없이 실행되지만, `preDelay`가 "터치다운 후 대기"로 동작하지 않는
   것으로 보인다.** `preDelay: 0.5`(임계값 0.25초보다 크게)를 줘도 매번 지도만 패닝되고
   선은 그려지지 않았다 — `preDelay`가 "제스처 시작 전 대기"(다운 이벤트 자체가 지연되고,
   다운과 동시에 이동이 시작됨)로 동작하는 것으로 추정된다. 이러면 롱프레스 인식기가 다운
   이벤트 이후 실제로 그만큼 붙들려 있을 기회를 얻지 못한다.
3. **`touch`(down/up만, 이동 없음)와 `long_press`(눌렀다 뗌, 이동 없음)는 애초에 "누른 채
   이동"이라는 이동 자체를 지원하지 않는다.**
4. **결론: 이 네 프리미티브 중 어느 조합으로도 "터치다운 유지 → 임계값 경과 후 이동"을
   합성할 수 없다.** 억지로 조합을 반복 시도하며 루프를 돌지 말고(anti-loop), 각 가설을
   1회씩만 검증한 뒤 "시뮬레이터 합성 불가"로 결과를 정직하게 기록하고 실기기 QA로 이관한다.
   시뮬레이터로 확실히 검증 가능한 인접 동작(예: 이 사이클의 "한 손가락 = 항상 지도 이동")은
   분리해서 별도로 검증하고, 이건 실제 구현 성공/실패를 가리는 진짜 스모크로 취급한다.

## 다른 경로: computer-use MCP (2026-08-07, 검증 진행 중)

computer-use MCP는 macOS 마우스 이벤트를 시뮬레이터 **창**에 직접 보내므로 위에서 막힌
`FBSimulatorHIDEvent`를 거치지 않고, `left_mouse_down` · `mouse_move` · `left_mouse_up`을
따로 부를 수 있어 구조상 "누른 채 이동"이 만들어진다. **제스처가 실제로 인식되는지는 아직
결론이 나지 않았다** — 아래는 거기에 도달하기까지의 권한 절차이고, 이것만으로도 한 세션이
통째로 날아간 적이 있다.

### 권한 함정 — 이것 때문에 두 세션이 막혔다

1. **대상은 `~/.local/share/claude/ClaudeCode.app`이다.** Anthropic 데스크톱 앱 「Claude」가
   아니다. 실행 바이너리는 시스템 설정에 `+`로 추가되지 않으니 `.app` 번들을 추가한다.
2. **손쉬운 사용과 화면 기록이 둘 다 필요하고, 하나만 켜면 증상이 엉뚱한 곳에서 나온다.**
   `request_access`는 화면 기록을 먼저 검사한다. 화면 기록만 켜면 `request_access`는 통과하고,
   정작 `left_mouse_down`이 손쉬운 사용 부족으로 거부된다. **이 거부를 "tier 제한이라 구조적으로
   불가"로 읽으면 안 된다** — 오류 문구가 tier(`click`/`read`)를 **명시할 때만** 구조적 한계다.
   권한 실패나 권한 패널이 뜨는 것은 결론이 아니라 고치고 다시 하라는 뜻이고, anti-loop 시도
   횟수에도 넣지 않는다.
3. **권한은 프로세스가 시작하는 순간에 잡힌다.** 실행 중에 켜면 그 프로세스는 계속 "없음"으로
   안다. **창만 닫았다 여는 것으로는 안 된다**(백그라운드 잡 프로세스가 살아남는다). `Cmd+Q`로
   완전히 종료한 뒤 다시 켠다. 확인법: `ps -p $PPID -o lstart=`가 권한을 켠 시각보다 뒤여야 한다.
   2026-08-06 세션은 12시간 전에 뜬 프로세스라 권한을 켠 뒤에도 `request_access`가 계속 실패했다.
4. **버전이 올라가면 재발한다 — 실제로 재발했다.** 2.1.223(2026-08-07)에서 화면 기록 권한이
   다시 "없음"이 됐다. `ClaudeCode.app/Contents/MacOS/claude`는 `versions/2.1.223`과 **같은
   inode를 가리키는 하드링크**라, `.app` 번들을 등록하는 것과 버전 바이너리를 등록하는 것은
   같은 파일이다. 목록에 남은 `2.1.215` 같은 버전 번호 항목은 옛 흔적이므로 지우고 `.app` 번들
   하나만 남긴다.

### 검증에 들어갈 때

- `request_access`가 성공하면 **응답에 적힌 tier를 그대로 읽어 기록한다.** Simulator가 개발
  도구 범주라 "click" tier로 잡힐 가능성이 있는데, 범주에서 추론하지 말고 응답을 본다.
- `computer_batch`는 **각 액션 직전에** 최전면 앱을 검사한다. 배치 전에 조건 없이
  `open_application("Simulator")`을 부른다 — 중간에 다른 앱이 포커스를 뺏으면 배치가 도중에
  멈춰 판정 불가능한 부분 결과가 남는다.

## Why This Matters

롱프레스-드래그류 제스처는 UIKit 제스처 중재(gesture arbitration)가 핵심이라 원래도 실기기
검증이 필요한 영역이지만(`docs/agent-rules/testing.md`의 Real-Device Verification 규칙), 이
케이스는 한 단계 더 나아가 **시뮬레이터 UI 자동화 자체가 이 제스처 클래스를 원천적으로
검증할 수 없다**는 것이다. 이걸 모르고 계획 단계에서 "시뮬레이터 스모크로 끝날 것"이라고
가정하면, 검증 태스크가 도구 한계에 부딪혀 시간을 소모하거나 — 더 나쁘게는 — 실패를 대충
"스모크 통과"로 뭉뚱그려 보고해 마일스톤의 핵심 동작이 실은 전혀 검증되지 않은 채 "완료"로
오인될 위험이 있다.

## When to Apply

- `UILongPressGestureRecognizer` 또는 유사한 "홀드 후 동작 시작" 제스처를 도입·변경하고
  XcodeBuildMCP로 시뮬레이터 스모크를 계획할 때
- 플랜/태스크 분해 단계에서부터 이 제스처 클래스가 있으면 "시뮬레이터로 검증 가능한 것"과
  "실기기 검증이 필수인 것"을 처음부터 분리해 둔다 — draw-gesture 플랜의 "검증 현실" 섹션처럼
  사전에 명시하면, 검증 태스크가 이 한계에 부딪혔을 때 당황하지 않고 곧바로 실기기 QA
  체크리스트로 이관할 수 있다.

## Examples

MVP16 draw-gesture Task 3: `drag`(도구 오류로 즉시 실패) → `swipe`(오류 없이 실행되나 홀드
효과 없음, 1회만 재시도 후 중단) 순으로 시도, 두 결과 모두 "시뮬레이터 합성 불가"로 기록하고
`history/mvp16/2026-07-21-draw-gesture-device-checklist.md` 세션 1의 1-2번 항목("가장 먼저,
꼼꼼히 봐주세요")으로 이관. 인접 동작인 "그리기 모드에서 한 손가락 드래그 = 지도 이동"은
`swipe`로 확실히 합성·검증됨(도구 한계와 무관한 별개 스모크). 실기기 QA에서 핵심 동작
전체 통과 확인(2026-07-21).

## Related

- `docs/solutions/workflow-issues/xcodebuildmcp-test-tool-parallel-hang.md` — 같은
  XcodeBuildMCP 툴 계열의 다른 한계(테스트 실행 시 병렬 시뮬레이터 복제로 인한 무한 행)
- `docs/solutions/workflow-issues/gpx-simulated-location-real-device-qa.md` — 다른 종류의
  "자동화 한계 → 실기기 QA로 이관" 사례(시간·거리 기반 이벤트는 GPX 시뮬레이션으로 실기기에서
  가속 검증)
- `docs/agent-rules/testing.md` — Real-Device Verification, QA 체크리스트 템플릿
- `history/mvp16/2026-07-21-draw-gesture.md` — "검증 현실" 섹션, 🚦 결정 게이트
