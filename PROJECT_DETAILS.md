# PROJECT DETAILS — Sure Finance (NinzEnrai/sure-financialPlanning)

Comprehensive context document. Last updated: 2026-10-24. Commit: 68ff97df5.

## 1. Identity

- Repo: https://github.com/NinzEnrai/sure-financialPlanning
- Upstream: https://github.com/we-promise/sure (community fork of Maybe Finance)
- License: AGPLv3
- Framework: Ruby on Rails 8.1 (ruby 3.4.9)
- Stack: PostgreSQL 16, Redis 7, Sidekiq, Propshaft + Importmap (no JS bundler), Tailwind CSS v4, Stimulus, Turbo
- Auth: session cookies, Current.user / Current.family (never current_user)
- Multi-tenant: family_id scoping everywhere; Current.family

## 2. What Was Built (11 commits ahead of upstream, all pushed)

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

### Commit 6: ad59913e3 — FIRE variants + Coast FIRE
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
- RAILS_SERVE_STATIC_FILES=true (added — was missing, caused broken UI)

### db:prepare trap
- db:prepare loads db/schema.rb when DB is empty, stamping schema_migrations without running migrations
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
- Functional tokens: bg-container, text-primary, border-primary, bg-warning/10, text-destructive
- DS::* primitives: Card, Pill, ProgressBar, Disclosure, Note, DetailRow, etc.
- icon helper (never lucide_icon directly)
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
- KITE_API_KEY=xz5jbn2v6n8em5ce
- KITE_API_SECRET=wrrwtg1eo33khipzxha45w3ab8y0qfkc (rotate — was exposed in chat)
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
- Full suite: 11,673 runs, 53,600 assertions, 6 failures + 2 errors (all pre-existing)
- Pre-existing failures (Windows CRLF only, pass on Linux CI):
  - 3× AccountStatementTest (PDF xref)
  - Provider::FamilyGeneratorTest (generated controller)
  - RecurringTransaction::PipelineTest (database.yml)
  - 2× Pdf::TextExtractorTest (PDF fixtures)
  - 1× SnaptradeAccount::ActivitiesProcessorTest (float precision)

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
11. /opt/sure is not a git repo (deployed via tarball) — now converted to git clone
12. sure.creds is plaintext with DB password (security concern)
13. /opt/sure-old is a March 2026 deploy (Rails 7.2) — NOT a valid rollback
14. 512MB hosts: demo data generator OOMs
15. KiteItem#destroy_later was hand-rolled and didn't restore on enqueue failure — fixed
16. Compound calculator's growth_rate_pct was reading planning_setting directly — fixed
17. Savings rate chart NaN from BigDecimal→string in JSON — fixed
18. Wealth projection chart render() method added for calculator
19. Family#balance_sheet memoization survives reload — noted but not fixed
20. Yahoo Finance fetch_cookie_and_crumb makes requests that may hang

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
- Postgres password exposed in chat (ZRunWrdeFyz7R) — rotation recommended

## 13. What's NOT Built Yet

- Customisable 50/30/20 targets (only category assignment, not target %)
- XIRR + Indian capital gains (blocked on Zerodha Nextra)
- Visual verification of savings split by user (needs preview_features)
- Yahoo Finance full integration (reduced hang risk, but needs testing)
- XIRR/tax UI (Portfolio::Xirr exists but isn't wired to any view)
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
- Zerodha redirect URL: https://jarvis.taildc6d46.ts.net/kite/callback
- Tailscale serve on port 3000 (Windows side)

## 19. What's Pending

- Deploy to LXC (tarball ready, now converted to git clone)
- Visual verification of savings split by user (needs preview_features toggle)
- Rotate the exposed Kite api_secret
- Rotate the exposed Postgres password
- Build XIRR + Indian capital gains tax (blocked on Zerodha Nextra)
- Yahoo Finance full integration (reduced hang risk, needs testing)
- XIRR/tax UI (Portfolio::Xirr exists but isn't wired)
- Price history UI (Security::Price exists but no view)
- Document EXCHANGE_RATE_PROVIDER in .env.local.example
- Fix 5 pre-existing CRLF test failures (Windows only, pass on Linux)
- Yahoo Finance hang investigation (reduced timeouts, needs testing)
- Family#balance_sheet memoization bug (noted but not fixed)
- Customisable 50/30/20 targets (only category assignment, not target %)

## 20. Key Gotchas for DeepSeek

1. Always use `Current.user` and `Current.family`, never `current_user` or `current_family`
2. Family tenancy: every query must be scoped to `Current.family`
3. `Family#balance_sheet` memoizes per user and survives `reload` — use `Family.find` for fresh instances
4. `db:prepare` stamps schema_migrations without running migrations on empty DB
5. BigDecimal rides through `#to_json` as a string — coerce with `.to_f` in views
6. `Float#to_s("F")` raises — use BigDecimal
7. `ExchangeRate.rates_for` falls back to rate=1 with logged warning if no rate found
8. `IncomeStatement::ScopedTransactionsQuery#converted_amount_sql` uses LEFT JOIN with COALESCE(er.rate, 1) — strict exact-date match
9. Kite tokens are day-scoped; stuck pending Sync silently blocks sync_later forever
10. The reverse proxy at finance.lan caches aggressively — use cache-busting headers
11. Yahoo Finance hangs — do not set SECURITIES_PROVIDERS=yahoo_finance yet
12. `Family#income_statement` is NOT memoized (unlike balance_sheet)
13. `PlanningSetting#bucket_for` prefers override, falls back to DEFAULT_BUCKETS
14. `PlanningSetting::RESET_BUCKET = "__default__"` is a sentinel, not a real bucket
15. `FinancialPlanning::SavingsRate#invested` caps at income when income positive
16. `FinancialPlanning::WealthProjector#growth_rate_pct` routes through growth_rate (not planning_setting directly)
17. `FinancialPlanning::WealthProjector#projected_balance` guards against zero growth
18. `FinancialPlanning::FireProgress` Coast FIRE uses target year, not age
19. `Portfolio::Xirr` and `Portfolio::FlowClassifier` exist but aren't wired to views
20. `Security::Price` model exists for price history but no UI
21. `Security::Provided` has `find_or_fetch_price` and `import_provider_prices`
22. `ImportMarketDataJob` runs daily at market close, imports prices for all securities
23. `Account::MarketDataImporter` syncs required exchange rates for foreign-currency accounts
24. `DebugLogEntry.capture(...)` for support-relevant failures
25. `Current.user` and `Current.family` are set by middleware, not controller helpers