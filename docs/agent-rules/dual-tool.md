# Dual-Tool Workflow Rules

How this repository is worked on from more than one AI coding tool (Codex and
Claude Code) by switching between them — typically when one tool's session or
token budget runs out and work continues in the other.

## What is shared vs tool-specific

Shared (lives in the repo, both tools see it — never duplicate per tool):

- Rule manuals: `docs/agent-rules/*.md`
- Shared skills: `.agents/skills/*/SKILL.md` (`trace-init`, `daily-retro`, `trace-archive`, `trace-study`, `trace-video-review`)
- Git history, `.githooks`, plans (`docs/superpowers/plans/`), specs, `project-decisions.md`

Tool-specific (thin adapters; each tool only reads its own):

- Entry file: Codex reads `AGENTS.md`; Claude Code reads `CLAUDE.md` (a symlink to `AGENTS.md`).
- Shared-skill discovery: Codex reads `.agents/skills/` directly; Claude Code reads `.claude/skills/`, whose entries are symbolic links to `.agents/skills/`. 호출 문법만 다르다: Codex `$<skill-name>`, Claude Code `/<skill-name>`.
- Trace-specific skills do not use Codex `~/.codex/prompts/` or Claude Code `.claude/commands/`. Those paths are legacy adapters, not a source of truth.
- Tool settings: Codex project settings live in `.codex/config.toml`; Claude Code project settings live in `.claude/settings*.json`. 공통 정책은 맞추되, 도구별 설정 문법과 기능은 복사하지 않는다.
- Terminal permission model: Claude Code uses `permissions.allow` / `permissions.deny`; Codex uses `sandbox_mode`, `approval_policy`, and `.codex/rules/*.rules`. Trace의 Codex 기본값은 `workspace-write + on-request`다. 일반 프로젝트 작업은 승인 없이 실행하지만, 커밋처럼 보호된 `.git` 쓰기는 사용자 승인을 요청할 수 있다. 이는 전체 시스템 쓰기·네트워크 bypass가 아니며, 위험 명령 차단 규칙의 원문은 `docs/agent-rules/git.md`.
- Memory and MCP config: per-tool, not shared. See `setup-codex.md` / `setup-claude.md` under `docs/prompts/`.

## Adding a Trace-specific skill

새 Trace 전용 스킬은 항상 아래 구조로 만든다. 스킬 본문을 도구별 폴더에 복사하지 않는다.

```text
.agents/skills/<skill-name>/SKILL.md       # 공통 원본
.claude/skills/<skill-name>                # ../../.agents/skills/<skill-name> 링크
```

- Codex에서는 `$<skill-name>`, Claude Code에서는 `/<skill-name>`으로 명시 호출한다.
- 스킬이 두 도구에서 같은 정책을 요구하면 본문은 `SKILL.md`에 한 번만 쓴다.
- 도구 고유 설정은 `.codex/config.toml` 또는 `.claude/settings*.json`에만 추가하고, 공통 규칙은 `AGENTS.md`와 `docs/agent-rules/`에 둔다.

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

## Subagent and review model policy

- The user chooses the main session's model and reasoning level when starting that session. Do not pin a single main model for Trace: planning normally uses the highest-capability model, while implementation normally uses the balanced model at high reasoning.
- Do not use a low-tier/high-volume model for Trace implementation subagents or reviews (`Luna` in Codex; the equivalent lowest-tier model in another tool).
- Do not set a fixed default subagent model in Trace. A spawned agent normally inherits the parent session's model and reasoning level, so a Sol planning session stays Sol and a Terra implementation session stays Terra.
- A hard design decision, security/architecture review, or repeated failure that requires reconsidering the approach may explicitly use `gpt-5.6-sol` with `high` reasoning instead.
- Claude Code has no matching Trace project setting for a default subagent model. Keep the user's session-level model and advisor choices there; apply the same low-tier prohibition and use its higher-capability advisor/model only for the escalation cases above.

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
