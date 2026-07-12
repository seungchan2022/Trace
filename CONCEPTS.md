# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Course Planning

### Detent
One of three fixed height states a course-planning bottom sheet can rest at: collapsed (header only), medium (a capped list of segments), or full (fills down to just below the top safe area). Modeled after a system sheet's presentation detents, but implemented as a custom view rather than `.sheet(presentationDetents:)`. A detent's height never grows with content — more segments produce scrolling within the current detent, not a taller sheet. Detent transitions move one step at a time (collapsed↔medium↔full), never skipping a step.
