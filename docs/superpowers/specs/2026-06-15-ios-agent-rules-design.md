# iOS Agent Rules Design

## Goal

Prepare the `Trace` repository for Swift iOS app development before creating the Xcode project. The setup should give future agents a stable rule index for code style, architecture, git workflow, testing, and skill usage.

## Design

Use `AGENTS.md` as the short entry point and keep detailed rules under `docs/agent-rules/`.

`AGENTS.md` stays small so agents can read it every turn. It links to focused rule files:

- `ios-swift.md` for Swift, SwiftUI, Xcode, dependency, accessibility, and localization defaults
- `architecture.md` for app structure and boundaries
- `git.md` for branch, commit, PR, and history safety rules
- `testing.md` for build, test, simulator, performance, and memory verification
- `skills.md` for Superpowers, Compound Engineering, Build iOS Apps, and GitHub plugin usage
- `project-decisions.md` for defaults and decisions that are not known yet

The user does not need to decide product details yet. Unknown product decisions are recorded as reversible defaults. Agents should ask only when a choice affects architecture, privacy, persistence, account creation, cost, or App Store behavior.

## Verification

This setup is documentation-only. Verification is:

- confirm files exist
- inspect the rule index for broken references
- confirm git status before commit

## Follow-Up

After the user is ready to create the app, decide whether Xcode creates the project manually or Codex scaffolds it. Then update `testing.md` with the real scheme, simulator, and minimum iOS target.
