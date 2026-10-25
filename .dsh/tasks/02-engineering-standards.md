# Task 02 — Sure engineering standards (the rule set the plugin will inject)

**Owner:** standards-writer
**Dependencies:** 01-architecture-audit (read `.dsh/tasks/01-architecture-report.md` before starting;
it may not exist yet — if it does not, do the work yourself from the same sources and say so)
**Write scope:** `.dsh/tasks/02-standards-draft.md` (only this file)

## Goal

Turn the Rails 8 / Hotwire / PostgreSQL standards brief below into a **short, mandatory, actionable
rule set** for this specific repository. This draft becomes the body of a Harness plugin that
injects these rules into every agent session working in the Sure checkout, so it must be:

- **specific** — names real classes, paths, column types, helper methods and commands that exist in
  this repo, verified against `db/schema.rb`, `app/models/`, `app/services/`, `config/routes.rb`
  and `docs/llm-guides/`;
- **enforceable** — each rule is checkable by reading a diff (do this / never do that);
- **concise** — target 1200–1800 words of Markdown; no filler, no restating generic Rails advice;
- **non-duplicative** — do not restate repository rules that `AGENTS.md` already carries (tenancy
  via `Current.family`, design tokens, API checklist). Instead cross-reference them in one line each.

## Source brief from the user

- **Tech stack:** Ruby on Rails 8, Active Record, Solid Queue / Active Job, RESTful APIs,
  Hotwire (Turbo Frames/Streams, Stimulus), PostgreSQL, Tailwind CSS.
- **Hotwire-first:** prefer server-driven HTML — Turbo Frames for partial page replacement, Turbo
  Streams for async/real-time DOM updates — over SPA frameworks or heavy client JavaScript.
- **Domain and data integrity:** business logic and validations primarily at the model and service
  layer; monetary values as strict decimal types or integer cents, **never floating point**.
- **Architecture:** thin, RESTful controllers; complex business processes, third-party integrations
  and batch operations go to service objects or background jobs; modular, testable code with
  complete error handling, strict input validation and fallback mechanisms.
- **Execution strategy:** verify `db/schema.rb`, `config/routes.rb` and model dependencies before
  changing code; complete, production-ready code with no placeholder comments; provide explicit
  terminal commands for migrations, bundle installs and service restarts.

## Required structure of the draft

1. **Orientation** (3–6 lines): what the project is, where the Rails code lives, which guide files
   to read first, and the note that this section is complementary to `AGENTS.md`.
2. **Financial integrity** — the hard rules: representation of money end to end (cite the actual
   column types and the conversion helper), rounding, multi-currency conversion, and the rule that
   aggregate/cached balances are updated through the existing job/concern path rather than ad-hoc
   recalculation in a controller.
3. **Hotwire-first UI** — Turbo Frame vs Turbo Stream decision rule, when a Stimulus controller is
   justified and when it is not, `DS::*` component reuse, design-token and `icon`/`t()` rules,
   no React/Vue/no new JS build deps without a strong reason.
4. **Domain, services and jobs** — where business logic lives, controller shape, job conventions
   (queueing, idempotency, retries, `DebugLogEntry.capture` for provider failures), validation in
   both model and DB constraint.
5. **Database and performance** — indexes on foreign keys and hot lookups, N+1 avoidance, JSONB and
   window-function usage for net-worth time series, migration rules (current Rails migration
   version, historical versions untouched, no auto-migrate).
6. **Testing and verification** — Minitest + fixtures, what must be covered (balance updates,
   categorization rules, multi-currency conversion edge cases), and the exact pre-PR command list.
7. **Pre-flight checklist** — a 6–10 item checklist an agent must run through before saying a task
   is done, ending with the concrete commands (`bin/rails test`, lint, Biome, Brakeman, and a
   migration command example).
8. **Command reference** — exact terminal commands for: running migrations, seeding demo data
   (`rake demo_data:default`), starting the dev server (`bin/dev`), and running the checks. Verify
   each command exists (read `docs/llm-guides/development.md`, `Procfile.dev`, `bin/`, `lib/tasks/`)
   and mark any command you could not verify.

## Constraints

- Do not edit any file other than your write-scope file.
- Do not start a Rails server, run migrations, or touch `tmp/restart.txt`.
- Use `path:line` citations for every repo-specific claim.
- Keep Ruby two-space indentation conventions in any code samples; never emit float-based money
  examples.

When done, reply to the lead with: the file path, its word count, the rule count, and every claim
you had to mark unverified.
