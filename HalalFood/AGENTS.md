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
- Backend schema: use Supabase migrations under `supabase/migrations/` and regenerate `database.types.ts`.

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
- New Yelp spots require a follow-up CLI step (needs Supabase service key + `YELP_API_KEY`):
  1. Generate `HalalFood/data/yelp_halal.json` locally (do not commit), then run:
     `node scripts/yelp_ingest.js --file=HalalFood/data/yelp_halal.json --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY`
  Yelp photos now load via the edge proxy; do not run `yelp_photos_ingest.js`.

## Contributing / Working With Supabase (LLM-first)

This project uses Supabase. I use an LLM (Codex) to do most backend work for me.

### The objective
- Make backend changes safe, repeatable, and easy for AI.
- The repo should contain the Supabase backend definition (migrations + types).
- The AI can also use Supabase MCP for live context/debugging.
- Avoid "mystery changes" that only exist in the dashboard and aren't saved anywhere.

### What's in this repo
- `supabase/migrations/` = database changes as SQL files (tables, columns, RLS policies, functions, triggers).
- `supabase/functions/` = Edge Functions (if any).
- `database.types.ts` = TypeScript types generated from the DB.
- `.env.example` = placeholder env var names (no real values).
- `.env.local` (NOT committed) = real secrets on my machine.

### Simple rule (the default workflow)
When you change the database, always also change the repo. That means: every DB change should result in a committed migration file + updated `database.types.ts`.

If you (the LLM) make changes directly in Supabase (Dashboard or MCP), you must immediately follow up by making an equivalent migration file in `supabase/migrations/` and regenerating `database.types.ts`, then commit both.

### When to use MCP vs repo
Use MCP when:
- you need to inspect the live hosted database (schema, data, RLS behavior).
- you are debugging why something behaves differently in hosted vs local.
- you want to quickly answer "what exists right now?"

Use repo migrations when:
- you are implementing the actual backend change we want long-term.
- you are "locking in" changes so they aren't lost.

### Commands (Codex can run these)
- Pull current hosted schema into migrations (Docker required): `npm run db:pull`
- Generate types: `npm run types:gen`
- Apply migrations to hosted DB (dangerous: affects real project): `npm run db:push`

### Safety guardrails (because I'm a beginner)
- Prefer making DB changes via migrations in the repo.
- If you are about to run `db:push` (deploy DB changes), stop and print:
  1) which migrations will be applied
  2) what tables/policies/functions will change
  3) what could break
  Then proceed only if I explicitly say "push it".
- Do NOT put real secrets in committed files. Use `.env.local` for real values.

### Common blockers
- If `db:pull` fails with Docker errors: Docker runtime needs to be running and `docker ps` must work.

### Assistant defaults
You are my engineering assistant. I'm a beginner and you will do most of the work.

My goals:
1) Keep Supabase backend changes captured in this repo (migrations + `database.types.ts`).
2) Use MCP for live inspection/debugging when helpful.
3) Avoid changes that exist only in the dashboard and get lost.

Defaults:
- For long-term changes, implement them as SQL migrations under `supabase/migrations` and commit.
- After any schema change, regenerate and commit `database.types.ts`.
- Use MCP to inspect/debug the hosted DB or validate behavior.

When you choose MCP vs repo:
- Use MCP to answer "what exists / what's happening right now?" (schema, data, RLS behavior).
- Use repo migrations to implement the final change that should persist.

Allowed to use Supabase Dashboard or MCP:
- Yes, you can make changes directly via MCP/Dashboard if it's the fastest path.
- But if you do, you MUST immediately:
  1) mirror the change as a migration file in `supabase/migrations`
  2) regenerate `database.types.ts`
  3) commit those repo changes
  so the repo stays the source of truth.

Deploy safety:
- Before running `npm run db:push`, stop and summarize exactly what will change and what might break.
- Wait for me to explicitly say "push it" before applying migrations to the hosted project.

Secrets:
- Never commit secrets. Use `.env.local` (gitignored).
- `.env.example` should only contain empty placeholders.

Debugging:
- If there is mismatch between hosted behavior and repo/local behavior, use MCP to inspect, then fix via migrations in the repo.
