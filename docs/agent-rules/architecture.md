# Architecture Rules

## Default Shape

Use a feature-first MVVM structure that follows Clean Architecture boundaries and can be split into modules later:

```text
Trace/
  App/
  Features/
    {Feature}/
      Views/
      ViewModels/
      Models/
      UseCases/
  Core/
  Services/
  Shared/
  Resources/
  Tests/
```

## Clean Architecture Baseline

- Treat UI, presentation, domain policy, and infrastructure as separate concerns even while the app is still a single Xcode target.
- Keep domain decisions independent from SwiftUI, networking clients, persistence frameworks, and platform-specific APIs.
- Use cases should express app behavior in plain Swift types and depend on protocols, not concrete infrastructure.
- Infrastructure implementations belong behind service, repository, or adapter protocols.
- DTOs are for transport or persistence boundaries; map them into app/domain models before they reach presentation logic.
- Entities and domain models should not import SwiftUI.
- ViewModels may coordinate use cases and presentation state, but should not contain networking, persistence, or Keychain implementation details.

## Boundaries

- Each feature should own its screens and feature-specific state.
- Feature Views should not create concrete services directly.
- Feature ViewModels should depend on protocol abstractions.
- Feature boundaries should be clear enough that a feature can later move into its own Swift Package with minimal changes.
- Shared code must be genuinely reused or clearly cross-cutting.
- Services should expose small protocols only when abstraction is useful for testing or replacement.
- Avoid global singletons unless the system API requires it or the object is truly process-wide.
- Avoid cross-feature imports unless the dependency is intentionally promoted to `Shared`, `Core`, or a future package.

## Data Flow

- Prefer one-way data flow: state owner -> view -> action -> state update.
- Keep persistence, networking, and domain transformations outside SwiftUI views.
- Make side effects explicit and testable.
- Keep DTOs, entities, mappers, services, and adapters separated when the boundary matters.
- Keep data mapping at boundaries: API DTO -> domain/app model -> view state.

## Dependency Container

- Register app-wide dependencies in `DependencyContainer`.
- Inject protocol-typed services into ViewModels.
- Keep concrete implementations in `Services` or adapters, not in Views.
- The container composes dependencies at app or feature entry points; it should not become a global service locator used from arbitrary code.

## Future Modularization

- Write code as if `Features`, `Core`, `Services`, and `Shared` may later become Swift Package targets.
- Keep public APIs small and intentional. Prefer `internal` until a type truly crosses a module boundary.
- Avoid circular dependencies between features, services, and shared utilities.
- Do not let `Shared` become a dumping ground. Move code there only when two or more features need it or when it defines a stable cross-cutting boundary.
- Keep resources and generated files organized so they can be moved with their feature later.
- If a new dependency would be needed only by one feature, keep its usage inside that feature or its infrastructure adapter.

## Evolution

- Start simple, but preserve boundaries that make modularization possible.
- Do not introduce actual multi-package modularization or custom architecture frameworks before the app needs them.
- Document architecture decisions that affect future work in `docs/agent-rules/project-decisions.md`.
