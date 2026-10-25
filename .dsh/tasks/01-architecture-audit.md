# Task 01 — Architecture & convention audit of the Sure checkout

**Owner:** rails-architect
**Dependencies:** none
**Write scope:** `.dsh/tasks/01-architecture-report.md` (only this file)

## Goal

Produce the ground truth another agent needs to write correct Sure code without re-discovering the
repository. This is a **read-only audit of the application code**; you must not modify any file under
`app/`, `config/`, `db/`, `lib/`, `test/`, or `spec/`.

## Required reading

- `docs/llm-guides/architecture.md`
- `docs/llm-guides/README.md` (index — read the guides relevant to money, transactions, providers)
- `AGENTS.md` (already in your context)

## What to report (use short verbatim excerpts + `path:line` references)

1. **Financial data model**
   - How monetary amounts are represented: integer cents vs `decimal` columns. Find the actual
     schema lines in `db/schema.rb` for the core money columns (entries/transactions, accounts,
     balances, holdings, trades).
   - The helper/concern that converts money in and out of the DB (e.g. `Money`, `Moneyizable`,
     `has_many` balance caches). Give the module name, path, and the exact method names.
   - Which columns are cached aggregates (e.g. account balance, valuation) and which job/concern
     keeps them fresh. Name the job classes.
   - Currency handling: how multi-currency accounts store currency, any FX rate model/table, and how
     conversion is performed.

2. **Tenancy and authorization**
   - How `Current.user` / `Current.family` are set, where tenancy is enforced, and the model
     concern(s) that scope records to a family.
   - The authorization mechanism used in controllers (Pundit? custom?) and one representative
     example.

3. **Request/routing conventions**
   - Controller base classes, the standard RESTful controller shape, how Turbo Frames/Streams are
     used in an existing feature (give one concrete example: route → controller action → view/erb →
     turbo frame id).
   - Where Stimulus controllers live and one representative controller with its `data-controller`
     usage.

4. **Testing conventions**
   - Minitest layout under `test/`, fixture conventions, how tests set up a family/user, and how
     provider or network calls are stubbed (VCR/Mocha). Give one representative test file path and
     the setup pattern.
   - The exact commands used for: full test suite, a single test file, lint (RuboCop), ERB lint,
     Biome, Brakeman. Read `docs/llm-guides/development.md` and `docs/llm-guides/testing.md`.

5. **UI component conventions**
   - What lives in `app/components/` (ViewComponent? Phlex?) and the `DS::*` primitive inventory
     (list the available `DS::` components).
   - The Tailwind design-token rule source: `app/assets/tailwind/sure-design-system.css` — list the
     functional token class families an author is expected to use, and confirm which classes are
     forbidden.

## Deliverable

Write `.dsh/tasks/01-architecture-report.md`, max ~250 lines, structured under the five headings
above. Every non-obvious claim must cite `path:line`. Do not speculate: if something is absent, say
so explicitly (e.g. "no such model exists in db/schema.rb").

When done, reply to the lead with: file path written, the 5 most important facts, and anything you
could not determine.
