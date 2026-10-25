# Sure engineering standards

Mandatory for every agent session in this checkout. `AGENTS.md` is the repository contract;
this section is the operative rule set. Where the two overlap, one line here points at the
`AGENTS.md` topic instead of restating it.

## 1. Orientation

Sure is a Rails 8.1 + PostgreSQL personal-finance app (community fork of Maybe Finance),
all server-rendered HTML over Hotwire. Ruby code is under `app/`; schema is
`db/schema.rb:13` (`ActiveRecord::Schema[8.1]`), routes are `config/routes.rb`, tests
mirror `app/` under `test/`. Read `docs/llm-guides/architecture.md`,
`docs/llm-guides/development.md` and `docs/llm-guides/testing.md` before changing behavior.
Tenancy via `Current.family`, design tokens, and the API checklist are defined in
`AGENTS.md` — cross-reference, do not repeat them here.

## 2. Financial integrity

- **Never use Float for money.** Monetary columns are `decimal(19,4)`:
  `entries.amount` (`db/schema.rb:703`), `accounts.balance` (`db/schema.rb:102`),
  `balances.balance` (`db/schema.rb:257`), `holdings`/`trades` cost (`db/schema.rb:761`,
  `db/schema.rb:792`). Some provider mirrors use `decimal(34,18)` (`db/schema.rb:454`)
  or `decimal(10,2)` (`db/schema.rb:572`) — match the existing column, never widen it.
- **Convert money only through `monetize`.** Models declare `monetize :amount`
  (`app/models/entry.rb:9`) or `monetize :balance, :cash_balance` (`app/models/account.rb:40`),
  which defines `#<field>_money` returning `Money` (`app/models/concerns/monetizable.rb:5-13`).
  Use `entry.amount_money`, not arithmetic on the raw `BigDecimal` column, and never
  `Money.new` by hand outside the concern.
- **Never emit a float literal for money in code, tests, fixtures or seeds.** Write `12.34.to_d`,
  `BigDecimal("12.34")` or `"12.34"`; a bare `12.34` in a money assertion is a review-blocking defect.
- **Format server-side.** Money is rendered via `Money` / `lib/money.rb:1` formatting, not in
  JavaScript. Never pass a raw numeric amount to Stimulus for display.
- **Multi-currency: never assume the family currency equals the stored currency.**
  `Account`, `Entry`, `Balance` and `Holding` each carry their own `currency`
  (`db/schema.rb:106`, `db/schema.rb:705`, `db/schema.rb:263`). Convert with
  `ExchangeRate::Provided#find_or_fetch_rate(from:, to:, date:)`
  (`app/models/exchange_rate/provided.rb:14`), which caches dated rates and reuses a rate
  within `NEAREST_RATE_LOOKBACK_DAYS = 5` (`app/models/exchange_rate/provided.rb:12`).
  Never convert at "today" when the record has a `date`.
- **Treat conversion failure explicitly.** `Money::ConversionError`
  (`lib/money.rb:5`) is the signal; `Money` validates known source types
  (`lib/money.rb:19`). Do not swallow it into a zero.
- **Cached balances are derived, not authoritative.** `Account::CurrentBalanceManager` warns
  that an account with no current anchor falls back to the cached `account.balance`, "which may
  be out of date" (`app/models/account/current_balance_manager.rb:18-25`). Never treat that
  column as the source of truth.
- **`accounts.balance` has exactly four traced writers — use one, never add a fifth.**
  `CurrentBalanceManager#set_current_balance` for a manual account
  (`app/models/account/current_balance_manager.rb:40`, writing at `:47`) and its linked-account
  anchor path (`:141`), both `account.update!(balance: balance)`;
  `Balance::Materializer#update_account_info` (`app/models/balance/materializer.rb:55-58`),
  reached via `Account::Syncer#materialize_balances`
  (`app/models/account/syncer.rb:21-23`); and the IBKR preprocessor
  (`app/models/ibkr_account/processor.rb:227`). Never recompute this aggregate in a controller
  or view, and never `update_column` a balance.
- **Managers mostly create `Valuation` entries, not account writes.**
  `Account::ReconciliationManager#reconcile_balance` saves a valuation entry
  (`app/models/account/reconciliation_manager.rb:9`, `:17`) and `Account::OpeningBalanceManager`
  writes an opening anchor valuation (`app/models/account/opening_balance_manager.rb:30`, `:91`,
  `:103`). `Account::OpeningBalanceManager` and `Account::ReconciliationManager` are wired into
  account creation at `app/models/account.rb:215` and `:238` — but do not assume calling a
  manager has refreshed the cached column; only the four writers above do that.

## 3. Hotwire-first UI

- **Default to server-rendered HTML + Turbo Frames.** Turbo Frames are the normal
  page-section mechanism: `turbo_frame_tag dom_id(account, "entries")`
  (`app/views/accounts/show/_activity.html.erb:3`), lazy frames with `src:` + `loading: :lazy`
  (`app/views/accounts/_accountable_group.html.erb:16`). Reuse `dom_id`; never invent a
  frame id string when a record exists.
- **Turbo Streams enhance, they are not the sole dependency** (`docs/llm-guides/ui.md:11`).
  Reach for a stream only when a response must touch several DOM regions or broadcast;
  a single-region update is a Frame.
- **Stimulus is justified only for client-local interaction** where a server round trip hurts:
  bulk selection (`docs/llm-guides/ui.md:15-17`), toggles, drag/selection state. It is **not**
  justified for formatting money/dates, fetching data, or duplicating server validation.
- Declare Stimulus actions in HTML (`data-action="click->toggle#toggle"`), keep controllers
  under seven targets, and pass data via `data-*-value` rather than inline JS or
  `getElementById` (`docs/llm-guides/ui.md:32-41`). Component-scoped controllers live in
  `app/components/`, shared ones in `app/javascript/controllers/` (`docs/llm-guides/ui.md:38-39`).
- **Reuse `DS::*` before authoring markup.** 34 primitives exist in `app/components/DS/`
  (alert, button, card, dialog, disclosure, menu, pill, popover, select, table, tabs, toggle,
  tooltip, …). Design tokens, the `icon` helper (`app/helpers/application_helper.rb:35`),
  `t()` localization and the no-raw-SVG rule are the `AGENTS.md` "UI changes" topic.
- **No React/Vue/Svelte, no new JS build dependency, no new npm package** for a UI change.
  The asset pipeline and `app/javascript/` already cover the needs; a new dependency needs a
  strong technical reason recorded in the PR.
- Keep state in URL query parameters before session/local storage (`docs/llm-guides/ui.md:13`).
  Keep domain logic out of ERB (`docs/llm-guides/ui.md:22-23`).

## 4. Domain, services and jobs

- **Business logic lives in models, POROs and concerns — not controllers, not a service
  directory.** `docs/llm-guides/architecture.md:12-15` is explicit: organize around a model
  trait and prefer `account.balance_series` to `AccountSeries.new(account).call`. Existing
  `app/models/account/*.rb` managers (`syncer.rb`, `reconciliation_manager.rb`,
  `opening_balance_manager.rb`, `current_balance_manager.rb`) are the pattern to extend.
  `app/services/` is reserved for cross-cutting infrastructure
  (`provider_loader.rb`, `api_rate_limiter.rb`), not business rules.
- **Controllers stay thin and RESTful.** Scope through the family and the existing
  account-access scopes (`docs/llm-guides/architecture.md:33-34`); never build an
  unscoped `Model.find(params[:id])`. Use strong parameters and existing filters.
- **Jobs extend `ApplicationJob`** (`app/jobs/application_job.rb:1`). Inherited behavior
  already commits before enqueue (`:14`), retries `ActiveRecord::Deadlocked` (`:16`) and
  discards `ActiveJob::DeserializationError` (`:17`) — do not re-add these.
- **Choose the existing queue; do not invent one.** `queue_as` is one of
  `:high_priority` (`app/jobs/sync_job.rb:2`), `:medium_priority`, `:low_priority` (the
  `ApplicationJob` default, `app/jobs/application_job.rb:18`) or `:scheduled`.
- **Jobs must be idempotent and pass records, not IDs.** Jobs receive GlobalIDs and are
  enqueued after commit; re-running a job must not double-post data. Use the existing
  `idempotency_key` / `external_id` uniqueness (`db/schema.rb:727-729`) rather than a
  read-then-write check.
- **Sidekiq is the queue backend here, not Solid Queue.** `Procfile.dev` runs
  `bundle exec sidekiq`, `Gemfile:35` pins `sidekiq`, and the adapter is set in
  `config/environments/production.rb:113`. Do not add Solid Queue, and do not assume
  `solid_queue_*` tables exist.
- **Long, third-party or batch work never runs in the request cycle.** Provider sync,
  imports, AI calls and bulk rules go to jobs — `SyncJob` (`app/jobs/sync_job.rb:5`),
  `ImportJob`, `ApplyAllRulesJob`, `AutoCategorizeJob`.
- **Provider failures are recorded with `DebugLogEntry.capture`** (`app/models/debug_log_entry.rb:38`),
  with `category:`, `level:`, `message:`, `source:` and provider/family/account context
  (`app/models/debug_log_entry.rb:25-34`). It swallows its own errors (`:40-42`), so capture is
  always safe. It never replaces raising a real exception.
- **Validation belongs in both layers.** Simple null checks and uniqueness go in the database
  and may be mirrored in ActiveRecord for form errors; complex rules stay in Ruby
  (`docs/llm-guides/architecture.md:20-22`). If a DB check constraint exists, mirror it with a
  model validation so the user sees a validation error, not `StatementInvalid` — the pattern at
  `app/models/entry.rb:17-19` (paired with `chk_entries_reconciled_at_present_when_statement_set`).

## 5. Database and performance

- **Every foreign key and hot lookup needs an index.** The repo is index-dense: `account_id`,
  `date` and the partial unique indexes on `entries` (`db/schema.rb:725-735`), including the
  scoped unique indexes on `idempotency_key` and `(source, external_id)` (`:727`, `:729`) and
  the transfer-match index (`:731`). Add a matching index in the same migration that adds the column.
- **Avoid N+1.** Controllers eager-load what they render —
  `app/controllers/accounts_controller.rb:17` and `:22-34` chain `.includes(...)`. Any loop
  touching an association must be preloaded; prefer `includes` over manual caching.
- **Use JSONB for provider payloads and flexible attributes** (`db/schema.rb:196-197`,
  `:291-292`, `:427`), never for money. Do not add a JSONB column when a typed column exists.
- **Time series belong in SQL, not Ruby loops.** `start_balance`, `end_balance`,
  `end_cash_balance` and `end_non_cash_balance` are **stored generated columns** on `balances`
  (`db/schema.rb:265-274`). Do not recompute them in Ruby; aggregate in the query, and prefer
  the `account.balance_series`-style API over ad-hoc `map`/`sum` over loaded entries.
- **Migrations:** declare the current Rails version — `ActiveRecord::Migration[8.1]`, matching
  `db/schema.rb:13` and the newest migrations (e.g.
  `db/migrate/20261014000100_add_fire_variant_to_planning_settings.rb:1`). Never edit an
  historical migration, never edit `db/schema.rb` by hand, and never run `db:migrate`
  automatically — `AGENTS.md` already forbids auto-migration and server starts; that rule stands.
- Adding a column to a large table needs a `null: true` default or a `change_column_default`
  follow-up; do not add a non-null column with a volatile default in one step.

## 6. Testing and verification

- **Minitest + fixtures only.** Mirror `app/` under `test/`, name files `*_test.rb`, keep
  fixtures to two or three per model. No RSpec behavioral tests, no factories —
  RSpec/rswag is documentation-only (`docs/llm-guides/testing.md:3-8`).
- **Always cover:** balance updates (anchor and cached path), money conversion round-trips,
  categorization/rule application, transfer matching, provider sync idempotency. Edge cases that
  matter: zero, negative (inflow) amounts, foreign currency, missing exchange rate, and a
  split/locked entry that must not be mutated.
- Use Mocha for stubs (`OpenStruct` for mocks) and VCR with existing cassettes in
  `test/vcr_cassettes/` for external APIs; keep credentials out of recordings
  (`docs/llm-guides/testing.md:17-22`). Same-currency transfer amounts must be equal and
  opposite (`docs/llm-guides/architecture.md:78`).
- Never weaken or delete an existing assertion to make a change pass; a red test is evidence,
  not an obstacle.
- System tests only for critical flows, and rerun them when ERB or Turbo changed.

## 7. Pre-flight checklist

Before claiming a task is done, confirm each item and report the command output:

1. `db/schema.rb` and `config/routes.rb` were read, and any schema claim cites a real line.
2. No `Float` reaches money: grep your diff for money math without `_money`, `.to_d` or `Money`.
3. Balance/cached-aggregate writes go through the manager or syncer, not `update_column`.
4. Every new/changed FK or lookup column has an index in the same migration.
5. Turbo Frame id reuses `dom_id`; any new Stimulus controller is justified and under seven targets.
6. `DS::*` reuse checked; no raw palette class, hex literal, raw SVG or untranslated string.
7. No `TODO`, placeholder, commented-out block or stub left in production code.
8. Behavioral tests added for the changed behavior, and none deleted or weakened.
9. `bin/rails test` is green.
10. Lint, format and security checks pass, and the migration command below was run only if the
    user explicitly requested environment work.

Commands:

```
bin/rails test
bin/rails test test/models/account_test.rb:42
DISABLE_PARALLELIZATION=true bin/rails test:system
bin/rubocop -f github -a
bundle exec erb_lint ./app/**/*.erb -a
npm run lint
npm run format:check
bin/brakeman --no-pager
```

## 8. Command reference

Every command below is verified against this checkout.

| Purpose | Command | Source |
| --- | --- | --- |
| Full behavioral suite | `bin/rails test` | `docs/llm-guides/development.md:23` |
| Single file / single line | `bin/rails test test/models/account_test.rb:42` | `docs/llm-guides/development.md:24` |
| System tests | `DISABLE_PARALLELIZATION=true bin/rails test:system` | `docs/llm-guides/development.md:26` |
| Ruby lint (+safe autocorrect) | `bin/rubocop -f github -a` | `docs/llm-guides/development.md:45` |
| ERB lint | `bundle exec erb_lint ./app/**/*.erb -a` | `docs/llm-guides/development.md:46` |
| Biome lint / format check | `npm run lint` / `npm run format:check` | `package.json:11`, `package.json:13` |
| Security analysis | `bin/brakeman --no-pager` | `docs/llm-guides/development.md:49` |
| Run migrations | `bin/rails db:migrate` | `docs/llm-guides/development.md:21` |
| Prepare database | `bin/rails db:prepare` | `docs/llm-guides/development.md:21` |
| Roll back / seed | `bin/rails db:rollback` / `bin/rails db:seed` | `docs/llm-guides/development.md:22` |
| Demo dataset | `bin/rails demo_data:default` | `lib/tasks/demo_data.rake:37` (alias `sample_data:default`, `:85`) |
| Start dev processes | `bin/dev` (web + Tailwind watcher + Sidekiq) | `docs/llm-guides/development.md:19`, `Procfile.dev` |
| Console | `bin/rails console` | `docs/llm-guides/development.md:20` |

**Environment work is opt-in.** `bin/rails db:migrate`, `db:prepare`, `db:seed`,
`demo_data:default`, `bin/dev` and `bin/setup` are references, **not** permission — run them
only when the user explicitly asked for that environment change. `bin/setup` prepares the
database and restarts the app and is never a read-only check
(`docs/llm-guides/development.md:11-14`). Never start a Rails server, never touch
`tmp/restart.txt`, never run `rails credentials`.

**Unverified:** no command in this section was executed during drafting (read-only task); every
one was confirmed to exist by reading the cited file or `bin/`. `bin/dev` was verified from
`Procfile.dev` and the guide, not by running it.
