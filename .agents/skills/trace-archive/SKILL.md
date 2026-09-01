---
name: trace-archive
description: 완료된 Trace MVP의 명세·플랜·회고·로드맵 상태를 아카이빙해야 할 때 사용한다.
---

# MVP 아카이빙

> Codex에서는 `$trace-archive` 또는 `$trace-archive MVP1`, Claude Code에서는 `/trace-archive` 또는 `/trace-archive MVP1`로 호출한다.
> 목적: 완료된 MVP의 마일스톤 산출물(spec+plan)을 `history/`로 옮기고 회고·인덱스를 갱신한다.
> 아카이빙은 기존 산출물을 보존·색인하는 절차다. `diagram-design`으로 새 도식을 만들거나 기존
> 도식을 다시 그리는 범위는 아니다.

## 전제

- 단위·트리거 규칙은 `docs/agent-rules/workflow.md`, 제품 현황판의 완료 규칙은
  `docs/agent-rules/product-visibility.md`. 이 스킬은 그 **아카이빙 절차의 실행본**이다.
- 파일 이동은 **`git mv`로 이력 보존**. 커밋·푸시는 하지 않는다 — 사용자가 명시적으로 요청할 때만,
  경로를 지정해 stage/commit (`docs/agent-rules/git.md`).
- `main`이면 먼저 feature 브랜치를 판다.

## 0. 대상 MVP 확인

- 인자 없으면 `docs/roadmap.md`에서 **마일스톤이 전부 `[x]`인데 아직 아카이빙 안 된 MVP**를 찾아 제안.
- **폴더명**: 단순 번호 — `mvp1`, `mvp2` … (예: `history/mvp1/`). **0.5 단위는 점을 살린다** (`mvp1.5` ≠ `mvp15`).

## 1. 완료 검증 (사용자 확인 후 진행)

- `docs/roadmap.md`의 해당 MVP 마일스톤이 모두 `[x]`인지 확인.
- 각 마일스톤 plan의 체크박스 ↔ 실제 구현/커밋 일치 확인.
- `docs/current-mvp.md`의 완료 결과·QA 근거·제품 기준선 영향이 최신인지 확인.
- ⚠️ **소급 정리 엣지케이스**: 코드는 완료됐는데 plan 체크박스가 비어 있으면 —
  체크박스를 전부 복원하지 말고, plan 상단에 `> 완료(소급 확인): <근거 커밋 해시/요약>` 한 줄 노트를
  추가하고, 정말 미진한 항목만 표시한다. (`workflow.md` 엣지케이스 규칙)

## 2. 회고 작성

`history/mvpN/<YYMMDD>_mvpN_completion_retro.md` 생성:

- **Keep / Problem / Surprise**
- 마일스톤별 핵심 의사결정과 "왜"
- 남은 기술부채 (→ `docs/backlog.md` 항목과 연결)
- 다음 MVP 방향

## 3. 아카이빙 (`git mv`)

해당 MVP 마일스톤의 spec/plan/회고를 `history/<slug>/`로 이동:

```bash
mkdir -p history/mvpN
git mv docs/superpowers/specs/<...>-design.md history/mvpN/
git mv docs/superpowers/plans/<...>.md          history/mvpN/
git mv docs/retro/<...>-retro.md                history/mvpN/   # milestone-retro 산출물
```

- `docs/superpowers/specs|plans/`와 `docs/retro/` 루트에는 **진행 중 마일스톤 문서만** 남는다.
- QA 체크리스트(`docs/qa/`) 등 그 MVP 전용 문서가 있으면 함께 이동을 제안한다.
- 마일스톤 회고(`milestone-retro` 산출물)는 사용자 인터뷰가 들어간 유일한 마일스톤 단위 기록이므로,
  **2번 완료 회고를 쓸 때 근거로 먼저 읽는다.** 커밋만 보고 추측해서 쓰지 않는다.

### 3.1 제품 현황판과 기준선

1. `docs/current-mvp.md`의 `제품 기준선 영향`이 `변경 후보`면 사용자에게 변경 여부를 묻는다.
2. 승인된 경우에만 `docs/product-baseline.md`를 갱신하고, 이전 방향과 변경 이유를 완료 회고에 남긴다.
3. 활성 현황판을 `git mv docs/current-mvp.md history/mvpN/overview.md`로 보존한다.
4. `docs/current-mvp.md`를 진행 중 MVP 없음 상태로 다시 만든다. 제품 기준선, 마지막 완료 MVP,
   `docs/backlog.md`, 마지막 갱신일 링크만 둔다.

## 4. INDEX 갱신

`history/INDEX.md`에 MVP 항목 추가:

```markdown
## <MVP명> — <한 줄 설명> (<기간>)

> <규모/기간 요약>

| 유형 | 파일 | 핵심 내용 |
|------|------|----------|
| 기획 | [<제목>](<경로>) | <설명> |
| 회고 | [<제목>](<경로>) | <설명> |
```

## 5. roadmap 갱신

`docs/roadmap.md`에서 해당 MVP를 **"완료(아카이빙됨)"**으로 바꾸고 `history/mvpN/` 경로를 링크한다.

## 6. 보고

- 이동한 파일 수, 회고·overview 경로, INDEX/roadmap 갱신 요약.
- stale(7일 이상 미수정·"진행중" 상태) 문서가 있으면 목록 보고.
- 커밋이 필요하면 명시 경로 stage 후 사용자에게 커밋 여부를 묻는다 (직접 커밋하지 않는다).
