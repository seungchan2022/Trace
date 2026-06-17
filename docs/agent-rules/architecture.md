# Architecture Rules

## Default Shape

Use page-first MVVM presentation with Clean Architecture boundaries. Keep the
project in one Xcode target for now, but structure folders so the same
boundaries can later become Swift Package modules:

```text
Trace/
  App/
    TraceApp.swift
    DependencyContainer.swift

  Domain/
    {DomainName}/
      Entity/
      Protocol/
      {DomainName}Error.swift

  Application/
    {DomainName}/
      {Action}UseCase.swift

  Infrastructure/
    {DomainName}/
      {Provider}/
        {Provider}{DomainName}Service.swift

  Pages/
    {PageName}Page/
      {PageName}Page.swift
      {PageName}PageViewModel.swift
      UIComponent/
        {PageName}Page+{Role}Component.swift

  Resources/
  Tests/
```

Example for Trace course planning:

```text
Trace/
  Domain/
    CoursePlanning/
      Entity/
        CourseCoordinate.swift
        PlannedCourse.swift
      Protocol/
        CoursePlanningServiceProtocol.swift
      CoursePlanningError.swift

  Application/
    CoursePlanning/
      PlanCourseUseCase.swift

  Infrastructure/
    CoursePlanning/
      MapKit/
        MapKitCoursePlanningService.swift

  Pages/
    CoursePlannerPage/
      CoursePlannerPage.swift
      CoursePlannerPageViewModel.swift
      UIComponent/
        CoursePlannerPage+StatusComponent.swift
```

## Clean Architecture Baseline

- Treat UI, presentation, domain policy, and infrastructure as separate concerns even while the app is still a single Xcode target.
- Keep domain decisions independent from SwiftUI, networking clients, persistence frameworks, and platform-specific APIs.
- Use cases should express app behavior in plain Swift types and depend on protocols, not concrete infrastructure.
- Infrastructure implementations belong behind service, repository, or adapter protocols.
- DTOs are for transport or persistence boundaries; map them into app/domain models before they reach presentation logic.
- Entities and domain models should not import SwiftUI.
- ViewModels may coordinate use cases and presentation state, but should not contain networking, persistence, or Keychain implementation details.

## Layer Responsibilities

- `App` is the composition root: app entry point, dependency wiring, launch mode selection, and app-wide environment setup.
- `Domain` owns app concepts and contracts. Put domain models under `Entity/`, port protocols under `Protocol/`, and app-meaningful domain errors next to that domain.
- Domain protocols should use the `Protocol` suffix when it improves readability in this project, for example `CoursePlanningServiceProtocol`.
- `Application` owns use cases. Use cases express user/app workflows and depend on domain protocols, not concrete infrastructure.
- `Infrastructure` owns external technology adapters: MapKit, network APIs, persistence, keychain, files, SDKs, and provider-specific mappers.
- `Pages` owns SwiftUI pages and page-specific ViewModels. A page ViewModel may call use cases or, for simple MVP flows, a domain protocol directly until a use case earns its place.

## Boundaries

- Each page should own its screen and page-specific state.
- Page Views should not create concrete services directly.
- Page ViewModels should depend on use cases or protocol abstractions.
- Page boundaries should be clear enough that a page can later move into its own Swift Package with minimal changes.
- Shared domain concepts should live in `Domain`, not in a catch-all shared folder.
- Infrastructure services should implement small domain protocols only when abstraction is useful for testing or replacement.
- Avoid global singletons unless the system API requires it or the object is truly process-wide.
- Avoid cross-page imports unless the dependency is intentionally promoted to `Domain`, `Application`, `Infrastructure`, or a future package.

## Page Components

- Keep page entry files focused on assembling the page.
- Put page-only subviews under `Pages/{PageName}Page/UIComponent/`.
- Name page component files `{PageName}Page+{Role}Component.swift`.
- Component types should make their page ownership obvious, for example `CoursePlannerPage.StatusComponent` or `CoursePlannerPageStatusComponent`.
- Promote a component out of `UIComponent` only when it is reused by another page or becomes a design-system-level element.

## Data Flow

- Prefer one-way data flow: state owner -> view -> action -> state update.
- Keep persistence, networking, and domain transformations outside SwiftUI views.
- Make side effects explicit and testable.
- Keep DTOs, entities, mappers, services, and adapters separated when the boundary matters.
- Keep data mapping at boundaries: API DTO -> domain/app model -> view state.

## Dependency Container

- Register app-wide dependencies in `DependencyContainer`.
- Inject use cases or protocol-typed services into ViewModels.
- Keep concrete implementations in `Infrastructure`, not in Views.
- The container composes dependencies at app or page entry points; it should not become a global service locator used from arbitrary code.

## Future Modularization

- Write code as if `Domain`, `Application`, `Infrastructure`, and `Pages` may later become Swift Package targets.
- Keep public APIs small and intentional. Prefer `internal` until a type truly crosses a module boundary.
- Avoid circular dependencies between pages, use cases, domain, and infrastructure.
- Keep resources and generated files organized so they can be moved with their page or infrastructure adapter later.
- If a new dependency would be needed only by one provider, keep its usage inside that provider's infrastructure adapter.
- A likely module split is `TraceDomain`, `TraceApplication`, `TraceInfrastructure{Provider}`, `TracePages`, and `TraceApp`.

## Evolution

- Start simple, but preserve boundaries that make modularization possible.
- Do not introduce actual multi-package modularization or custom architecture frameworks before the app needs them.
- Document architecture decisions that affect future work in `docs/agent-rules/project-decisions.md`.
