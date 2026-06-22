# MVP 아카이빙 (공용 프롬프트)

> 이 절차는 Codex와 Claude Code **양쪽에서 `/trace-archive`로 호출**된다.
> - Codex: 이 파일을 `~/.codex/prompts/trace-archive.md`에 복사해 등록 (`docs/prompts/setup-codex.md` 참고).
> - Claude Code: `.claude/commands/trace-archive.md`가 이 파일을 가리키므로 별도 복사 없이 인식된다.
> 목적: 완료된 MVP의 마일스톤 산출물(spec+plan)을 `history/`로 옮기고 회고·인덱스를 갱신한다.
> `/trace-archive` 또는 `/trace-archive MVP1`.

## 전제

- 단위·트리거 규칙은 `docs/agent-rules/workflow.md`. 이 프롬프트는 그 **아카이빙 절차의 실행본**이다.
- 파일 이동은 **`git mv`로 이력 보존**. 커밋·푸시는 하지 않는다 — 사용자가 명시적으로 요청할 때만,
  경로를 지정해 stage/commit (`docs/agent-rules/git.md`).
- `main`이면 먼저 feature 브랜치를 판다.

## 0. 대상 MVP 확인

- 인자 없으면 `docs/roadmap.md`에서 **마일스톤이 전부 `[x]`인데 아직 아카이빙 안 된 MVP**를 찾아 제안.
- **폴더명**: 단순 번호 — `mvp1`, `mvp2` … (예: `history/mvp1/`). **0.5 단위는 점을 살린다** (`mvp1.5` ≠ `mvp15`).

## 1. 완료 검증 (사용자 확인 후 진행)

- `docs/roadmap.md`의 해당 MVP 마일스톤이 모두 `[x]`인지 확인.
- 각 마일스톤 plan의 체크박스 ↔ 실제 구현/커밋 일치 확인.
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

해당 MVP 마일스톤의 spec/plan을 `history/<slug>/`로 이동:

```bash
mkdir -p history/mvpN
git mv docs/superpowers/specs/<...>-design.md history/mvpN/
git mv docs/superpowers/plans/<...>.md          history/mvpN/
```

- `docs/superpowers/specs|plans/` 루트에는 **진행 중 마일스톤 문서만** 남는다.
- QA 체크리스트(`docs/qa/`) 등 그 MVP 전용 문서가 있으면 함께 이동을 제안한다.

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

- 이동한 파일 수, 회고 경로, INDEX/roadmap 갱신 요약.
- stale(7일 이상 미수정·"진행중" 상태) 문서가 있으면 목록 보고.
- 커밋이 필요하면 명시 경로 stage 후 사용자에게 커밋 여부를 묻는다 (직접 커밋하지 않는다).
