# Repository Guidelines

This document summarizes how to work on the HalalFood iOS app. Keep changes small, focused, and consistent with the patterns below.

## Project Structure & Module Organization
- `HalalFoodApp.swift` — app entry point (SwiftUI).
- `Core/Models/` — lightweight data and helpers.
- `Core/UI/` — app theming and SwiftUI views/components.
- `Assets.xcassets/` — app icons, colors, and images.
- `scripts/`, `data/`, `supabase/` — tooling, seed data, and backend schema.

## Build, Test, and Development Commands
- Run app: Xcode → select a simulator → `Cmd+R`.
- Format Swift: Xcode (Editor → Structure → Re‑Indent) or `swift-format` if installed.
- Backend schema: apply changes with Supabase CLI or via SQL in `supabase/schema.sql`.

## Coding Style & Naming Conventions
- Swift 5.9+, SwiftUI first. Use `struct` views and `private` helpers.
- Indentation: 4 spaces, no tabs. Line length target: 100.
- Names: `PascalCase` types, `camelCase` functions/vars, `SCREAMING_SNAKE_CASE` for constants.
- Colors: define in `Core/UI/Theme.swift`. Reserve green/orange strictly for halal status badges; use neutrals/brand for navigation and tabs.

## Testing Guidelines
- Prefer lightweight view previews and targeted unit tests when applicable.
- Name tests `<Type>NameTests.swift`. Keep fixtures small and checked in under `data/`.
- Aim for clear behavior checks over high coverage totals.

## Commit & Pull Request Guidelines
- Commits: present tense, imperative, scoped prefixes when useful: `feat:`, `fix:`, `chore:`, `docs:`.
- Example: `feat(ui): custom bottom tab bar`.
- PRs: include purpose, screenshots (before/after for UI), and linked issues. Keep PRs under ~300 lines of diff when possible.

## Security & Configuration Tips
- Never commit secrets. Use environment variables or Xcode build settings.
- Be cautious with third‑party APIs; rate limits can affect the app.

## Agent‑Specific Notes
- When adding files, follow directory scopes above so other agents can locate code quickly.
- If you must deviate from these conventions, explain the rationale in the PR description.

