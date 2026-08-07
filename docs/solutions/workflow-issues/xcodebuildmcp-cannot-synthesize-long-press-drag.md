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
  - "computer-use MCP로 시뮬레이터를 조작하려 할 때 — 권한, 멀티 모니터/Space, 좌표계 함정이 여기 정리돼 있다"
tags: [xcodebuildmcp, simulator, ui-automation, long-press, gesture, touch-synthesis, real-device-qa, computer-use, macos-permissions, multi-display]
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

## 다른 경로: computer-use MCP로 합성 성공 (2026-08-07 검증 완료)

**computer-use MCP는 롱프레스-드래그를 합성한다.** 즉 "누른 채 이동"으로 경로를 긋는 동작은
실기기 없이 시뮬레이터로 검증할 수 있다.

⚠️ **뚫린 것은 이 제스처 하나다.** 더블탭·원핑거 줌·이어 그리기는 **이번에 검증하지 않았다.**
그쪽은 도구 문제가 아니라 **타이밍 의존**이라 막힌 것이라, computer-use로 옮긴다고 풀린다는
근거가 없다(MVP10 설계와 MVP16 「검증 현실」 양쪽이 "실기기 확인 필수"라 적어 뒀고, 결정론적
근거로는 `TapClassifierTests` 7개가 있다). **"그리기 제스처 전체가 시뮬레이터로 된다"로 넓혀
읽지 말 것.**

computer-use는 macOS 마우스 이벤트를 시뮬레이터 **창**에 직접 보내므로 위에서 막힌
`FBSimulatorHIDEvent`를 거치지 않고, `left_mouse_down` · `mouse_move` · `left_mouse_up`을
따로 부를 수 있어 "누른 채 이동"이 실제로 만들어진다.

- **첫 시도에 성공했다.** 대기 0.4초 + 중간 `mouse_move` 3개. anti-loop 예비 조정(대기 0.6초,
  중간점 6개)은 쓰지 않았다.
- **Simulator의 tier는 `full`이다** — `list_granted_applications`로 확인. "개발 도구니까 click
  tier일 것"이라는 추측은 틀렸다. 클릭도 드래그도 막히지 않는다. 단, `request_access` 응답에는
  tier가 없고 `list_granted_applications` 응답에만 있으니 그쪽을 봐야 한다.
- **판정 근거는 두 가지를 같이 본다.** 출발·도착 마커와 도보 스냅 경로선(0.94km)이 그려졌고,
  **동시에 지도가 전혀 패닝되지 않았다.** 후자가 중요하다 — 롱프레스가 지도 팬 제스처와의
  중재에서 이겼다는 뜻이고, XcodeBuildMCP `swipe`가 실패했던 지점이 정확히 여기다.
- 그래서 배치 **직전에** `mcp__XcodeBuildMCP__screenshot`으로 베이스라인을 찍어 둔다. 사후
  이미지 하나만으로는 "선이 그려짐 / 지도만 움직임 / 아무 일도 안 일어남"을 구분할 수 없다.

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

### 두 번째 함정: 창을 못 찾는다 (멀티 모니터·Space)

권한을 뚫고 나면 다음 벽은 **시뮬레이터 창이 스크린샷에 안 보이는 것**이다. 실제로 여기서
왕복을 여러 번 썼다.

1. **`open_application("Simulator")`은 창을 현재 모니터로 가져오지 않는다.** 시뮬레이터 창이
   다른 모니터에 있으면 스크린샷은 그 모니터를 안 찍는다. `switch_display`로 모니터를 옮겨
   가며 찾고, 끝나면 **`switch_display("auto")`로 돌려놓는 게 가장 잘 맞았다** — auto가
   최전면 앱이 있는 모니터를 골라 준다.
2. **허용 목록에 없는 앱이 전체 화면이면 화면이 통째로 비거나 까맣게 나온다.** 컴포지터가
   그 앱을 걸러내는데 뒤에 배경이 없어서다(Chrome·iPhone 미러링에서 각각 겪었다). 바탕화면이
   보이거나 새까만 화면이 나오면 "시뮬레이터가 없다"가 아니라 **다른 Space를 보고 있는 것**이다.
3. **`zoom`은 최근 전체 화면 스크린샷과 다른 모니터를 잡은 적이 있다.** 확대했는데 엉뚱한
   내용이 나오면 전체 스크린샷을 다시 찍어 기준을 잡고 다시 확대한다.
4. **`computer_batch`는 각 액션 직전에 최전면 앱을 검사한다.** 배치 전에 조건 없이
   `open_application("Simulator")`을 부르고, 배치가 오류로 멈추면 **`left_mouse_up`을 즉시
   호출한다** — 안 그러면 버튼이 눌린 채로 사용자 데스크톱에 남는다.

### 세 번째 함정: Cmd+Q가 사전 조건을 날린다

권한 때문에 Claude Code를 `Cmd+Q`로 껐다 켜면 **플랜에 "이미 끝나 있음"으로 적어 둔 것들이
같이 사라진다.** 2026-08-07 세션에서 둘 다 실제로 어긋나 있었다.

- **XcodeBuildMCP 세션 defaults가 비어 있다.** `session_show_defaults`로 먼저 확인한다.
- **시뮬레이터가 종료돼 있을 수 있다.** `xcrun simctl list devices booted`로 확인한다.
- 이때 **다시 빌드하지 않는다.** 부팅 → 앱 설치 여부 확인 → 실행이면 충분하다:
  `xcrun simctl boot <UDID>` · `xcrun simctl get_app_container <UDID> <bundleId>` ·
  `launch_app_sim`.

### 재현 절차 (성공한 그대로)

```
list_granted_applications          # tier가 "full"인지 확인
open_application("Simulator")
screenshot                         # 여기서 읽은 좌표만 쓴다 (아래 좌표계 주의)
left_click(「그리기」 버튼)          # 모드 전환
mcp__XcodeBuildMCP__screenshot     # 베이스라인 — 배치 직전에 찍는다

computer_batch([
  mouse_move       → 지도 위 시작점
  left_mouse_down
  wait 0.4                          # 롱프레스 임계값 0.25초보다 크게
  mouse_move       → 중간점 1
  mouse_move       → 중간점 2
  mouse_move       → 끝점
  left_mouse_up
  wait 0.3                          # 스트로크 렌더링 대기
  screenshot
])

mcp__XcodeBuildMCP__screenshot     # 판정은 이걸로 (창 전체 샷은 선이 잘 안 보인다)
```

- **중간점을 여러 개 두는 것이 핵심이다.** 한 번에 끝점으로 점프하면 이동 이벤트가 하나뿐이라
  스트로크가 안 쌓인다.
- **좌표계를 섞지 않는다.** computer-use 좌표는 최근 전체 화면 스크린샷의 macOS 픽셀이고,
  `snapshot_ui`/XcodeBuildMCP 좌표는 기기 좌표다. 클릭 좌표는 **반드시** computer-use
  스크린샷에서 읽는다. `snapshot_ui`는 화면 상태 확인용으로만 쓴다.
- 모드 전환이 됐는지는 버튼 하이라이트만 보지 말고 **하단 시트 문구**로 확인한다
  (탭 모드 "지도를 탭해 출발지를 선택하세요" → 그리기 모드 "지도를 꼭 눌러서 경로를 그려보세요").

## Why This Matters

롱프레스-드래그류 제스처는 UIKit 제스처 중재(gesture arbitration)가 핵심이라 원래도 실기기
검증이 필요한 영역이지만(`docs/agent-rules/testing.md`의 Real-Device Verification 규칙), 이
케이스는 한 단계 더 나아가 **XcodeBuildMCP가 이 제스처 클래스를 원천적으로 합성하지
못한다**는 것이다. 이걸 모르고 계획 단계에서 "시뮬레이터 스모크로 끝날 것"이라고 가정하면,
검증 태스크가 도구 한계에 부딪혀 시간을 소모하거나 — 더 나쁘게는 — 실패를 대충 "스모크
통과"로 뭉뚱그려 보고해 마일스톤의 핵심 동작이 실은 전혀 검증되지 않은 채 "완료"로 오인될
위험이 있다.

**단, "시뮬레이터로는 불가"가 아니다.** 2026-08-07 검증으로 computer-use MCP가 롱프레스-드래그를
합성한다는 것이 확인됐다(위 절). 이건 도구를 바꾸면 되는 문제이지 플랫폼의 한계가 아니었다.
새 플랜을 짤 때는 **롱프레스-드래그를 "computer-use로 검증 가능"** 쪽에 넣는다.

**그래도 분리는 여전히 필요하다.** 뚫린 것은 홀드-후-이동 하나이고, **타이밍 의존 제스처
(더블탭·원핑거 줌처럼 판별 창 안에서 결과가 갈리는 것)는 도구를 바꿔도 그대로 남는다.**
"시뮬레이터로 검증 가능 / 실기기 필수"를 계획 단계에서 나누라는 원래 교훈은 유효하고,
경계선이 "도구가 합성할 수 있나"에서 **"타이밍에 의존하나"**로 옮겨졌을 뿐이다.

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
