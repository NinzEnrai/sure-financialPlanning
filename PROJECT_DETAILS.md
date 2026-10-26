# PROJECT DETAILS — Sure Finance (NinzEnrai/sure-financialPlanning)

Comprehensive context document. Last updated: 2026-10-26.

**Resuming? Read §23 first.** It is the only section describing the current state;
everything from H1 onwards is a dated log, kept because the mistakes in it were
expensive to rediscover.

## 0. How to read this document

| Section | What it holds | Status |
| --- | --- | --- |
| §1–§18 | Identity, stack, deployment, models, API, file map | Reference. Accurate except where §23 says otherwise. |
| §19 | Stub pointing at §22 | — |
| §21 | Superseded pending list, plus what is genuinely still open | Live |
| §22 | **Master gotcha list** — read before touching anything | Live |
| §23 | Current state, the tax phase plan, owner actions | **Start here** |
| H1 | Log: 2026-10-25 — wealth graph fix, INR formatting half-wired | History |
| H2 | Log: 2026-10-25 later — INR complete, price providers wired | History |
| H3 | Log: 2026-10-26 — production Zerodha bring-up, six bugs | History |

Housekeeping on 2026-10-26: the historical logs were renumbered H1/H2/H3 because three
sections had been called §20, two §21 and two §22; the 41-item gotcha list in §19 was
deleted as a verbatim duplicate of §22's fuller copy; §22 was deduplicated from 50 to 44
entries and regrouped by area; and three stale claims were corrected — "uncommitted,
nothing pushed", "do not enable Yahoo Finance", and the old `jarvis.` callback URL.

## 1. Identity

- Repo: https://github.com/NinzEnrai/sure-financialPlanning
- Upstream: https://github.com/we-promise/sure (community fork of Maybe Finance)
- License: AGPLv3
- Framework: Ruby on Rails 8.1 (ruby 3.4.9)
- Stack: PostgreSQL 16, Redis 7, Sidekiq, Propshaft + Importmap (no JS bundler), Tailwind CSS v4, Stimulus, Turbo
- Auth: session cookies, Current.user / Current.family (never current_user)
- Multi-tenant: family_id scoping everywhere; Current.family

## 2. What Was Built (34 commits ahead of upstream, all pushed)

### Commit 1: 8bbd3be2e — Complete Zerodha Kite Connect integration
- Promoted out of wip/ into app/; migrations re-dated 20261013000100/20261013000200
- api_key/api_secret columns removed from DB (env vars instead)
- 4 missing concerns written (Provided, Unlinking, Importer, KiteAccount)
- Provider::KiteAdapter registered
- Routes, locales, views, Family::KiteConnectable, Settings>Providers panel wired
- KiteItem no longer includes Syncable; includes Encryptable
- KiteItem::Importer calls schedule_balance_syncs (0.0-balance fix)
- KiteItem#destroy_later uses DestroyableLater concern (was hand-rolled, didn't restore on enqueue failure)
- Credentials from env, not DB (pg_dump safety)
- Deleted Syncer + SyncCompleteEvent (dead code)
- Kite verified live: user LBS596, 15 equity + 3 MF holdings, balances ₹68,692.57 + ₹102,611.42

### Commit 2: 812eee982 — Count invested money as savings in the planning split
- FinancialPlanning::SavingsRate rewritten: invested, expenses, cash_savings, savings, percent (cash/income), total_percent (savings/income)
- IncomeStatement::InvestmentContributionsTotal query (reuses ScopedTransactionsQuery)
- New: FinancialPlanning::HoldingsCostBasisSeries — per-account latest date, FX-converted
- Two measures (recorded transfers + holdings cost basis delta), larger wins, never summed
- Cost basis (not market value) so price moves don't fake investing
- Expenses subtracts only recorded contributions (holdings-derived was never in expenses)
- Caps invested at income when income positive
- 41 model tests + 9 controller tests green

### Commit 3: 006a72bbf — Compound calculator sliders + FIRE assumptions form
- WealthProjector: growth_rate override, growth_rate_pct routes through override, final_balance_money, monthly_contribution_money
- projection endpoint accepts monthly_contribution + growth_rate_pct (BigDecimal, not Float)
- compound_calculator_controller.js — sliders, debounce, stale discard, fetch, render chart
- wealth_projection_chart_controller.js — added render() method
- FIRE assumptions form wired (withdrawal rate + growth rate)
- Fixed: growth_rate_pct was reading planning_setting directly, ignoring slider override
- Fixed: annuity term at zero growth (0/0 → NaN blanked chart)
- Fixed: positive_param parses as BigDecimal not Float (Float#to_s("F") raised)

### Commit 4: 98b0f0076 — Savings rate chart (solid + dashed)
- savings_rate_chart_controller.js — dual series, zero reference line, tooltip
- _savings_rate.html.erb — 12-month chart
- Fixed: BigDecimal → string in JSON made d3.max compare lexicographically → NaN. Fixed with toRate() coercion + server-side to_f
- locale keys for chart

### Commit 5: 1e8b845a3 — Bucket picker (category → needs/wants/savings)
- _bucket_picker.html.erb — disclosure with per-category select, auto-submit
- BudgetAnalyzer#bucketed_categories — all family categories, spending ones first
- update_bucket action: supports reset (deletes override key, not sentinel)
- PlanningSetting::RESET_BUCKET = "__default__"
- locale keys

### Commit 6: ad59913e3 — FIRE assumptions form and variants, incl. Coast FIRE
- Migration: fire_variant (string, default "standard"), fire_target_year (integer)
- PlanningSetting::FIRE_VARIANTS: lean/coast/barista/standard/fat with withdrawal rates
- FireProgress: coast_fire?, target_year, target_date, months_until_target_date, projected_balance_at_target_date, coast_on_track?
- WealthProjector: balance_after_months, balance_after_months_money (for Coast FIRE)
- _fire_progress.html.erb: variant select, target year (coast only), pill, coast rows
- fire_variant_controller.js — show/hide target year field
- Coast FIRE uses target YEAR (not age) — no birth date in schema, and age drifts
- locale keys for variants

### Commit 7: 966c6c82f — Cache-busting headers + PROJECT_DETAILS.md
- Cache-Control: no-store on financial_planning show + projection
- PROJECT_DETAILS.md added

### Commit 8: d94a8850f — Auto-deploy script + git hook
- bin/deploy — one-command deploy (pull, assets, migrate, restart)
- .githooks/post-merge — auto-runs bin/deploy after git pull
- core.hooksPath activation

### Commit 9: 0b6d57e57 — Donut pie chart + projection UX
- _budget_analyzer.html.erb — donut chart (replaces bar + progress bars)
- compound_calculator_controller.js — loading indicator, console.warn if chart not found
- _wealth_projector.html.erb — larger outcome figure, slider hint
- en.yml — slider_hint locale key

### Commit 10: b1065fc55 — Yahoo Finance hang risk reduction
- max_retries: 5 → 2
- retry_interval: 1.0 → 0.5
- timeout: 10 → 5 (all three Faraday clients)
- nil-guards in fetch_security_price and fetch_security_prices

### Commit 11: 68ff97df5 — Yahoo Finance test defaults update
- Updated test expectations to match new defaults

### Commit 12: a8375ff02 — Update PROJECT_DETAILS.md
- Updated with complete project status

## 3. Deployment Environment (LXC bare metal)

- Host: Proxmox LXC, hostname `sure`, IP 192.168.1.100
- Public URL: finance.lan (reverse proxy on another machine)
- App path: /opt/sure (NOW a git clone after conversion)
- Env file: /etc/sure/.env
- DB: postgres on 127.0.0.1, sure_production, user sure_user
- Redis: 127.0.0.1:6379
- Ruby: rbenv 3.4.9 at /root/.rbenv
- Web: puma 7.2.1 on 0.0.0.0:3000 (systemd `sure.service`, Restart=always)
- Worker: sidekiq 8.0.5 (systemd `sure-worker.service`)
- Gems: vendor/bundle (544MB, BUNDLE_DEPLOYMENT=1, BUNDLE_WITHOUT=development)
- Memory: ~385MB RSS for puma
- Build packages: build-essential libpq-dev git pkg-config libyaml-dev
- Tailwind v4.1.8, poppler-utils, libvips, jemalloc

### systemd units
- sure.service: ExecStartPre=/opt/sure/bin/rails db:prepare, ExecStart=/opt/sure/bin/rails server
- sure-worker.service: ExecStart=/opt/sure/bin/bundle exec sidekiq -e production
- EnvironmentFile=/etc/sure/.env
- RAILS_ENV=production, BUNDLE_DEPLOYMENT=1, BUNDLE_WITHOUT=development

### Critical env vars
- SECRET_KEY_BASE (must not change between deploys)
- POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, DB_HOST, DB_PORT
- REDIS_URL
- KITE_API_KEY, KITE_API_SECRET
- EXCHANGE_RATE_PROVIDER=frankfurter (was yahoo_finance — WRONG, fixed)
- SECURITIES_PROVIDER=yahoo_finance (price quotes, separate from FX)
- RAILS_SERVE_STATIC_FILES=true (was missing — caused broken UI)

### db:prepare trap
- db:prepare loads db/schema.rb when DB is empty, stamping schema_migrations without running
- Always verify with db:migrate:status after deploy

### Deploy procedure (now automated)
```bash
cd /opt/sure && git pull origin main
# bin/deploy runs automatically via post-merge hook
# Or run manually: bin/deploy
```
bin/deploy does: pull, tailwindcss:build, assets:precompile, db:migrate, restart both services, smoke test

## 4. Architecture Overview

### Financial Planning
- Route: /financial_planning (preview feature, requires preview_features_enabled)
- Controller: FinancialPlanningController
- Partials: _savings_rate, _budget_analyzer, _bucket_picker, _fire_progress, _wealth_projector
- Models: SavingsRate, BudgetAnalyzer, FireProgress, WealthProjector, HoldingsCostBasisSeries
- PlanningSetting model: buckets, category_buckets, fire_variant, fire_target_year, fire_withdrawal_rate_pct, annual_growth_rate_pct

### Kite/Zerodha
- 10th investment provider in Settings > Providers
- Models: KiteItem, KiteAccount, KiteItem::Importer/Provided/Unlinking
- Provider: Provider::KiteAdapter, Provider::Kite::HoldingsSync, MutualFundSync
- Controller: Kite::CallbacksController, Settings::KiteConnectionsController
- Routes: /kite/callback, /settings/kite_connections
- Credentials from env vars (KITE_API_KEY, KITE_API_SECRET)
- Daily manual login, no stored credentials/TOTP
- Not Syncable-scheduled (cron instead)

### Design System
- Functional tokens only: bg-container, text-primary, border-primary, bg-warning/10, text-destructive
- No raw Tailwind palette classes or hex literals
- DS::* primitives: Card, Pill, ProgressBar, Disclosure, Note, DetailRow, etc.
- icon helper, never lucide_icon directly
- t() for all user-facing strings
- Scale tokens, not arbitrary px

## 5. Key Models

### FinancialPlanning::SavingsRate
- income, invested, expenses, cash_savings, savings
- percent (cash/income), total_percent (savings/income)
- monthly_series(months:), trailing_rate(months:), average_monthly_savings(months:)
- invested = max(recorded transfers, holdings cost basis delta), capped at income

### FinancialPlanning::HoldingsCostBasisSeries
- Per-account latest date (not shared date)
- Converts to family currency via ExchangeRate.rates_for
- Falls back to rate=1 with logged warning if no rate found

### FinancialPlanning::BudgetAnalyzer
- 3 buckets: needs, wants, savings
- TARGET_SHARE_PCT: needs 50%, wants 30%, savings 20%
- Category → bucket via PlanningSetting#bucket_for (prefers override)
- buckets, spend_by_category, unassigned_categories, bucketed_categories
- on_track? (needs/wants are ceilings, savings is floor)

### FinancialPlanning::FireProgress
- Target = average annual expenses / withdrawal rate
- Variants: lean (3.3%), coast (4.0%, target_year), barista (6.5%), standard (4.0%), fat (3.0%)
- Coast FIRE: target year, projected balance at target date, coast_on_track?
- percent, bar_percent (capped 100), remaining, achieved?, months_to_target
- Simulator uses WealthProjector

### FinancialPlanning::WealthProjector
- 10-year projection from current net worth
- opening_balance, monthly_contribution, growth_rate
- points (year 0 = today, years 1-10)
- final_balance, monthly_contribution, growth_rate_pct
- months_to_target(target) — geometric closed form
- balance_after_months(months) — for Coast FIRE
- growth_rate_pct handles zero growth (annuity term becomes annual * offset)
- growth_rate override from caller (for calculator)

### PlanningSetting
- BUCKETS = %w[needs wants savings]
- TARGET_SHARE_PCT = { "needs" => 50, "wants" => 30, "savings" => 20 }
- DEFAULT_BUCKETS: category i18n key → bucket mapping
- category_buckets: JSONB overrides keyed by category id
- bucket_for(category, key:): prefers override, falls back to default
- bucket_override?(category)
- FIRE_VARIANTS, DEFAULT_FIRE_VARIANT = "standard"
- fire_variant, fire_target_year, fire_withdrawal_rate_pct, annual_growth_rate_pct
- fire_target_money(annual_expenses), fire_multiple, growth_rate
- coast_fire?, needs_target_age? (now needs_target_year?)
- RESET_BUCKET = "__default__"

### KiteItem
- includes Provided, Unlinking, Encryptable (NOT Syncable)
- filter_attributes on api_key/api_secret
- has_many :kite_accounts (dependent: :destroy)
- scopes: active, syncable, ordered, needs_update
- destroy_later via DestroyableLater concern
- status: requires_update, etc.

## 6. Frontend Architecture

### JS Controllers (new/modified)
- compound_calculator_controller.js — sliders, debounce, stale discard, fetch, render chart
- savings_rate_chart_controller.js — dual series (solid + dashed), zero reference line, tooltip
- fire_variant_controller.js — show/hide target year field
- wealth_projection_chart_controller.js — modified: added render() method for calculator
- auto_submit_form_controller.js — reused for bucket picker

### Design System
- Functional tokens only: bg-container, text-primary, border-primary, bg-warning/10, text-destructive
- No raw Tailwind palette classes or hex literals
- DS::* primitives: Card, Pill, ProgressBar, Disclosure, Note, DetailRow, etc.
- icon helper, never lucide_icon directly
- t() for all user-facing strings
- Scale tokens, not arbitrary px

## 7. API Endpoints

### Financial Planning
- GET /financial_planning — show (HTML, preview-gated)
- GET /financial_planning/projection — JSON: years, balances, balance_labels, final_balance, final_balance_label, monthly_contribution, growth_rate_pct, currency
- PATCH /financial_planning/bucket — params: category_id, bucket
- PATCH /financial_planning/setting — params: planning_setting[fire_variant, fire_target_year, fire_withdrawal_rate_pct, annual_growth_rate_pct]

### Kite
- GET /kite/callback — receives request_token from Zerodha
- Settings::KiteConnectionsController — require_admin!, no credential form
- Settings::ProvidersController — kite panel

## 8. Environment Variables

### Required (LXC)
- KITE_API_KEY=<redacted — see /etc/sure/.env>
- KITE_API_SECRET=<redacted — see /etc/sure/.env; rotate, see §12>
- EXCHANGE_RATE_PROVIDER=frankfurter (without this, all currencies convert at rate 1)
- SECRET_KEY_BASE (must not change between deploys)
- POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, DB_HOST, DB_PORT
- REDIS_URL
- RAILS_SERVE_STATIC_FILES=true (was missing — caused broken UI)

### Optional
- SECURITIES_PROVIDER=yahoo_finance (price quotes — hangs, avoid for now)
- YAHOO_FINANCE_MAX_RETRIES (default 2, was 5)
- YAHOO_FINANCE_RETRY_INTERVAL (default 0.5, was 1.0)
- TWELVE_DATA_API_KEY
- OPENAI_ACCESS_TOKEN, OPENAI_URI_BASE, OPENAI_MODEL
- OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_ISSUER
- WEBAUTHN_RP_ID, WEBAUTHN_ALLOWED_ORIGINS

## 9. Database

### Migrations
- 20261013000100_add_indian_market_support.rb
- 20261013000200_create_kite_items_and_accounts.rb
- 20261014000100_add_fire_variant_to_planning_settings.rb

### Schema changes
- planning_settings: +fire_variant (string, default "standard", not null), +fire_target_year (integer, nullable)
- planning_settings: +category_buckets (jsonb, default {})
- kite_items table: api_key/api_secret columns REMOVED (env vars instead)
- kite_items: +scheduled_for_deletion, +access_token, +status, etc.
- kite_accounts table
- account_provider_id on holdings
- provider Securities provider support (Indian market)

### Critical trap
db:prepare loads db/schema.rb instead of running migrations when DB is empty — stamps schema_migrations without running. Always verify with db:migrate:status.

## 10. Tests

- Minitest + fixtures (not RSpec, except rswag for OpenAPI)
- Financial planning: 87 tests, 248 assertions, 0 failures
- Kite: kite_item_test, kite_account_test
- Full suite: 11,673 runs, 53,600 assertions
- 8 pre-existing failures (all Windows CRLF or Snaptrade float precision)
- My work introduced 0 new failures

## 11. Known Issues / Gotchas

1. Docker crashes (ENOMEM) — host memory
2. Tailscale serve config lost on restart
3. db:prepare stamping trap
4. Kite tokens day-scoped; stuck pending Sync blocks sync_later forever
5. EXCHANGE_RATE_PROVIDER must be set or silent rate-1 conversion
6. Family#balance_sheet memoizes per user and survives reload
7. Windows CRLF: core.autocrlf=true, .gitattributes doesn't cover *.pdf/*.tt
8. Yahoo Finance price provider hangs (>15 min)
9. XIRR + Indian capital gains blocked (need Zerodha Nextra for history)
10. Family currency was USD, switched to INR
11. /opt/sure is now a git clone (was tarball)
12. sure.creds is plaintext with DB password (security concern)
13. /opt/sure-old is a March 2026 deploy (Rails 7.2) — NOT a valid rollback
14. 512MB hosts: demo data generator OOMs
15. KiteItem#destroy_later was hand-rolled and didn't restore on enqueue failure — fixed
16. Compound calculator's growth_rate_pct was reading planning_setting directly — fixed
17. Savings rate chart NaN from BigDecimal→string in JSON — fixed
18. Wealth projection chart render() method added for calculator
19. Family#balance_sheet memoization survives reload — noted but not fixed
20. Yahoo Finance fetch_cookie_and_crumb makes requests that may hang
21. Reverse proxy at finance.lan caches aggressively — cache-busting headers added
22. SECURITIES_PROVIDER=yahoo_finance is set (price quotes, separate from FX) — may hang

## 12. Security Notes

- Kite credentials in env vars, not DB (pg_dump captures columns)
- .env.local is gitignored
- .env.local.example is clean (no secrets)
- api_secret was briefly in chat and .env.local.example — reverted, rotation recommended
- filter_attributes on KiteItem for api_key/api_secret
- Family tenancy preserved everywhere
- X-Api-Key auth pattern for API endpoints
- Brakeman clean (0 errors, 0 warnings)
- RuboCop clean on touched files
- Postgres password was exposed in chat and now also in this file's git history — rotate it and keep it only in /etc/sure/.env
- .env.example updated with Kite config documentation

## 13. What's NOT Built Yet

- Customisable 50/30/20 targets (only category assignment, not target %)
- XIRR + Indian capital gains (blocked on Zerodha Nextra)
- Visual verification of savings split by user (needs preview_features)
- Yahoo Finance full integration (reduced hang risk, needs testing)
- XIRR/tax UI (Portfolio::Xirr exists but isn't wired)
- Price history UI (Security::Price exists but no view)
- Document EXCHANGE_RATE_PROVIDER in .env.local.example

## 14. External Services

- Zerodha Kite Connect (broker API, daily manual login)
- Frankfurter (FX rates, free, keyless) — NOT the same as SECURITIES_PROVIDERS
- Yahoo Finance (securities prices — hangs, avoid for now)
- OpenAI-compatible LLM endpoint (optional)
- SimpleFIN, Plaid, SnapTrade (other providers, pre-existing)
- Twelve Data (default securities provider)

## 15. File Structure (key paths)

app/
  controllers/financial_planning_controller.rb
  controllers/kite/callbacks_controller.rb
  controllers/settings/kite_connections_controller.rb
  controllers/settings/providers_controller.rb
  javascript/controllers/
    compound_calculator_controller.js
    savings_rate_chart_controller.js
    fire_variant_controller.js
    wealth_projection_chart_controller.js
  models/financial_planning/
    savings_rate.rb
    budget_analyzer.rb
    fire_progress.rb
    wealth_projector.rb
    holdings_cost_basis_series.rb
  models/income_statement.rb
  models/income_statement/investment_contributions_total.rb
  models/kite_item.rb (+ importer, provided, unlinking)
  models/kite_account.rb
  models/provider/kite_adapter.rb
  models/provider/kite/{holdings_sync,mutual_fund_sync}.rb
  models/provider/yahoo_finance.rb
  models/planning_setting.rb
  views/financial_planning/
    show.html.erb
    _savings_rate.html.erb
    _budget_analyzer.html.erb
    _bucket_picker.html.erb
    _fire_progress.html.erb
    _wealth_projector.html.erb
config/locales/views/financial_planning/en.yml
db/migrate/20261013000100_*.rb
db/migrate/20261013000200_*.rb
db/migrate/20261014000100_*.rb
lib/indian_number_formatter.rb
bin/deploy
.githooks/post-merge
PROJECT_DETAILS.md
wip/kite/ (deleted Syncer, SyncCompleteEvent; README explaining removal)

## 16. API Endpoints (financial planning)

- GET /financial_planning — show (HTML, preview-gated)
- GET /financial_planning/projection — JSON: years, balances, balance_labels, final_balance, final_balance_label, monthly_contribution, growth_rate_pct, currency
- PATCH /financial_planning/bucket — params: category_id, bucket
- PATCH /financial_planning/setting — params: planning_setting[fire_variant, fire_target_year, fire_withdrawal_rate_pct, annual_growth_rate_pct]

## 17. How To Run Tests

```bash
docker build -f Dockerfile.test -t sure-test:work .
docker start suretest-postgres suretest-redis
docker run --rm --network suretest -v "/path/to/repo:/rails" -w /rails \
  -e RAILS_ENV=test -e DB_HOST=suretest-postgres -e DB_PORT=5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sure_test \
  -e REDIS_URL=redis://suretest-redis:6379/0 \
  sure-test:work bin/rails test <path>
```

## 18. Deployment (bare metal LXC)

- No Docker (docker crashed 7x due to ENOMEM)
- Services: sure.service (puma), sure-worker.service (sidekiq), systemd
- ExecStartPre: /opt/sure/bin/rails db:prepare (runs migrations on restart)
- EnvironmentFile: /etc/sure/.env
- Update: git pull origin main (now a git clone), bin/deploy auto-runs
- Need EXCHANGE_RATE_PROVIDER=frankfurter or silent rate-1 conversion
- Need KITE_API_KEY, KITE_API_SECRET in env
- Zerodha redirect URL: https://desktop-nt9v6sa.taildc6d46.ts.net/kite/callback
- Tailscale serve on port 3000 (Windows side)

## 19. Key Gotchas — moved

The 41-item gotcha list that used to sit here was a verbatim duplicate of §22,
which holds every one of those items plus nine more. §22 is the only copy that
is maintained; edit that one.

## 21. What's Pending

This list is superseded by §23.4 (owner actions) and §23.6 (build order). Kept only
so the history of decisions is not lost. What used to be here that is now **DONE**:
deploy to the LXC, git-pull deployment, Zerodha redirect URL, preview features,
XIRR/tax research (unblocked — see §23.3), Yahoo Finance (works; quota is the
constraint, not hangs), price history (backfilling nightly), `EXCHANGE_RATE_PROVIDER`
and `SECURITIES_PROVIDER` documentation notes.

Still genuinely open and not covered by §23:

- Visual verification of savings split by user (needs preview_features toggle).
- `Family#balance_sheet` memoization quirk (noted, not fixed).
- Customisable 50/30/20 targets (only category assignment, not target %).
- No UI for `Security::Price` history (rows exist, nothing renders them).
- 5 pre-existing CRLF test failures (Windows only, pass on Linux).
- Delete `/opt/sure-pre-git` on the LXC (frees ~544 MB).
- `kite_accounts.current_balance` is never written (the balance anchor replaced it).

## 22. Key Gotchas (master list)

Deduplicated 2026-10-26. Grouped by area rather than numbered by the order they
were discovered. The 50-item list this replaces repeated several entries.

**Conventions and tenancy**

1. Always use `Current.user` and `Current.family`, never `current_user` or `current_family`.
2. Family tenancy: every query must be scoped to `Current.family`.
3. `Current.user` and `Current.family` are set by middleware, not by controller helpers.

**Money and numbers**

4. `BigDecimal` rides through `#to_json` as a string — coerce with `.to_f` in views.
5. `Float#to_s("F")` raises — use `BigDecimal`.
6. `positive_param` parses as `BigDecimal` for exactly that reason.
7. `ExchangeRate.rates_for` falls back to rate = 1 with a logged warning when no rate exists.
8. `IncomeStatement::ScopedTransactionsQuery` joins exchange rates on the exact date with `COALESCE(er.rate, 1)`.
9. Indian lakh/crore grouping is applied in `ApplicationHelper#format_money` through `delimiter_pattern:`; only the integer part is regrouped and `precision:` still applies (see H2.1).

**Family statements**

10. `Family#balance_sheet` memoizes per user and survives `reload` — use `Family.find` for a fresh instance.
11. `Family#income_statement` is NOT memoized, unlike `balance_sheet`.

**Providers and market data**

12. Kite tokens are day-scoped; a stuck pending `Sync` blocks `sync_later` forever.
13. Kite `/trades` returns **only the current day's** tradebook — there is no historical endpoint. Purchase dates must come from a Console tradebook CSV (§23.3).
14. `holdings.cost_basis` is **per share**, not per position (`Holding#avg_cost`). `investment_statement` and `calculate_trend` multiply by qty.
15. Yahoo Finance works; the constraint is quota, not hangs. Production sets `SECURITIES_PROVIDERS=yahoo_finance,mfapi`; the old advice not to enable it is obsolete.
16. AMFI's `NAVAll.txt` answers 302 and plain Faraday will not follow it — `AmfiSchemeIndex` follows one hop by hand and never caches an empty index.
17. `ImportMarketDataJob` runs daily, after both the NSE close and AMFI publication.
18. `Account::MarketDataImporter` syncs the exchange rates foreign-currency accounts need.
19. `Security::Price` stores price history but has no UI.
20. `Security::Provided#find_or_fetch_price` and `#import_provider_prices` exist; a security with no explicit provider infers one from `amfi_scheme_code`, else `country_code == "IN"`.
21. A Kite sync runs on the `integrations` queue, which must be declared in `config/sidekiq.yml` — otherwise its jobs sit in Redis forever (§H3.2).
22. `DebugLogEntry.capture(...)` for support-relevant failures, with provider and family context.

**Accounts, trades and valuation**

23. Provider-linked accounts are excluded from `Account.manual`; anything that lists "your accounts" must query accounts directly, not `manual`.
24. A linked account's balance is reverse-calculated from its latest anchor. With no anchor it materializes to 0.00 and disappears from net worth.
25. `Portfolio::Xirr` and `Portfolio::FlowClassifier` are written, tested and **not wired to any view**.
26. `Trade#qty` is signed (negative = sell) and `Trade#price` is per unit; a `Trade`'s date lives on its `entries` row, not on `trades`.
27. `security_splits` must be applied before comparing per-unit costs, or a split reads as a loss.

**Planning figures**

28. `PlanningSetting#bucket_for` prefers the family override, then `DEFAULT_BUCKETS`.
29. `PlanningSetting::RESET_BUCKET = "__default__"` is a sentinel, not a bucket name.
30. `SavingsRate#invested` = max(recorded transfers, holdings cost-basis delta), capped at income when income is positive.
31. `SavingsRate#expenses` = `total_expenses` minus recorded contributions; `#cash_savings` = income minus `total_expenses`; `#savings` = `cash_savings + invested`.
32. `SavingsRate#percent` = `cash_savings / income`, `#total_percent` = `savings / income`; both nil when income is nil.
33. `WealthProjector#growth_rate_pct` routes through `growth_rate`; `#projected_balance` guards against zero growth; `#balance_after_months` projects a given month offset.
34. `FireProgress`: Coast FIRE uses the target **year** (there is no birth date in the schema), and `#months_until_target_date` is nil once that year has passed.
35. `FireProgress#coast_on_track?` compares the projection at the target date against the target; `#projected_balance_at_target_date` uses `balance_after_months`.
36. `PlanningSetting#fire_variant` defaults to `"standard"`; `#coast_fire?` checks for `"coast"`.
37. `PlanningSetting::FIRE_VARIANTS` has five variants; withdrawal rates: lean 3.3, coast 4.0, barista 6.5, standard 4.0, fat 3.0.
38. `HoldingsCostBasisSeries` uses each account's own latest date and converts through `ExchangeRate.rates_for`.
39. `BudgetAnalyzer#bucketed_categories` lists all family categories with their effective bucket; `#to_donut_segments` turns that into donut segments.

**Frontend**

40. `toRate()` in `savings_rate_chart_controller.js` coerces BigDecimal strings to numbers; without it the chart renders NaN.
41. `render()` in `wealth_projection_chart_controller.js` merges new data and redraws, and is only reachable when the chart element sits **inside** the controller element — a Stimulus target must be a descendant.
42. Donut colours: `d3.color("var(--token)")` returns null, so `donut_chart_controller.js` passes colours as strings through `.style()` instead of `.attr("fill")`. A null reaching `.opacity` blanked the whole donut.

**Environment**

43. `db:prepare` stamps `schema_migrations` without running migrations on an empty database.
44. The reverse proxy at `finance.lan` caches aggressively — use cache-busting headers.

---

# H1. Session Handoff (2026-10-25) — graph fix done, INR formatting half-wired

Written so a new session (a different model provider) could resume without
re-investigating. **Historical: this work was committed and pushed on 2026-10-25**
(4eccb66d and earlier); the paragraph below said otherwise at the time.

## H1.1 What is finished and verified

**Graph did not respond to sliders — FIXED.**
Root cause: in `app/views/financial_planning/_wealth_projector.html.erb`, the chart
`<div>` sat *outside* the element carrying `data-controller="compound-calculator"`
(the controller's wrapper closed just before it). A Stimulus target must be a
descendant of its controller's element, so `data-compound-calculator-target="chart"`
never resolved and `render()` was never called. The chart is now nested inside that
wrapper. Two range inputs also gained `autocomplete="off"` and the file gained a
trailing newline to satisfy ERB lint.

**Float precision in growth-rate math — FIXED.**
- `app/models/planning_setting.rb` — `growth_rate` now `BigDecimal(...) / 100`
  instead of `to_f / 100`.
- `app/controllers/financial_planning_controller.rb` — `ratio_param` now `/ 100`
  instead of `/ 100.0`.
The projector itself already used `BigDecimal` throughout.

**Verified results (Docker, image code — no Windows bind mount):**
- `bin/rails test` on financial-planning suite: **104 runs, 279 assertions, 0 failures, 0 errors**
- `bin/brakeman --no-pager`: **0 warnings, 0 errors**
- `bundle exec erb_lint _wealth_projector.html.erb`: **no errors**
- `bin/rubocop` on changed Ruby files: **no offenses**

**Caveat on what that covers.** Those runs happened AFTER the ERB fix and the two
BigDecimal edits, so those three are genuinely verified. The `Family::NUMBER_FORMATS`
constant and validation were added *after* that test run and are therefore **NOT yet
tested**. The next session must run the suite before trusting them. Risk is low — every
existing family gets the column default `"western"`, so the new inclusion validation
should pass — but it is unverified, not verified.

**`AGENTS.md`** — added a "Communication style" section (owner is not a professional
programmer; explain in plain language, define jargon, keep answers short).

## H1.2 What is INCOMPLETE

`families.number_format` (values `"western"` | `"lakh_crore"`, default `"western"`,
DB check constraint already exists from `db/migrate/20261013000100_add_indian_market_support.rb`).
`lib/indian_number_formatter.rb` already implements `.format` and `.compact`.
Nothing was consuming either yet. Steps 1–2 below are DONE; 3–7 are NOT.

1. **DONE** `app/models/family.rb` — added `NUMBER_FORMATS = %w[western lakh_crore].freeze`
   and `validates :number_format, inclusion: { in: NUMBER_FORMATS }` (next to the
   existing `date_format` validation).

2. **DONE** `lib/indian_number_formatter.rb` — already existed; unchanged.

3. **TODO** `app/controllers/users_controller.rb:117` — add `:number_format` to
   `family_attrs`. This is the actual save path; `Settings::PreferencesController#update`
   only writes *user* preferences and is NOT where family settings land.

4. **TODO** `app/helpers/application_helper.rb:186` — `format_money` currently does
   `Money.new(number_or_money).format(options)`. Add Indian grouping when
   `Current.family&.number_format == "lakh_crore"`. Recommended low-risk approach:
   pass `delimiter_pattern: INDIAN_GROUPING` through to `number_to_currency` rather
   than bypassing `Money`, so existing `precision:`/`format:` options keep working.
   Pattern: `/(\d+?)(?=(\d\d)+(\d)(?!\d))/` → `1,23,45,67,890`.

5. **TODO** `app/views/settings/preferences/show.html.erb:15` — add a
   `family_form.select :number_format, Family::NUMBER_FORMATS ...` next to the existing
   `:date_format` select. Note the form uses `data: { controller: "auto-submit-form" }`.

6. **TODO** `config/locales/views/settings/en.yml:191` — add label keys beside the
   existing `date_format:` key. Other locales can fall back to English for now.

7. **TODO** `app/javascript/controllers/wealth_projection_chart_controller.js:352` —
   `_fmtMoneyShort` hardcodes K/M. Needs L/Cr when the family uses lakh_crore. Pass the
   setting in via a new `data-wealth-projection-chart-number-format-value`. Tooltips and
   the end-of-line label already use server-sent `balance_formatted`, so only axis ticks
   need JS work.

8. **TODO tests** — no `test/lib/indian_number_formatter_test.rb` exists. Add one, plus a
   `Family` validation test for an invalid `number_format`. Precedent: `test/lib/money_test.rb`.

## H1.3 Docker test recipe that actually works

The documented recipe in section 17 is **wrong for this machine** and `Dockerfile.test`
does not exist. Do NOT bind-mount the repo — Rails boot hangs indefinitely reading gems
over the Windows→Linux mount. Instead copy files into a container built from an existing
image.

Working image: `sure-dev-app:live` (Rails 8.1.3.1, gems at `/usr/local/bundle`).
Broken image: `sure-test:work` (empty/invalid gemspecs — do not use).
Containers: `suretest-postgres`, `suretest-redis`, network `suretest`.

```
docker start suretest-postgres suretest-redis
docker rm -f suretest-work
docker run -d --name suretest-work --network suretest --entrypoint /bin/bash \
  -e RAILS_ENV=test -e DB_HOST=suretest-postgres -e DB_PORT=5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sure_test \
  -e REDIS_URL=redis://suretest-redis:6379/0 sure-dev-app:live -lc "sleep infinity"
# copy ONLY changed files in, then:
docker exec suretest-work sh -lc "cd /rails && bin/rails test <path>"
```

Gotchas learned the hard way:
- **Exit code 1 is a false alarm.** A Minitest deprecation notice goes to stderr and
  PowerShell surfaces stderr as a failure. Read the summary line: `0 failures, 0 errors`
  means green. Do not chase the exit code.
- Never put PowerShell cmdlets (`Select-Object`, etc.) inside the container's `sh -lc`
  string — that produced `sh: Select-Object: not found`.
- The image has no `.git` and no `Gemfile.lock` mismatch; copy source files in, don't
  expect git commands inside.
- Docker Desktop must be running (`docker info`) or all commands fail with a npipe error.

## H1.4 Product decisions already made by the owner

- **Stocks:** use **daily closing prices** from Yahoo Finance (reliable without login).
  Not intraday. Zerodha remains the source for holdings and trades.
- **Mutual funds:** use **AMFI official daily NAV** (no login, no token expiry). Zerodha
  still supplies holdings/trades. Yahoo is unreliable for Indian MF NAVs.
- **INR display:** lakh/crore grouping is wanted; `1,00,00,000` for one crore.
- **Kite today:** pulls holdings once per valid daily session token; token is day-scoped,
  so price refresh stops after expiry. That is why it feels like a one-time pull.
- Later features (not started): XIRR wiring, tax harvesting, tax estimate. `Portfolio::Xirr`
  and `Portfolio::FlowClassifier` already exist but are not wired to views.

## H1.5 Next-session starting order

1. Finish steps 3–7 in 20.2 (INR formatting end to end).
2. Add tests from step 8.
3. Run the Docker recipe in 20.3 and confirm green.
4. Then begin the Yahoo/AMFI price pipeline — read
   `app/models/provider/yahoo_finance.rb`, `app/models/market_data_importer.rb`,
   `app/models/security/provided.rb`, and the Kite scheduler in
   `app/services/kite/sync_scheduler.rb`.
5. `bin/rails db:migrate` was NOT run. The `number_format` column already exists in the
   schema from migration `20261013000100`, so no migration is needed for this work.

---

# H2. Session Update (2026-10-25, later) — INR complete, price providers wired

## H2.1 Lakh/crore display: done and verified

Steps 3–8 of H1.2 are finished:

- `app/controllers/users_controller.rb` — `:number_format` added to `family_attrs`
  (this, not `Settings::PreferencesController`, is the real save path).
- `app/helpers/application_helper.rb` — `format_money` adds
  `delimiter_pattern: INDIAN_DELIMITER_PATTERN` when the family chose `lakh_crore`.
  The pattern rides through `Money#format` → `number_to_currency`, so `precision:`
  and locale symbol placement keep working, and only the integer part is grouped.
- `app/views/settings/preferences/show.html.erb` — Number format select. Uses
  `help_text:`, **not** `hint:` (the form builder ignores `hint:`).
- `config/locales/views/settings/en.yml` — `number_format`, `number_format_hint`,
  `number_formats.{western,lakh_crore}`.
- `app/javascript/controllers/wealth_projection_chart_controller.js` — new
  `numberFormat` Stimulus value; `_fmtMoneyShort` emits `L`/`Cr` for lakh_crore.
  Only axis ticks need JS; tooltips use server-sent `balance_formatted`.

`1,00,00,000` renders as one crore as requested.

## H2.2 Two pre-existing `IndianNumberFormatter` bugs — fixed

The module existed but nothing consumed it, which is why its bugs went unnoticed:

1. Whole-number amounts dropped their decimals — `format(1234567)` gave
   `"12,34,567"` instead of `"12,34,567.00"`, because `Integer#to_s` has no `"."`
   to split on.
2. `compact` **always raised** `ArgumentError`: its bare `format('%.2f', value)`
   resolved to this module's own `format` method, not `Kernel#format`.

Both fixed, with `test/lib/indian_number_formatter_test.rb` covering them.

## H2.3 Daily price pipeline: providers wired (the actual blocker)

The pipeline was mostly built already — `Provider::YahooFinance` (daily closes,
`.NS`/`.BO` for XNSE/XBOM), `Provider::Mfapi` (official AMFI NAV),
`MarketDataImporter`, and `ImportMarketDataJob` on a `0 22 * * 1-5` UTC cron
(03:30 IST the next morning — after both NSE close and AMFI publication).

**The gap was that securities carried no `price_provider`.** Both Kite syncs
created securities without one, so `price_data_provider` fell back to "first
enabled provider" — and an AMFI scheme code is not a ticker, so a stock provider
returned nothing and mutual fund NAVs never updated.

- `app/models/provider/kite/holdings_sync.rb` — new equities get `yahoo_finance`.
- `app/models/provider/kite/mutual_fund_sync.rb` — new funds get `mfapi`.
- `app/models/security/provided.rb` — new `inferred_price_provider`
  (`amfi_scheme_code` → mfapi, else `country_code == "IN"` → yahoo_finance).
  This repairs **already-imported** securities with no backfill or migration.

Verified live from the container: mfapi returned real INR NAVs for scheme
`125497`; Yahoo returned INR daily closes for `RELIANCE.NS`. **The old "Yahoo
hangs" problem does not reproduce** with the current 5s timeout / 2 retries.

### Still required in production (config, not code)

`Setting.enabled_securities_providers` falls back to the singular
`SECURITIES_PROVIDER` when the plural is unset, so only one provider can be
active at a time. On the LXC, in `/etc/sure/.env`:

```
SECURITIES_PROVIDERS=yahoo_finance,mfapi
```

Then restart both services. Without this the inferred provider resolves to nil
and silently falls back to the old behaviour.

## H2.4 Full test suite — actually run

`bin/rails test` on a faithful copy of the working tree inside `sure-dev-app:live`:
**11,706 runs, 53,670 assertions, 6 failures, 2 errors, 34 skips.**

All 8 are the known environment artifacts, none caused by this work:
- 3 `AccountStatementTest` + 2 `Pdf::TextExtractorTest` — PDF fixtures corrupted
  by CRLF (`.gitattributes` does not cover `*.pdf`).
- 1 `Provider::FamilyGeneratorTest` and 1 `RecurringTransaction::PipelineTest` —
  they regex-match `\n` but Windows-sourced files carry `\r\n`.
- 1 `SnaptradeAccount::ActivitiesProcessorTest` — float precision.

These pass on the Linux LXC except the PDF ones.

## H2.5 Preview gotchas worth remembering

The `sure-dev-app` container bakes its code into the image (no bind mount). To
preview local changes you must `docker cp` the changed files in **and**
`bin/rails tailwindcss:build`, otherwise Tailwind classes written for new markup
are absent from the compiled CSS. Clear `/rails/tmp/pids/server.pid` before
restarting or Puma refuses to boot. The app registers a service worker, so a hard
refresh (or unregistering it) is needed to see new JS.

Running the full suite needs a **faithful** tree: a partial `docker cp` of only
changed files makes unrelated tests fail (e.g. `YahooFinance` retry defaults,
`max_retries`) because stale test files stay behind. Copy `app config lib test db
spec bin` wholesale, not just the diff.

---

# H3. Production Bring-Up (2026-10-26) — Zerodha working end to end

Zerodha had **never** worked on the LXC. The connection had only ever been made
against the local Docker demo, and six separate faults were hiding behind that.

## H3.1 Why the Kite login went nowhere

The registered Kite Connect redirect URL is
`https://desktop-nt9v6sa.taildc6d46.ts.net/kite/callback`, served by **Tailscale
serve on the Windows PC** — and it proxied to `127.0.0.1:3000`, which is Docker
Desktop's port mapping, i.e. the demo container. Every login landed in the demo
database; production never saw a callback.

Tailscale cannot proxy to `192.168.1.100` directly (502): that host is only
reachable *through* the tailnet, so its own proxy loops. The working chain is:

```
Zerodha -> https://desktop-nt9v6sa.../  (tailscale serve)
         -> http://127.0.0.1:3100       (ssh -N -L 3100:127.0.0.1:3000 root@192.168.1.100)
         -> LXC puma :3000
```

`tailscale serve --bg http://127.0.0.1:3100` and the ssh tunnel must both be
running; a reboot drops them. Permanent fix: install Tailscale on the LXC and
serve there instead.

Kite requires an **HTTPS** redirect URL, so the plain-HTTP `finance.lan` path can
never be the callback. `RAILS_ASSUME_SSL` stays **false** — Rails already honours
Tailscale's `X-Forwarded-Proto: https` (verified: `scheme: "https"` in the log),
and setting it true would break `finance.lan`, which is HTTP.

## H3.2 The six bugs

1. **`integrations` queue missing from `config/sidekiq.yml`.** All three Kite
   jobs declare `queue_as :integrations`; no worker polled it, so every
   `Kite::SyncPortfolioJob` sat in Redis forever. The cron jobs looked healthy
   only because `Kite::SyncScheduler` pins them to `scheduled`.
2. **No Kite section on the accounts page.** `Account.manual` is
   `where(account_providers: { id: nil })`, so provider-linked accounts are
   excluded; the index renders one section per provider and Kite had none. Added
   `kite_items/_kite_item.html.erb` plus `@kite_item` in the controller.
3. **Cost basis multiplied by quantity.** `holdings.cost_basis` is **per share**
   (`Holding#avg_cost` returns it verbatim; `calculate_avg_cost` divides total
   cost by total qty). Both Kite syncs stored `average_price * qty`, inflating
   cost by the position size — a 584-unit fund reported a ₹2.87 crore loss
   (−99.8%) and, because `investment_statement` multiplies qty by avg_cost again,
   a portfolio denominator in the crores that pushed every weight to 1.0%.
4. **No balance anchor.** Kite reports holdings, not deposits, so
   `Balance::ReverseCalculator` had no total to work back from and derived cash
   as the negative of the holdings. Zero net, so ₹1.67 lakh stayed out of net
   worth. `Provider::Kite::BalanceSync` anchors each account to latest holdings +
   `/user/margins` cash, **before** the account syncs.
5. **Funds identified by ISIN.** Zerodha's `/mf/holdings` gives `tradingsymbol`
   as an ISIN (`INF959L01FX6`); mfapi is keyed by scheme code (`149892`) and
   answers 400 to an ISIN. `AmfiSchemeIndex` maps ISIN -> scheme code from AMFI's
   official `NAVAll.txt` (both identifiers on one row, either ISIN column
   resolves). `MutualFundSync` now stores the scheme code as the ticker and keeps
   the ISIN, correcting ISIN-keyed funds **in place** (matched by ISIN) so no
   duplicate security is created.
6. **Rights entitlements priced forever.** `OLAELEC-RE-BE` is a renounceable
   entitlement, not tradable; Yahoo 404s it on every fetch. `HoldingsSync` marks
   such symbols offline with a reason.

## H3.3 Things that will bite next time

- **AMFI's URL answers 302**, and plain `Faraday.get` does not follow it — the
  body is a 169-byte redirect page that parses to zero ISINs. `AmfiSchemeIndex`
  follows one hop by hand. It also refuses to cache an empty result, so one bad
  fetch does not cost a day of fund pricing.
- **Yahoo's quota is brutal from this IP.** A 24-month backfill of 19 securities
  fails after two or three requests *at any spacing*, so `backfill_price_history`
  (cron `30 19 * * *`) tops up three securities a night, shallowest series first,
  and finishes in about a week.
- `kite_accounts.current_balance` is **never** populated: `upsert_from_kite!`
  exists but nothing calls it. Balance comes from the anchor instead.
- For the monthly-sync workflow (owner resyncs Zerodha monthly, not daily):
  holdings and cost basis refresh at sync time; **prices still update daily**
  from Yahoo/mfapi, so valuations stay current without a Kite login. The daily
  "session expired / reconnect" prompt is expected noise, not a fault.

## H3.4 Verified state at end of that session

- Holdings 19, portfolio ₹1,67,286.76; both accounts anchored and matching.
- `/accounts` returns 302 (login) with no errors; Zerodha section renders.
- 9 securities hold ≥1 year of daily prices; 6,599 price rows, earliest
  2024-10-26. The 3 funds each have 731 NAV points.
- Tests: `test/models/amfi_scheme_index_test.rb`, `test/jobs/
  market_data_history_backfill_job_test.rb`, `test/models/provider/kite/*`, and
  `test/controllers/accounts_controller_test.rb` cover every fix above.

---

# 23. Current State and the Indian Tax Phase (2026-10-26)

Written for whoever picks this up next, human or model. Everything in §23.1 and §23.2
was **verified against the running LXC**, not inferred from code. Everything in §23.4
is a plan, and §23.4 says which of it must be re-checked before it is trusted.

## 23.1 Shipped, pushed and deployed

Eight commits, `main` in sync with `origin`:

| Commit | What it did |
| --- | --- |
| `74a8048b0` | Added the `integrations` Sidekiq queue — Zerodha syncs had been sitting in Redis unprocessed forever |
| `bc1fd6494` | Zerodha-linked accounts now appear on `/accounts` (provider accounts are excluded from `Account.manual`) |
| `e73494a2d` | Cost basis is per share, not per position; account balances anchored from holdings |
| `ab3213ead` | Kite mutual funds priced by resolving ISIN to an AMFI scheme code |
| `38c907e5d` | AMFI 302 redirect followed by hand; empty index is never cached |
| `bf06a69c2` | `market_data:backfill_prices[24]` rake task fills price history |
| `a679ece0d` | `MarketDataHistoryBackfillJob` tops up 3 securities a night at 01:00 IST |
| `b4eccb66d` | This document |

Verified live afterwards: 19 holdings, portfolio **₹1,67,286.76**; Zerodha Equity
₹63,895.48 and Zerodha Coin ₹1,03,391.28 both anchored; security weights 31.45%,
22.06%, 15.02% (they were ~1% each when cost basis was wrong); returns +7.36%,
+2.51%, +11.53%, −38.51%; 3 funds carry AMFI codes 122639 / 149892 / 150892 with 731
NAV rows each; `OLAELEC-RE-BE` (a rights entitlement) marked `offline` instead of
404ing Yahoo nightly.

## 23.2 What is collecting data while we wait

Nothing needs to be clicked except one monthly Zerodha login.

- `ImportMarketDataJob` — `0 22 * * 1-5` UTC (03:30 IST) — daily closes from Yahoo for
  equities, official AMFI NAV for funds. **Prices keep updating even when the Kite
  session has expired**; holdings refresh only when the login happens.
- `MarketDataHistoryBackfillJob` — `30 19 * * *` (01:00 IST) — 3 securities a night.
  It exists because Yahoo throttles after two or three requests from this IP *at any
  spacing*; a single 19-security backfill cannot succeed.

State at hand-off: **6,599 price rows**, earliest 2024-10-26, **9 of 18** securities
with a year or more. About a week of nights finishes the rest.

**Gate for starting tax work:** enough history to compare a sale against its purchase
date. Check with:

```ruby
Security.joins(:prices).group("securities.id").having("count(*) > 200").count.size
```

At 16+ of 19, the data is good enough for a first capital-gains pass over the current
financial year.

## 23.3 The real blocker for tax: we have no purchase dates

This is the one finding that changes the plan, so it is written out in full.

- A `holdings` row has a `date`, but that is the **valuation snapshot** date, not the
  day anything was bought. There is no purchase date and no lot structure anywhere in
  the schema.
- Lots can only come from `trades`. A `Trade` has `security_id`, signed `qty`, per-unit
  `price` and `fee`; its **date and account live on `entries`** (`entries.date`,
  `entries.account_id`) because `Trade` is `Entryable`. That join is the whole lot
  source.
- `Provider::Kite::TradeImporter` calls Kite's `/trades`, which returns **only the
  current trading day's** tradebook. Kite Connect has no historical tradebook endpoint.
  So matching the owner's monthly resync pace, most trades will never be seen.
- Therefore, for everything already held: **purchase dates are unobtainable from the
  API.** They exist in Zerodha Console → Reports → *Tradebook* (CSV, any date range),
  and Console's *Capital gains statement* for a financial year is the ground truth to
  reconcile against.

Consequence for the build: the tax feature needs a **one-time CSV import** of the
Console tradebook, then forward capture of `/trades` while a session is live. Without
the import, the feature can only describe gains made on positions bought after the
import date.

Second consequence, subtler: the existing `Trade#realized_gain_loss` uses the
**average cost of the latest holding on or before the sale date** and returns a
`Trend`. That is a reasonable portfolio figure and it is *wrong for tax*, because
average cost erases which shares were sold, and lot age is exactly what decides
12 months (long-term) versus 11 months (short-term). Tax needs FIFO lots.

## 23.4 The rules to encode — RE-CHECK BEFORE SHIPPING ANY FIGURE

Last confirmed against the **Finance (No. 2) Act 2024**, which applies to gains
realised **on or after 23 July 2024**. A web search was unavailable while writing
this, so no rate below has been verified against a 2025/26 Finance Act. Treat this
as the shape of the problem, not as the answer:

- **Listed equity shares and equity-oriented mutual funds (STT paid):** held ≤12
  months → short-term, 20% (s.111A). Held >12 months → long-term, 12.5% (s.112A),
  with the first **₹1.25 lakh of long-term gains per person per financial year
  exempt**. No indexation.
- **Debt / "specified" mutual funds bought on or after 1 April 2023:** gains are taxed
  at the person's **slab rate** whenever sold. No long-term rate at all. This is why
  a fund needs its category recorded, not just a ticker.
- **Unlisted shares and foreign shares** (the US stocks in the IBKR account): the
  long-term threshold is **24 months**; long-term rate 12.5%; short-term at slab.
- **Set-off (s.74):** a short-term loss offsets short-term gains first, then long-term
  gains; a long-term loss offsets **only** long-term gains. Unused losses carry
  forward **8 assessment years, but only if that year's return was filed on time**.
- **Cess and surcharge:** 4% health & education cess on the tax; surcharge applies
  above income thresholds with a **15% cap** on s.111A/112A gains.
- **Grandfathering:** listed equity bought before 31 January 2018 may use the higher
  of actual cost and the 31 January 2018 fair market value. Let the user type it in.
- **India has no wash-sale rule.** Selling to book a loss and buying the same stock
  back the next day is allowed, which is what makes tax-loss harvesting legitimate
  here (in the US it is not).
- **Dividends are slab income**, not capital gains. They are `Transaction` rows, not
  trades — do not add them to proceeds.

## 23.5 Design decisions for the tax feature

- **Per person, not per family.** Tax is assessed per PAN. `accounts.owner_id` already
  exists. Family tenancy is a convenient view; it must never be the tax unit, and
  household totals must not be presented as one taxable person.
- **FIFO lots, never average cost.** One defensible method, stated on screen.
- **Never compute tax from `holdings`.** Holdings are for valuation. Lots come from
  trades only.
- **Currency.** Foreign holdings need INR: sale value at the sale date's rate, cost at
  the purchase date's rate. `ExchangeRate` rows for those dates already exist.
  Follow `Trade#converted_to_basis_currency`, which looks up the exact date and
  returns `nil` rather than pretending a missing rate is 1.0.
- **Estimate, do not file.** No ITR generation, no e-filing. The output is a number
  the owner can sanity-check and a schedule to hand to a CA. Say "estimate" on screen.
- **We do not know the owner's slab.** Either add an "other income this year" input,
  or show slab-taxed gains at 0% and label them plainly as not included.

## 23.6 Build order for the next session

1. **Confirm the data gate** (§23.2). Prices first; a capital gains number built on
   missing prices is a wrong number.
2. **Wire `Portfolio::Xirr`.** It is finished, tested and unused: Newton-Raphson with a
   bisection fallback, `rate_or_nil` for render paths, `ambiguous?` for series with
   several roots — the caller is told to hedge rather than present one root as *the*
   answer. Flows come from `Portfolio::FlowClassifier` (also finished, with a SQL and
   a Ruby form proved to agree). This is the cheapest win and needs no purchase dates.
3. **Lot engine** — a PORO, e.g. `Portfolio::TaxLots`, FIFO over trades, yielding
   `{security, acquired_on, qty, cost_per_unit, currency}`. Pure function, heavily
   tested; no migration.
4. **Zerodha Console tradebook CSV importer.** Turns the existing portfolio into
   taxable data. This is the step that unblocks real gains.
5. **`FinancialPlanning::CapitalGains`** — per financial year, per owner:
   short-term / long-term / slab buckets, ₹1.25 lakh exemption applied, set-off
   applied, cess and surcharge shown separately.
6. **Estimator view** — "if you sold everything today", per bucket and per person.
7. **Harvesting view** — losses available to book, ranked by which gains they would
   offset, with the buy-back caveat (no wash-sale rule, so the trade is real and has
   costs).

## 23.7 Things that will bite during the tax work

- `security_splits` exists and is populated for some securities. Apply splits and
  bonuses before computing per-unit cost, or a 1:10 split reads as a 90% loss.
- Rights entitlements (`-RE`, `-RE-BE`) are already marked `offline` by the Kite
  holdings sync. They have no cost until renounced or exercised — exclude from lots.
- `Trade#qty` is **signed** (negative = sell) and `Trade#price` is **per unit**.
  Proceeds = `price × qty.abs − fee`. A `cost_basis` read as a total instead of
  per-share is exactly the bug that produced a fake −₹2.87 crore in §22 — do not
  repeat it in the tax code.
- Broker cost basis may be corporate-action adjusted; the Console capital gains
  statement is the figure to reconcile against, and a mismatch must be shown to the
  user rather than silently hidden.
- Foreign shares also need **Schedule FA** disclosure in the ITR. That is a
  compliance checkbox, not a tax amount, but the cost of missing it is a penalty —
  worth surfacing in the UI even though we compute nothing for it.

## 23.8 Owner actions still outstanding

- **Rotate the Kite API secret and the Postgres password.** The repository is public
  and both appear in its git history (the file was redacted in `96f19c33a`; earlier
  commits still contain them).
- **Install Tailscale on the LXC.** The Kite callback currently depends on a tunnel
  started on the Windows PC; a reboot breaks the daily price sync's UI access and
  makes the callback return 502.
- **Log in to Zerodha once a month** (the agreed pace — monthly resync). The daily
  "session expired / reconnect" prompt is expected noise, not a fault.
- **Download the Console tradebook CSV once** so step 4 above has something to import.
