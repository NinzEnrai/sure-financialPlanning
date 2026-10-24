# PROJECT DETAILS — Sure Finance (NinzEnrai/sure-financialPlanning)

Paste this entire document into DeepSeek as context. It describes a fork of we-promise/sure
(Maybe Finance community fork) with three feature areas built in: Zerodha Kite integration,
a Financial Planning dashboard (savings split, budget analyzer, FIRE, wealth projection),
and the savings-rate chart. Everything below reflects the state at commit ad59913e3.

## 1. Identity

- Repo: https://github.com/NinzEnrai/sure-financialPlanning
- Upstream: https://github.com/we-promise/sure (community fork of Maybe Finance)
- License: AGPLv3
- Framework: Ruby on Rails 8.1 (ruby 3.4.9)
- Stack: PostgreSQL 16, Redis 7, Sidekiq, Propshaft + Importmap (no JS bundler), Tailwind CSS v4, Stimulus, Turbo
- Auth: Devise-ish session cookies, Current.user / Current.family (never current_user)
- Multi-tenant: family_id scoping everywhere; Current.family

## 2. Environment (production)

- Host: Proxmox LXC, container name `sure` (hostname), IP 100.69.188.5 (tailscale)
- Public URL: https://jarvis.taildc6d46.ts.net (tailscale serve)
- App path: /opt/sure (NOT a git repo — deployed via rsync tarball; being converted to git)
- Previous release: /opt/sure-pre-git (the Oct 12 deployment, kept for rollback)
- Env file: /etc/sure/.env (EnvironmentFile= in systemd units)
- DB: postgres on 127.0.0.1, sure_production, user sure_user, password rotated (see security note)
- Redis: 127.0.0.1:6379
- Ruby: rbenv 3.4.9 at /root/.rbenv, PATH includes shims
- Web: puma 7.2.1 on tcp://0.0.0.0:3000 (systemd service `sure.service`, Restart=always)
- Worker: sidekiq 8.0.5 (systemd service `sure-worker.service`)
- Gems: vendor/bundle (544MB, BUNDLE_DEPLOYMENT=1, BUNDLE_WITHOUT=development)
- Memory: ~198MB RSS for puma, 452MB for sidekiq (see gotchas)
- Build packages: build-essential libpq-dev git pkg-config libyaml-dev (needed for native gems)
- Tailwind v4.1.8, poppler-utils, libvips, jemalloc (preloaded)
- rbenv version marker: /root/.sure = "0.6.8"

## 3. The Six Commits (pushed, in order)

1. 8bbd3be2e "Complete Zerodha Kite Connect integration" (50 files, +1727/-755)
2. 812eee982 "Count invested money as savings in the planning split" (6 files, +726/-21)
3. 006a72bbf "Add compound calculator sliders to the wealth projection" (7 files, +302/-13)
4. 98b0f0076 "Chart the monthly savings rate against savings incl. investments" (3 files, +413/-4)
5. 1e8b845a3 "Let families assign categories to needs, wants and savings" (6 files, +317/-2)
6. ad59913e3 "Add FIRE assumptions form and variants, incl. Coast FIRE" (10 files, +418/-9)

The final tree is byte-identical to the tested state.

## 4. Zerodha Kite Connect Integration

### Design decisions
- Daily manual login; NO stored broker credentials or TOTP (no auto-login, no TOTP automation)
- Credentials (api_key/api_secret) live in ENV VARS, not DB. Reason: pg_dump captures every column; /etc/sure/.env does not. Safer for backups.
- Kite is the 10th investment provider, lives in Settings > Providers (not a standalone /settings/kite_connection page)
- Not Syncable-scheduled (cron-scheduled instead). Removed KiteItem::Syncer + SyncCompleteEvent as dead code. Bonus: this fixed a shadowed `last_synced_at` column.

### Kite credentials
- api_key: xz5jbn2v6n8em5ce
- redirect URL registered on Zerodha app: https://desktop-nt9v6sa.taildc6d46.ts.net/kite/callback (dev)
  - Production redirect URL must be https://jarvis.taildc6d46.ts.net/kite/callback
- Kite user_id: LBS596
- Holdings: 15 equity + 3 mutual funds
- Balances: ₹68,692.57 + ₹102,611.42

### Models
- KiteItem (app/models/kite_item.rb) — includes Provided, Unlinking, Encryptable (NOT Syncable)
  - filter_attributes on api_key/api_secret
  - has_many :kite_accounts (dependent: :destroy)
  - has_many :linked_accounts, through: :kite_accounts
  - scopes: active (scheduled_for_deletion: false), syncable (active.good.with token), ordered, needs_update
  - destroy_later via DestroyableLater concern
- KiteAccount (app/models/kite_item/kite_account.rb) — wrapper around Investment account
- Provider::KiteAdapter registered with Provider::Factory.register("KiteAccount", self)
- KiteItem::Importer, Provided, Unlinking concerns (app/models/kite_item/)
- Family::KiteConnectable concern
- Provider::Kite::HoldingsSync, MutualFundSync — set account_provider_id, require the link
- KiteItem::Importer now calls schedule_balance_syncs (the 0.0-balance fix)

### Migrations
- db/migrate/20261013000100_add_indian_market_support.rb (Migration[8.1])
- db/migrate/20261013000200_create_kite_items_and_accounts.rb (Migration[8.1])
- Both re-dated from original 20260101... names

### Routes & controllers
- app/controllers/kite/callbacks_controller.rb — find-or-create item; require_admin! (not ensure_admin)
- app/controllers/settings/kite_connections_controller.rb — require_admin!, no credential form
- app/controllers/settings/providers_controller.rb — kite added to FAMILY_PANELS, PANEL_SYNCABLE_TYPES, load_provider_items, family_panel_items
- app/helpers/settings_helper.rb — when "kite" → sync_based_summary

### Settings UI
- Settings > Providers → Kite panel (10th investment provider)
- config/locales/views/settings/providers/kite/en.yml — had duplicate `providers:` key bug (fixed)

### Kite auth flow
- Daily manual login, no stored credentials
- Redirect URL must be registered on the Kite Connect app
- /kite/callback receives the request_token from Zerodha
- Tokens are day-scoped; stuck pending Sync silently blocks sync_later forever

### Kite deploy notes
- /etc/sure/.env must have KITE_API_KEY, KITE_API_SECRET
- EXCHANGE_RATE_PROVIDER=frankfurter (see below)
- Zerodha redirect URL must be https://jarvis.taildc6d46.ts.net/kite/callback (production, not the dev tailscale URL)

## 5. Financial Planning Dashboard

### Entry point
- Route: /financial_planning (preview feature, requires preview_features_enabled preference)
- Controller: FinancialPlanningController
- Views: show.html.erb + partials: _savings_rate, _budget_analyzer, _fire_progress, _wealth_projector

### 5.1 Savings Rate (the split)

Model: FinancialPlanning::SavingsRate
- `income` — from IncomeStatement
- `invested` — max(recorded investment_contribution transfers, holdings cost basis delta), capped at income when income positive
- `expenses` — total_expenses - recorded contributions (holdings-derived is NOT subtracted; it was never in expenses)
- `cash_savings` — income - total_expenses
- `savings` — cash_savings + invested
- `percent` — cash_savings / income (nil if no income)
- `total_percent` — savings / income (nil if no income)
- `monthly_series(months:)` — 12 months of rows with both percent and total_percent
- `trailing_rate(months:)` — income-weighted average over trailing window
- `average_monthly_savings(months:)` — divides by month count

Two independent measures of "invested":
1. IncomeStatement::InvestmentContributionsTotal — recorded investment_contribution transfers
2. FinancialPlanning::HoldingsCostBasisSeries — change in holdings cost basis (per-account latest date, FX-converted)

HoldingsCostBasisSeries:
- Per-account latest date (not shared date) — handles partial syncs
- Converts to family currency via ExchangeRate.rates_for
- Falls back to rate=1 with logged warning if no rate found
- CTEs: per_account_day (group by account_id, date, currency) → latest_per_account (DISTINCT ON)

View: _savings_rate.html.erb
- Cash savings % headline
- Invested line (conditional on positive)
- Total saved line
- Progress bar
- Savings rate chart (solid = saved, dashed = saved incl. investments)

### 5.2 Budget Analyzer (50/30/20)

Model: FinancialPlanning::BudgetAnalyzer
- Three buckets: needs, wants, savings
- TARGET_SHARE_PCT: needs 50%, wants 30%, savings 20%
- Category → bucket assignment via PlanningSetting#bucket_for (prefers override, falls back to DEFAULT_BUCKETS)
- `spend_by_category`, `unassigned_categories`, `categories_for`, `assigned_categories`, `bucketed_categories`
- Needs/wants are ceilings, savings is a floor — on_track? compares direction

Bucket picker UI: Customise buckets disclosure in the card
- Lists all family categories (spending ones first)
- Select: Default (restores built-in mapping) / Needs / Wants / Savings
- Auto-submits on change (auto-submit-form controller)
- RESET_BUCKET = "__default__" sentinel — dropping the key, not storing a sentinel

Controller action: update_bucket — scoped to family's categories, validates bucket value

### 5.3 FIRE Progress

Model: FinancialPlanning::FireProgress
- Target = average annual expenses / withdrawal rate
- Annual expenses averaged over 12 trailing months
- `percent`, `bar_percent` (capped 100), `remaining`, `achieved?`, `months_to_target`
- Simulator uses WealthProjector with current net worth as opening balance

Variants (PlanningSetting::FIRE_VARIANTS):
- lean: 3.3% withdrawal rate
- coast: 4.0%, needs target_year (different question: "will I have it by then")
- barista: 6.5% (15x expenses)
- standard: 4.0% (25x, classic 4% rule)
- fat: 3.0% (33x)
- DEFAULT_FIRE_VARIANT = "standard"

Coast FIRE:
- target_year (integer, validated current_year..current_year+60)
- target_date = end of target year
- months_until_target_date, projected_balance_at_target_date
- coast_on_track? compares projection at target date against target

UI: FIRE assumptions disclosure with:
- Variant select (auto-toggles target year field via fire_variant_controller.js)
- Target year (coast only)
- Withdrawal rate (auto-filled on variant change)
- Growth rate
- Save button
- Pill showing current variant

### 5.4 Wealth Projection

Model: FinancialPlanning::WealthProjector
- 10-year projection from current net worth
- opening_balance, monthly_contribution, growth_rate
- `points` (year 0 = today, years 1-10)
- `final_balance`, `monthly_contribution`, `growth_rate_pct`
- `months_to_target(target)` — geometric closed form
- `balance_after_months(months)` — for Coast FIRE
- growth_rate_pct handles zero growth (annuity term becomes annual * offset)

Compound calculator UI:
- Two sliders: monthly contribution + annual growth
- Re-projects via GET /financial_planning/projection
- Debounced, stale-response discard via monotonic token
- Chart re-renders via wealth_projection_chart_controller.js `render()`
- JS: compound_calculator_controller.js

## 6. JS Controllers (new/modified)

- compound_calculator_controller.js — sliders, debounce, stale discard, fetch, render chart
- savings_rate_chart_controller.js — dual series (solid + dashed), zero reference line, tooltip
- fire_variant_controller.js — show/hide target year field
- wealth_projection_chart_controller.js — modified: added `render()` method for calculator

## 7. Routes

```ruby
# financial_planning
get  financial_planning_path          # show
get  projection_financial_planning_path # projection JSON
patch bucket_financial_planning_path   # category -> bucket
patch setting_financial_planning_path  # update_setting

# kite
get  kite_callback_path               # /kite/callback
# settings/kite_connections
# settings/providers (includes kite panel)
```

## 8. Database

### Migrations added
- 20261013000100_add_indian_market_support.rb
- 20261013000200_create_kite_items_and_accounts.rb
- 20261014000100_add_fire_variant_to_planning_settings.rb (fire_variant string, fire_target_year integer)

### Schema changes
- planning_settings: +fire_variant (string, default "standard", not null), +fire_target_year (integer, nullable)
- planning_settings: +category_buckets (jsonb, default {})
- kite_items table: api_key/api_secret columns REMOVED (env vars instead)
- kite_items: +scheduled_for_deletion, +access_token, +status, etc.
- kite_accounts table
- account_provider_id on holdings
- provider Securities provider support (Indian market)

### Critical trap
`db:prepare` loads `db/schema.rb` instead of running migrations when the DB is empty — stamps schema_migrations without running. Always verify with `db:migrate:status`.

## 9. Environment Variables

Required (LXC):
- KITE_API_KEY=xz5jbn2v6n8em5ce
- KITE_API_SECRET=<32-char secret>
- EXCHANGE_RATE_PROVIDER=frankfurter (without this, all currencies convert at rate 1 — silent wrong numbers)

Optional:
- SECURITIES_PROVIDERS (do NOT set yahoo_finance — hangs)
- DB_HOST, DB_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, REDIS_URL
- SECRET_KEY_BASE
- RAILS_ENV=production

## 10. External Services

- Zerodha Kite Connect (broker API, daily manual login)
- Frankfurter (FX rates, free, keyless) — NOT the same as SECURITIES_PROVIDERS
- Yahoo Finance (securities prices — hangs, avoid)
- OpenAI-compatible LLM endpoint (optional)
- SimpleFIN, Plaid, SnapTrade (other providers, pre-existing)

## 11. Tests

- Minitest + fixtures (not RSpec, except rswag for OpenAPI)
- 150+ tests passing in financial_planning + kite + settings
- Full suite: 11,673 runs, 53,600 assertions
- 8 pre-existing failures (all Windows CRLF or Snaptrade float precision)
- My work introduced 0 new failures

## 12. Design System

- Functional tokens only: bg-container, text-primary, border-primary, bg-warning/10, text-destructive
- No raw Tailwind palette classes or hex literals
- DS::* primitives: Card, Pill, ProgressBar, Disclosure, Note, DetailRow, CategoryIcon (doesn't exist — use icon helper)
- icon helper, never lucide_icon directly
- t() for all user-facing strings
- Scale tokens, not arbitrary px

## 13. Known Issues / Gotchas

1. Docker crashes (ENOMEM) — host memory
2. Tailscale serve config lost on restart
3. db:prepare stamping trap
4. Kite tokens day-scoped; stuck pending Sync blocks sync_later forever
5. EXCHANGE_RATE_PROVIDER must be set or silent rate-1 conversion
6. Family#balance_sheet memoizes per user and survives reload
7. Windows CRLF: core.autocrlf=true, .gitattributes doesn't cover *.pdf/*.tt
8. Yahoo Finance price provider hangs
9. XIRR + Indian capital gains blocked (need Zerodha Nextra for history)
10. Family currency was USD, switched to INR (user lives in India)
11. /opt/sure is not a git repo — deployed via tarball
12. sure.creds is plaintext with DB password (security concern)
13. /opt/sure-old is a March 2026 deploy (Rails 7.2) — NOT a valid rollback
14. 512MB hosts: demo data generator OOMs
15. KiteItem#destroy_later was hand-rolled and didn't restore on enqueue failure — fixed
16. Compound calculator's growth_rate_pct was reading planning_setting directly, ignoring slider override — fixed

## 14. Security Notes

- Kite credentials in env vars, not DB (pg_dump captures columns)
- .env.local is gitignored
- .env.local.example is clean (no secrets)
- api_secret was briefly in chat and .env.local.example — reverted, rotated recommended
- filter_attributes on KiteItem for api_key/api_secret
- Family tenancy preserved everywhere
- X-Api-Key auth pattern for API endpoints
- Brakeman clean (0 errors, 0 warnings)
- RuboCop clean on touched files

## 15. What's NOT Built Yet

- Compound calculator with slider for monthly investment — BUILT (this session)
- Customisable FIRE UI — BUILT (this session)
- Customisable 50/30/20 targets (only category assignment, not target %)
- Savings rate graph — BUILT (this session)
- XIRR + Indian capital gains (blocked on Zerodha Nextra)
- Visual verification of savings split by user (needs preview_features)

## 16. File Structure (key paths)

```
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
```

## 17. API Endpoints (financial planning)

- GET /financial_planning — show (HTML)
- GET /financial_planning/projection — JSON: years, balances, balance_labels, final_balance, final_balance_label, monthly_contribution, growth_rate_pct, currency
- PATCH /financial_planning/bucket — params: category_id, bucket
- PATCH /financial_planning/setting — params: planning_setting[fire_variant, fire_target_year, fire_withdrawal_rate_pct, annual_growth_rate_pct]

## 18. How To Run Tests

```bash
docker build -f Dockerfile.test -t sure-test:work .
docker start suretest-postgres suretest-redis
docker run --rm --network suretest -v "/path/to/repo:/rails" -w /rails \
  -e RAILS_ENV=test -e DB_HOST=suretest-postgres -e DB_PORT=5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sure_test \
  -e REDIS_URL=redis://suretest-redis:6379/0 \
  sure-test:work bin/rails test <path>
```

## 19. Deployment (bare metal LXC)

- No Docker (docker crashed 7x due to ENOMEM)
- Services: sure.service (puma), sure-worker.service (sidekiq), systemd
- ExecStartPre: /opt/sure/bin/rails db:prepare (runs migrations on restart)
- EnvironmentFile: /etc/sure/.env
- Update: tarball → rsync over /opt/sure (preserve vendor/)
- Need EXCHANGE_RATE_PROVIDER=frankfurter or silent rate-1 conversion
- Need KITE_API_KEY, KITE_API_SECRET in env
- Zerodha redirect URL: https://jarvis.taildc6d46.ts.net/kite/callback
- Tailscale serve on port 3000

## 20. What's Pending

- Deploy to LXC (tarball ready)
- Convert /opt/sure to git clone (planned)
- Visual verification of savings split by user (needs preview_features toggle)
- Rotate the exposed Kite api_secret
- Build FIRE UI inputs (done)
- Build compound calculator (done)
- Document EXCHANGE_RATE_PROVIDER in .env.local.example
- Fix 5 pre-existing CRLF test failures (Windows only, pass on Linux)
- Yahoo Finance price provider hang (investigate separately)
- XIRR + Indian capital gains (blocked on Zerodha Nextra)