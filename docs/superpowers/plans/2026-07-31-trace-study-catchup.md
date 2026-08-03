# trace-study 따라잡기 진행 상태

> **For agentic workers:** 이 파일은 실행 계획이 아니라 **학습 진행 상태**다.
> `/trace-study`(인자 없음)가 이 파일에서 다음 덩어리를 고르고, 세션이 끝나면 체크박스를 켠다.
> `/trace-init`이 이 경로의 `- [ ]`를 읽어 "몇 번까지 했고 다음은 몇 번인지"를 복원한다.

**Goal:** 바이브코딩으로 만들어진 Trace를 기능 단위 9덩어리로 나눠, 각 부품이 **무엇을 받아 무엇을
보장하는지 + 어떤 순서로 이어지는지**(깊이 C) 이해하고, 잊어도 10분이면 복원되는 노트로 남긴다.

**설계 근거:** `docs/superpowers/specs/2026-07-31-trace-study-scope-design.md`
**절차:** `.agents/skills/trace-study/SKILL.md`
**산출물:** `docs/study/<번호>-<슬러그>.md`

**한 덩어리 = 한 세션.** 순서는 데이터가 흐르는 순서(만든다 → 붙인다 → 보여준다 / 잰다 → 살려둔다 → 쓴다)를
따르고, 0번이 맨 앞인 이유는 나머지 8개가 전부 그 골격 위에 얹혀 있기 때문이다.

---

## 진행 상태

- [x] **0. 앱 구조** → `docs/study/0-app-architecture.html` (2026-08-03 완료 · 7파트 + 확인 문제 6)
- [ ] **1. 손으로 그은 선이 도로 경로가 되는 법** → `docs/study/1-drawn-path-to-route.html`
- [ ] **2. 구간을 이어붙이고 재는 법** → `docs/study/2-segment-stitching.html`
- [ ] **3. 지도 위에 표시하는 법** → `docs/study/3-map-rendering.html`
- [ ] **4. GPS가 거리·페이스가 되는 법** → `docs/study/4-gps-to-stats.html`
- [ ] **5. 백그라운드에서 계속 도는 법** → `docs/study/5-background-execution.html`
- [ ] **6. 소리 내는 법** → `docs/study/6-audio-coaching.html`
- [ ] **7. 잠금화면 위젯** → `docs/study/7-live-activity.html`
- [ ] **8. 저장하는 법** → `docs/study/8-persistence.html`

전부 `- [x]`가 되면 따라잡기는 끝이다. 그 뒤로는 `/trace-study MVP{N}`(따라가기)으로 전환하고,
이 파일과 설계 스펙의 처분(옮길지·지울지·둘지)을 그 시점에 판단한다.
