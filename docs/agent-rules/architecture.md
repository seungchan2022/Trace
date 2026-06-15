# Architecture Rules

## Default Shape

Use a simple feature-first structure until the app needs more:

```text
Trace/
  App/
  Features/
  Shared/
  Resources/
  Tests/
```

## Boundaries

- Each feature should own its screens and feature-specific state.
- Shared code must be genuinely reused or clearly cross-cutting.
- Services should expose small protocols only when abstraction is useful for testing or replacement.
- Avoid global singletons unless the system API requires it or the object is truly process-wide.

## Data Flow

- Prefer one-way data flow: state owner -> view -> action -> state update.
- Keep persistence, networking, and domain transformations outside SwiftUI views.
- Make side effects explicit and testable.

## Evolution

- Start simple.
- Do not introduce modularization, dependency injection containers, or custom architecture frameworks before the app needs them.
- Document architecture decisions that affect future work in `docs/agent-rules/project-decisions.md`.
