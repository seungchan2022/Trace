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

## 파일 크기 기준선 (2026-07-30 조사)

- **`AGENTS.md`(및 심볼릭 `CLAUDE.md`)는 120줄 이하로 유지한다.** 이 파일만 모든 세션에
  자동 로드된다. 모델이 한 컨텍스트에서 신뢰성 있게 따르는 지시는 150~200개이고 도구
  시스템 프롬프트가 이미 상당수를 쓴다 — 80줄을 넘으면 규칙이 떨어지기 시작하고 200줄을
  넘으면 블록 단위로 무시된다(비선형). 현재 65줄.
- **`docs/agent-rules/` 상세 파일은 자동 로드되지 않으므로 위 한계가 그대로 적용되지 않는다.**
  Rule Index를 보고 필요할 때 읽는 구조가 곧 progressive disclosure다. `@path` import로
  바꾸지 말 것 — import는 조직화에만 도움이 되고 **시작 시 함께 로드되어 컨텍스트를 줄이지 않는다.**
- **상세 파일 하나가 300줄을 넘으면 분리를 검토한다.** 단 **섹션 단위가 아니라 도메인 단위로**
  나눈다. 같은 흐름의 분기를 떼어놓으면 "한 규칙 한 곳" 원칙이 깨지고 두 파일이 어긋난다
  (2026-07-30에 같은 내용이 두 곳에 있어 생긴 불일치를 4건 고쳤다).

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
