# Remaining Trace Shared Skills Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the four remaining Trace-specific legacy prompts into one shared skill source that Codex and Claude Code both discover without copied prompt bodies.

**Architecture:** Each command becomes `.agents/skills/<name>/SKILL.md`, retaining its existing workflow and adding tool-neutral metadata. Codex reads that directory directly; Claude Code receives a symlink per skill under `.claude/skills/`. The legacy source prompts and command symlinks are removed only after their replacements exist.

**Tech Stack:** Agent Skills Markdown/YAML frontmatter, Git symbolic links, project documentation.

**Status (2026-07-23):** Complete. Fresh sessions discovered all four shared skills, and the
legacy global `daily-retro` prompt was removed only after that verification.

## Global Constraints

- Do not change Superpowers or other plugin-provided skills.
- Codex invokes Trace skills with `$<name>`; Claude Code invokes the same skill with `/<name>`.
- Do not copy a shared skill body into a tool-specific location.
- Do not delete the pre-existing global Codex `daily-retro` prompt until the user verifies the new skill in a new Codex session.
- Do not commit or push.

---

### Task 1: Create the four shared skill sources

**Files:**
- Create: `.agents/skills/daily-retro/SKILL.md`
- Create: `.agents/skills/trace-archive/SKILL.md`
- Create: `.agents/skills/trace-study/SKILL.md`
- Create: `.agents/skills/trace-video-review/SKILL.md`

- [x] **Step 1: Record the missing shared-skill baseline**

Run:

```bash
for skill in daily-retro trace-archive trace-study trace-video-review; do
  test -f ".agents/skills/$skill/SKILL.md" || echo "$skill: baseline-missing"
done
```

Expected: all four skills report `baseline-missing`.

- [x] **Step 2: Create each `SKILL.md` with valid frontmatter and the preserved legacy procedure**

Each file begins with:

```markdown
---
name: <skill-name>
description: Use when ...
---
```

Remove only obsolete prompt-copy instructions; preserve command arguments, project rules, and workflow steps.

- [x] **Step 3: Verify each common source exists and exposes valid metadata**

Run:

```bash
for skill in daily-retro trace-archive trace-study trace-video-review; do
  test -f ".agents/skills/$skill/SKILL.md" &&
  rg -q '^name: ' ".agents/skills/$skill/SKILL.md" &&
  rg -q '^description: .+' ".agents/skills/$skill/SKILL.md"
done
```

Expected: exit status `0`.

### Task 2: Replace Claude command adapters with skill adapters

**Files:**
- Create: `.claude/skills/daily-retro` (symlink)
- Create: `.claude/skills/trace-archive` (symlink)
- Create: `.claude/skills/trace-study` (symlink)
- Create: `.claude/skills/trace-video-review` (symlink)
- Delete: `.claude/commands/daily-retro.md`
- Delete: `.claude/commands/trace-archive.md`
- Delete: `.claude/commands/trace-study.md`
- Delete: `.claude/commands/trace-video-review.md`

- [x] **Step 1: Create one Claude symlink per shared skill**

Each adapter points to `../../.agents/skills/<name>` and contains no duplicated Markdown.

- [x] **Step 2: Remove the four obsolete command symlinks**

The original Markdown sources remain until Task 3 updates references.

- [x] **Step 3: Verify links resolve to shared sources**

Run:

```bash
for skill in daily-retro trace-archive trace-study trace-video-review; do
  test -L ".claude/skills/$skill" &&
  test -f ".claude/skills/$skill/SKILL.md"
done
```

Expected: exit status `0`.

### Task 3: Update references and remove legacy source prompts

**Files:**
- Modify: `docs/agent-rules/skills.md`
- Modify: `docs/agent-rules/dual-tool.md`
- Modify: `docs/agent-rules/workflow.md`
- Modify: `docs/prompts/setup-codex.md`
- Modify: `docs/prompts/setup-claude.md`
- Delete: `docs/prompts/daily-retro.md`
- Delete: `docs/prompts/trace-archive.md`
- Delete: `docs/prompts/trace-study.md`
- Delete: `docs/prompts/trace-video-review.md`

- [x] **Step 1: Point rules and setup documents to the shared skill layout**

Replace “custom prompt,” `docs/prompts/<name>.md`, `~/.codex/prompts/` copy directions, and `.claude/commands/` directions for these four commands with their shared-skill locations and the `$`/`/` invocation distinction.

- [x] **Step 2: Delete the now-unreferenced legacy prompt source files**

Delete only the four prompt sources whose full procedures now live under `.agents/skills/`.

- [x] **Step 3: Verify no legacy Trace-command paths remain**

Run:

```bash
rg -n --glob '!docs/superpowers/plans/**' \
  'docs/prompts/(daily-retro|trace-archive|trace-study|trace-video-review)\\.md|\\.claude/commands/(daily-retro|trace-archive|trace-study|trace-video-review)\\.md' \
  AGENTS.md CLAUDE.md docs .claude .agents
```

Expected: no matches.

### Task 4: Validate migration and hand off runtime checks

**Files:**
- Modify: `docs/superpowers/plans/2026-07-23-remaining-shared-skills.md`

- [x] **Step 1: Run structural and whitespace checks**

Run the Task 1 and Task 2 verification loops, `git diff --check`, and `git status --short`.

- [x] **Step 2: Ask the user to verify the new runtime commands in fresh sessions**

Codex: `$daily-retro`, `$trace-archive`, `$trace-study`, `$trace-video-review`.

Claude Code: `/daily-retro`, `/trace-archive`, `/trace-study`, `/trace-video-review`.

- 사용자 확인 완료(2026-07-23): 새 세션에서 공용 스킬이 정상 발견된다.

- [x] **Step 3: Remove the old global Codex `daily-retro` copy after verification succeeds**

사용자 확인 뒤 `~/.codex/prompts/daily-retro.md`가 없는 상태를 확인했다. 공용 원본은
`.agents/skills/daily-retro/SKILL.md`에 남아 있다.
