# Project Decisions

This file records defaults until the user chooses otherwise.

## Current Defaults

- App name: `Trace`
- Repository: `seungchan2022/Trace`
- Platform: iOS
- Language: Swift
- UI framework: SwiftUI
- Minimum iOS version: iOS 17+
- Presentation architecture: MVVM
- Dependency injection: `DependencyContainer` with protocol-based services
- Architecture direction: Clean Architecture boundaries inside a feature-first app
- Modularization: not active yet, but code should be structured so features and shared layers can later move into Swift Package modules
- Persistence: undecided
- Backend: none by default
- Authentication: none by default
- Analytics: none by default
- Monetization: none by default

## Decisions the User May Need to Make Later

- What problem the app solves
- Main user flow
- Whether data is local-only or synced
- Whether login is required
- Privacy constraints
- Minimum supported iOS version
- App icon/name/subtitle
- Whether TestFlight, App Store release, or private use is the target

## Decision Policy

- If a decision affects architecture, privacy, persistence, account creation, cost, or App Store behavior, ask the user.
- If a decision is only local code style or project organization, choose the documented default and update this file.
