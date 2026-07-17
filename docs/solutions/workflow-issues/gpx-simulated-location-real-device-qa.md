---
title: "실제로 뛰지 않고 실기기 QA — GPX 파일로 위치 시뮬레이션"
date: 2026-07-17
category: workflow-issues
module: QA workflow / Run tracking
problem_type: workflow_issue
component: development_workflow
severity: low
applies_when:
  - "실기기 QA에서 거리/시간 경과에 따라 트리거되는 동작(km 경계 안내, 목표 절반/달성, 스플릿 등)을 확인해야 하는데, 매번 실제로 걷거나 뛰기엔 QA 사이클이 느려질 때"
  - "정확히 특정 지점(예: 정확히 1.5km 또는 정확히 3분)에서 이벤트가 발생하는지 확인해야 해서, 실제로 뛰어서는 타이밍을 맞추기 어려울 때"
tags: [gpx, simulate-location, real-device-qa, xcode, run-tracking, location-simulation]
---

# 실제로 뛰지 않고 실기기 QA — GPX 파일로 위치 시뮬레이션

## Context

MVP14 `run-goal`(거리/시간 목표 + 절반·달성 음성 안내) 실기기 QA를 진행하면서, 매 시나리오마다
실제로 몇 km를 걷거나 몇 분을 기다려야 했다. 특히 "정확히 목표의 절반 지점에서 안내가
나오는가" 같은 시나리오는 실제로 뛰면서 타이밍을 맞추기 어렵다. Xcode의 위치 시뮬레이션
기능을 실기기에 적용해 이 문제를 해결했다 — 실제로는 제자리에 있어도 앱은 GPX 경로를 따라
이동하는 것으로 인식한다.

## Guidance

1. **Xcode에서 기기를 케이블로 연결하고 앱을 실행한 채로 Debug → Simulate Location에서
   GPX 파일을 선택한다.** 시뮬레이터 전용 기능이 아니라 실기기에서도 동작하며, 백그라운드
   위치 권한이 있는 앱(Trace처럼)이면 **화면을 잠가도 계속 흘러간다** — 잠금화면+음악 같은
   시나리오도 실제로 걷지 않고 검증할 수 있다.
2. **GPX는 원하는 페이스에 맞춰 직접 만든다.** `<wpt>`에 위도·경도·`<time>`만 있으면 되고,
   Xcode는 그 타임스탬프 간격에 맞춰 실시간으로(파일의 시간 배율 그대로) 재생한다. 즉 10초
   간격으로 좌표를 100m씩 전진시키면 실제 페이스는 10m/s(=1km/100초)가 되고, 이 페이스를
   미리 계산해서 원하는 시각에 원하는 지점(예: 목표 거리의 절반)이 오도록 역산하면 된다.
   최소 파이썬 스니펫:

   ```python
   import datetime
   base_lat, lon = 37.5665, 126.978000  # 서울시청 근방, 임의 시작점
   meters_per_deg = 111320.0
   pace_m_per_s = 1000.0 / 60.0          # 예: 1km당 60초 페이스
   t0 = datetime.datetime(2026, 1, 1)

   lines = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<gpx version="1.1" creator="Trace QA" xmlns="http://www.topografix.com/GPX/1/1">']
   for i in range(0, total_seconds // step_seconds + 1):
       t_s = i * step_seconds
       lat = base_lat + (t_s * pace_m_per_s) / meters_per_deg
       t = t0 + datetime.timedelta(seconds=t_s)
       lines.append(f'  <wpt lat="{lat:.6f}" lon="{lon:.6f}"><time>{t.isoformat()}Z</time></wpt>')
   lines.append('</gpx>')
   ```

   페이스를 딱 떨어지는 값(1km/분 등)으로 잡으면 목표 지점(절반·달성 등)이 정확히 정수
   분·초에 오도록 설계할 수 있어 체크리스트 작성이 쉬워진다.
3. **파일 끝에서 정확히 종료하도록 여유 구간을 둔다** — 아래 "Why This Matters"의 되감기
   문제 때문에, 확인해야 할 마지막 이벤트 이후로 최소 30초~1분의 안전 여유를 두고, 테스터가
   그 안에 종료 버튼을 누르도록 안내한다.
4. QA가 끝나면 **이 사이클 전용으로 만든 GPX 파일 자체는 커밋하지 않는다.** 목표값(3km,
   5분 등)이 사이클마다 다르므로 재사용 가치가 낮고, `docs/qa/`가 일회성 픽스처로 쌓이는
   걸 막기 위해 이 문서(방법)만 남기고 파일은 QA 완료 후 지운다. 다음에 필요하면 위 스니펫으로
   몇 초 만에 다시 만들 수 있다.

## Why This Matters

**Xcode의 GPX 시뮬레이션은 파일 끝에 도달하면 자동으로 처음 웨이포인트로 되돌아가 반복
재생한다** — 이건 Xcode 자체 동작이라 앱에서 막을 방법이 없다. 그런데 Trace의
`RunSession.ingest`/`RunTrack.append`는 GPS 정확도(`horizontalAccuracyMeters ≤ 30`)만
검사할 뿐, 연속된 두 샘플 사이의 거리·속도가 물리적으로 말이 안 되는지는 전혀 검사하지
않는다(`docs/backlog.md`의 "GPS 거리 이상치 방어 로직 없음" 참고). 그래서 파일이 되감기는
순간의 "순간이동" 점프도 그대로 총 거리에 합산돼, 예를 들어 6km 지점에서 되감긴 채로 두면
기록이 11km처럼 부풀려진다. **테스터가 파일이 끝나기 전(또는 끝나는 순간)에 종료 버튼을
누르기만 하면 이 문제를 완전히 피할 수 있다** — GPX를 설계할 때 마지막 확인 지점 이후로
여유 구간을 넉넉히 두는 이유가 이것이다.

## When to Apply

- 거리·시간 경과로 트리거되는 동작(음성 안내, 진행률, 스플릿, 목표 판정 등)을 실기기에서
  확인해야 할 때
- 정확한 타이밍(예: "정확히 절반 지점")을 실제로 뛰어서는 맞추기 어려울 때
- 화면 잠금·백그라운드 상태에서도 위치 기반 동작이 이어지는지 확인해야 할 때

## Examples

- `run-goal` QA: 거리 목표(3km, 1km/분 페이스)는 1분 30초=1.5km(절반), 3분=3km(달성)이
  되도록 설계, 시간 목표(5분, 피커 최소값)는 별도 GPX로 2분 30초=절반·5분=달성이 되도록
  설계. 둘 다 마지막 확인 지점 이후 최소 1분의 여유를 두고 "파일 끝나기 전 종료"를 체크리스트에
  명시.

## Related

- `docs/agent-rules/testing.md` — Real-Device Verification, QA 체크리스트 템플릿
- `docs/backlog.md` MVP14 run-goal 섹션 — "GPS 거리 이상치(비정상 점프) 방어 로직 없음"
  (이 문서의 되감기 문제가 드러낸 근본 원인, 트리거 조건과 함께 기록됨)
