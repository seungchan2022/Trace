# Dual-Tool Workflow Rules

How this repository is worked on from more than one AI coding tool (Codex and
Claude Code) by switching between them — typically when one tool's session or
token budget runs out and work continues in the other.

## What is shared vs tool-specific

Shared (lives in the repo, both tools see it — never duplicate per tool):

- Rule manuals: `docs/agent-rules/*.md`
- Shared prompts: `docs/prompts/trace-init.md`, `docs/prompts/daily-retro.md`
- Git history, `.githooks`, plans (`docs/superpowers/plans/`), specs, `project-decisions.md`

Tool-specific (thin adapters; each tool only reads its own):

- Entry file: Codex reads `AGENTS.md`; Claude Code reads `CLAUDE.md` (a symlink to `AGENTS.md`).
- Slash-command location: Codex `~/.codex/prompts/` (copied in); Claude Code `.claude/commands/` (symlinked to `docs/prompts/`, committed).
- Memory and MCP config: per-tool, not shared. See `setup-codex.md` / `setup-claude.md` under `docs/prompts/`.

## Claude Code 오토컴팩트 복구 설정

컨텍스트가 넘쳐 자동 컴팩션이 발생할 때 작업 맥락이 유실되지 않도록 두 가지 장치를 `.claude/`에 설정한다:

- **`.claude/settings.json` — PreCompact 훅**: 컴팩션 직전 트랜스크립트를 `~/.claude/backups/trace-<timestamp>.jsonl`로 백업. 컴팩션 후 원본 대화를 복원할 수 있다.
- **`.claude/settings.local.json` — `compactPrompt`**: 컴팩션 요약 생성 시 Claude에게 보존 지침을 주입. 브랜치명, 플랜 체크박스 진행률, 수정 파일 목록, 사용자 피드백, 실패한 접근법 5개 항목을 요약에 반드시 포함하도록 지시한다.

`settings.local.json`은 Claude Code 스키마 검증 우회를 위해 분리되어 있다 (`compactPrompt` 필드가 프로젝트 레벨 `settings.json`의 Edit 도구 검증을 통과하지 못하는 버그 회피). 커밋해서 세션 간 유지한다.

Edit shared files to change behavior for both tools; touch a tool-specific
adapter only to wire a tool up.

## Handoff state lives in the repo, never in tool memory

- The next tool resumes only from **git + `project-decisions.md` + plan checkboxes**.
- Claude memory (`~/.claude/.../memory/`) and Codex memory (`~/.codex/memories`) are
  invisible to the other tool. Do not put anything the other tool needs to resume there.
- Record a decision the moment it is made (in `project-decisions.md`), not at session end.

## Keep progress markers live

- Update plan checkboxes (`- [ ]` → `- [x]`) **as each step completes**, not in a batch later.
- Sessions can die on token exhaustion with no clean checkpoint; the checkbox state is the
  primary handoff channel `trace-init` reads to rebuild "done up to Task N, resume at N+1".
- Code committed without its plan checkbox ticked makes the next tool restart blind. If plan
  and working tree disagree, fix the markers before switching tools.

## When to consult the advisor (Claude Code)

This is an agent-behavior rule about **when the agent calls the advisor** — not tool
config. Which main model, effort level, and advisor the user runs are per-tool runtime
settings the user applies with `/model`, `/effort`, and `/advisor`; they are not set
here and not committed.

Context the rule assumes: the user runs a cheap main model with an Opus advisor, so
the agent leans on the advisor at hard moments instead of asking the user to switch models.

- Consult the advisor **only at decision points** — before committing to an approach,
  when an error keeps recurring, and before declaring a task complete. **Not every turn.**
  The user may override in-prompt with "consult the advisor" / "no need to ask the advisor".
- The advisor **advises only; the main model still writes the code.** For a rare
  generation-heavy spike where advice cannot substitute for output quality, flag it to
  the user (who may switch to Opus briefly) rather than shipping weaker output.
- For one-off deeper reasoning on a single turn, put `ultrathink` in the prompt — only
  that keyword is recognized; "think" / "think hard" are passed through as ordinary text.
- Each advisor call re-sends the full transcript to Opus uncached, so it gets pricier as
  a session grows — another reason to consult sparingly, at decision points only.
