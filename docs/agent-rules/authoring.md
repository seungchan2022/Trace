# Documentation and Rule-File Authoring

How rule and documentation files in this repository are structured.
Read this before creating or editing any file under `docs/agent-rules/`
or any rule/skill documentation.

## Principle: lean entry point, referenced details

`AGENTS.md` is loaded into every agent session. Detail rule files are read
only when a task touches them. Efficiency comes from keeping the always-loaded
entry point small and pushing specifics into single-responsibility detail files
(progressive disclosure).

- Entry point (`AGENTS.md`): project facts, the Rule Index, and only the safety
  hard-stops an agent needs *before* it would open a detail file.
- Detail files (`docs/agent-rules/*.md`): one domain per file; own the full
  rules for that domain.

## One rule, one home

- Each rule lives in exactly one file. Do not restate it in another file.
- When another file needs a rule, link to its home file; do not copy the text.
- Duplication wastes the always-loaded context and drifts out of sync over time.

Exception: safety hard-stops (no push, no commit on `main`, no force push or
history rewrite without approval) may also appear in `AGENTS.md`, because an
agent can act on git before opening `git.md`. Keep that list short and point to
`docs/agent-rules/git.md` for the rest.

## What goes where — the discriminator

Ask: does the agent need this *before* it would naturally open the detail file?

- Yes (safety hard-stops): keep it in the entry point.
- No (procedure, format, steps, naming, examples): detail file only.

## Planning and spec document language

- Write user-reviewed planning documents, product specs, MVP designs, and
  `docs/superpowers/specs/` documents in Korean by default.
- Keep code identifiers, API names, class names, commands, and file paths in
  their original language.
- Use English only when the document is primarily for external tooling or when
  the user explicitly asks for English.

## Adding a new rule or skill file

1. Create the file under `docs/agent-rules/` with a single domain.
2. Add one line to the `AGENTS.md` Rule Index pointing to it.
3. Cross-link related files instead of repeating their content.
4. Do not paste the file's content into `AGENTS.md`.

## Template

```text
# <Domain> Rules

## <Section>

- <rule, one line, imperative>
- <rule>; see `docs/agent-rules/<other>.md` for related detail.
```
