# Repository Guidelines

This guide describes how to contribute to the HalalFood iOS app. Keep changes focused, small, and explain decisions in PRs.

## Project Structure & Modules
- `HalalFood.xcodeproj` — Xcode project.
- `HalalFoodApp.swift`, `ContentView.swift` — app entry + main UI.
- `Core/` — models and UI helpers.
- `Assets.xcassets/` — colors, images, app icon.
- `data/`, `scripts/`, `supabase/` — dataset, import scripts, backend schema.

## Build, Test, Dev
- Build/Run: open the project in Xcode → pick a simulator → `Cmd+R`.
- Clean: `Shift+Cmd+K` if you don’t see changes.
- Format: Xcode Re‑Indent or `swift-format` if installed.
- Backend: iterate on SQL in `supabase/schema.sql` and apply via Supabase tooling.

## Coding Style & Naming
- Swift 5.9+, SwiftUI first. Prefer `struct` views and `private` helpers.
- Indentation: 4 spaces; aim for ≤100 chars/line.
- Naming: `PascalCase` types, `camelCase` vars/functions, `SCREAMING_SNAKE_CASE` constants.
- Colors: define in a theme; reserve green/orange strictly for halal‑status badges. Use neutrals/brand for navigation (tabs, search, etc.).

## Testing
- Add lightweight unit/ui tests when logic grows. Name tests `ThingNameTests.swift`.
- Keep fixtures small under `data/`. Prefer deterministic tests over broad coverage targets.

## Commits & PRs
- Commits: imperative present tense, optional scope prefix: `feat:`, `fix:`, `chore:`, `docs:`.
- Example: `feat(ui): off‑white bottom tab bar`.
- PRs: include intent, before/after screenshots for UI, steps to verify, and linked issues.

## Security & Config
- Never commit secrets. Use Xcode build settings or environment files ignored by Git.
- Be mindful of rate limits for 3rd‑party APIs.

## Agent Tips
- Keep views modular and previewable. Co-locate small components with their parents.
- If deviating from conventions (e.g., new folder layout), document the rationale in the PR.

