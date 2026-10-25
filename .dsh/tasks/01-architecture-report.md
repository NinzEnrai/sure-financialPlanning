# Sure checkout - architecture & convention report (ground truth for plugin rule text)

Audit scope: read-only inspection of `C:\Users\Ninz\Documents\GitHub\sure-financialPlanning`.
Everything below is code-traced with `path:line`. Where a claim is only guide-derived or where
something is absent, that is stated explicitly.

Schema version audited: `ActiveRecord::Schema[8.1].define(version: 2026_10_14_000100)` - `db/schema.rb:13`.

---

## 1. Financial data model

### 1.1 Storage is `decimal(19,4)` (NOT integer cents)

- `entries.amount` - `t.decimal "amount", precision: 19, scale: 4, null: false` - `db/schema.rb:703`
- `accounts.balance` / `accounts.cash_balance` - `db/schema.rb:102`, `db/schema.rb:103`
- `balances.balance` / `cash_balance` - `db/schema.rb:257`, `db/schema.rb:259`; plus the other balance
  components `cash_inflows` `db/schema.rb:260`, `cash_outflows` `:261`, `net_market_flows` `:269`,
  `non_cash_*` `:270-272`, `start_*` `:274-275`.
- `holdings.amount` `db/schema.rb:1179`, `holdings.price` `:1187`, `holdings.cost_basis` `:1180`
- `trades.fee` `db/schema.rb:2754`, `trades.price` `precision: 19, scale: 10` `:2757`
- `transfers.amount` `db/schema.rb:2825`
- `exchange_rates.rate` - `t.decimal "rate", null: false` (no precision/scale given) - `db/schema.rb:830`
- `security_prices.price` - `db/schema.rb:2383`

High-precision quantity columns (not money): `holdings.qty` `precision: 34, scale: 18` `db/schema.rb:1189`;
`trades.qty` same `db/schema.rb:2758`.

**Integer cents exists only at the API presentation boundary, never in the DB.** There is no `*_cents`
column anywhere in `db/schema.rb` (grep for `_cents` across `db/` returns nothing). Minor units are computed
on the way out: `Api::V1::MoneyHelper#money_to_minor_units` = `(money.amount * money.currency.minor_unit_conversion).round(0).to_i`
 -  `app/helpers/api/v1/money_helper.rb:4-6`, used by e.g. `app/views/api/v1/accounts/_account.json.jbuilder:9`.
`app/views/api/v1/transactions/_transaction.json.jbuilder:9` states the intent verbatim:
"Expose minor units (cents) as integers to make the API agent-friendly."

### 1.2 Money in/out of the DB: `Monetizable` + `Money`

- Concern: `module Monetizable` - `app/models/concerns/monetizable.rb:1`, class method `monetize(*fields)` - `:5`.
  It defines `"#{field}_money"` (`:7`) which wraps the raw decimal in `Money.new(value, monetizable_currency)` (`:12`).
  The private hook is `monetizable_currency` (`:19-21`), which defaults to the record's own `currency` column  - 
  override it for records without a `currency` attribute (e.g. `Accountable#balance_money(family)` at
  `app/models/concerns/accountable.rb:92`).
- `monetize` call sites relevant to money: `app/models/entry.rb:9` (`:amount`), `app/models/account.rb:40`
  (`:balance, :cash_balance`), `app/models/balance.rb:9-13` (all 14 balance columns), `app/models/holding.rb:4`
  (`:amount`), `app/models/trade.rb:4-5` (`:price`, `:fee`), `app/models/account_statement.rb:43`,
  `app/models/goal.rb:98`, `app/models/budget.rb:22-23`, `app/models/balance_sheet.rb:4`.
- Raw decimals stay decimals; you only get `Money` through the `_money` reader. Writing goes through the
  plain decimal column (`entry.amount = 12.34`), not through `Money`.
- `Money` itself: `lib/money.rb:1`. Core API: `#amount`, `#currency` (`:17`), `#exchange_to(other_currency, date:, custom_rate:)`
  (`:49`), `#for_display` (`:70`), `#as_json` (`:74`), comparison rules (`:78`). Arithmetic is in `lib/money/arithmetic.rb`,
  formatting in `lib/money/formatting.rb:12`. `Money::Currency` is a YAML-backed value object over
  `config/currencies.yml` (`lib/money/currency.rb:6`, `:53-70`), exposing `minor_unit_conversion`, `default_precision`,
  `step` (`:72`).
- View helper: `ApplicationHelper#format_money(number_or_money, options)` = `Money.new(number_or_money).format(options)`
  - `app/helpers/application_helper.rb:186-190`. Use it in ERB rather than calling `Money` directly
  (example: `app/views/transactions/categorizes/_entry_row.html.erb:11`).

### 1.3 Cached aggregates and the jobs/concerns that keep them fresh

- `accounts.balance` / `accounts.cash_balance` are the denormalized current snapshot; the daily history lives in
  `balances` (one row per account/date/currency, unique index `db/schema.rb:277`).
- `Balance::Materializer` - `app/models/balance/materializer.rb:1`. `#materialize_balances` (`:16`) runs inside a
  transaction and does: `materialize_holdings` (`:33`) -> `calculate_balances` (`:61`) -> `persist_balances`
  (`upsert_all` on `unique_by: %i[account_id date currency]`, `:65-73`) -> `purge_stale_balances` (`:75`) ->
  `update_account_info` (`:37`) which is the **only** place the account snapshot is refreshed:
  `account.update!(balance: calculated_balance, cash_balance: calculated_cash_balance)` - `:55-58`.
- Calculator selection: `Balance::ReverseCalculator` for linked accounts, `Balance::ForwardCalculator` otherwise
  - `app/models/balance/materializer.rb:111-117`.
- `Holding::Materializer` - `app/models/holding/materializer.rb:3`; `#materialize_holdings` (`:15`) persists and
  prunes holdings including `cleanup_shadowed_calculated_holdings` (`:28`).
- Driver: `Account::Syncer#perform_sync` - `app/models/account/syncer.rb:8-14`; `#materialize_balances` picks
  `account.linked? ? :reverse : :forward` (`:21-24`). Post-sync it calls `account.family.auto_match_transfers!(account: account)`
  (`:17`).
- Family-level orchestration: `Family::Syncer` (guide-referenced at `docs/llm-guides/architecture.md:107-108`).
- Jobs: `SyncJob < ApplicationJob`, `queue_as :high_priority`, just `sync.perform` - `app/jobs/sync_job.rb:1-14`.
  `Sync#perform` dispatches `perform_sync`/`perform_post_sync` via `Syncable` (`app/models/concerns/syncable.rb:81-87`).
  Scheduled orchestration jobs present: `app/jobs/sync_all_job.rb:1`, `app/jobs/sync_hourly_job.rb:1`,
  `app/jobs/import_market_data_job.rb:10`, `app/jobs/sync_all_providers_job.rb:1`, `app/jobs/sync_property_valuations_job.rb:7`.
- Entry changes must request a sync: `Entry#sync_account_later` - `app/models/entry.rb:308-312`; it widens the window
  to the earliest touched date and calls `account.sync_later(window_start_date:)`. `Syncable#sync_later` reuse/starts a
  `Sync` and enqueues `SyncJob` - `app/models/concerns/syncable.rb:53-79`.
- Cache invalidation key: `Family#build_cache_key(key, invalidate_on_data_updates: false)` - `app/models/family.rb:630-641`,
  and `Sync#update_family_sync_timestamp` touches `family.latest_sync_completed_at` - `app/models/sync.rb:24`, `:377`.
  Account chart data is cached through `Account::Chartable#sparkline_series` (`app/models/account/chartable.rb:29-35`).
- **Important for rule text:** `Balance::Materializer#update_account_info` (`app/models/balance/materializer.rb:37-59`)
  is the flush point inside the sync path. Direct controller writes to `accounts.balance` do exist elsewhere and are
  *not* forbidden by the architecture: `Account::ProviderImportAdapter#update_balance` (`app/models/account/provider_import_adapter.rb:407-410`)
  and `Account::CurrentBalanceManager` (`app/models/account/current_balance_manager.rb:47`, `:141`). Also note the app-wide
  `update_column`/`update_columns` escape hatch is used for sync bookkeeping and provider best-effort writes, e.g.
  `app/models/account/provider_import_adapter.rb:608`, `app/models/trade_republic_account/data_helpers.rb:411`.

### 1.4 Currency and FX

- Per-record currency codes: `accounts.currency` `db/schema.rb:106`, `entries.currency` `:705`, `balances.currency`
  `default: "USD", null: false` `:263`, `holdings.currency` `null: false` `:1184`, `trades.currency` `:2752`,
  `security_prices.currency` `:2381`, `families.currency default: "USD"` `:848`.
- A family's preferred currency normalizes reports only; it does **not** mean stored amounts are already in it  - 
  stated at `docs/llm-guides/architecture.md:38-40`. Family-level currency config:
  `Family#enabled_currency_codes` - `app/models/family.rb:293-301`.
- FX table: `exchange_rates` (`from_currency`, `to_currency`, `date`, `rate`) - `db/schema.rb:826-836`, unique index
  `["from_currency","to_currency","date"]` `:833`. Model is 6 lines - `app/models/exchange_rate.rb:1-6`.
- Lookup/fetch: `ExchangeRate::Provided.find_or_fetch_rate(from:, to:, date:, cache: true)`  - 
  `app/models/exchange_rate/provided.rb:14-56` (exact date -> nearest within `NEAREST_RATE_LOOKBACK_DAYS = 5` `:12`
  -> provider fetch + cache). Batch variant `rates_for` `:60-100` (falls back to rate `1` with a warn when unknown `:98`).
  Import with a distributed lock: `import_provider_rates` `:103-140`.
- Provider selection: `ExchangeRate.provider` via `ENV["EXCHANGE_RATE_PROVIDER"] || Setting.exchange_rate_provider`
  and `Provider::Registry.for_concept(:exchange_rates)` - `app/models/exchange_rate/provided.rb:5-9`.
- Conversion at the Ruby level: `Money#exchange_to` - `lib/money.rb:49-67`; it raises `Money::ConversionError` (`:5`, `:63`)
  when no positive rate exists. `Holding#amount_in_account_currency` rescues that error and silently keeps the
  unconverted amount - `app/models/holding.rb:259-265` (a real footgun for anyone writing FX-sensitive code).
- Conversion inside reporting SQL: `Balance::ChartSeriesBuilder` joins `exchange_rates` twice (rate on-or-before the
  date, else earliest after) - `app/models/balance/chart_series_builder.rb:205-222`; holdings/gains conversion
  `:295-312`. Trade rows may carry their own `extra["exchange_rate"]`, which takes precedence over the table
  (`app/models/holding.rb:319-328`).

---

## 2. Tenancy and authorization

### 2.1 `Current.user` / `Current.family`

- `class Current < ActiveSupport::CurrentAttributes` - `app/models/current.rb:1`. `Current.user` is
  `impersonated_user || session&.user` (`:9-11`); `family` is delegated to `user` with `allow_nil: true` (`:7`).
  `true_user` exists for impersonation (`:17`).
- There is **no `current_user` / `current_family`** - confirmed by grep across `app/`: Pundit is explicitly
  re-pointed, `def pundit_user; Current.user; end` with the comment "Pundit uses current_user by default, but this
  app uses Current.user" - `app/controllers/application_controller.rb:12-15`.
- Session is established in `Authentication#authenticate_user!` from a signed cookie, setting `Current.session`
  - `app/controllers/concerns/authentication.rb:18-29`; cookie lookup `:31-41`. `skip_authentication` exists for
  public surfaces `:11-14`.
- Family scoping helpers on `Current`: `accessible_accounts` (`:21-24`), `finance_accounts` (`:26-29`),
  `accessible_entries` (`:31-34`, joins accounts through `Account.accessible_by`), `account_share_version` (`:41-45`).
- Tenancy is enforced with **model scopes, not a default_scope**. `Account.accessible_by(user)`  - 
  `app/models/account.rb:70-74` (owner OR shared). Related scopes: `writable_by` `:97-101`, `annotatable_by`
  `:105-110`, `included_in_finances_for` `:113-121`, `accessible_by_all_active_members` `:80-94`.
  Controllers start from `Current.family.<assoc>` and merge those scopes, e.g.
  `Current.family.transactions.joins(entry: :account).merge(Account.accessible_by(Current.user))`  - 
  `app/controllers/transactions_controller.rb:570-574`.

### 2.2 Authorization: Pundit **and** a custom permission helper

Two mechanisms coexist; do not assume Pundit is applied everywhere.

1. **Pundit** is included (`app/controllers/application_controller.rb:6`) but `authorize`/`policy_scope` are used in
   only a handful of controllers: `app/controllers/admin/families_controller.rb:7`, `app/controllers/admin/users_controller.rb:8-9`,
   `app/controllers/admin/sso_providers_controller.rb:8-9`. Policies: `app/policies/application_policy.rb`,
   `account_policy.rb`, `family_policy.rb`, `user_policy.rb`, `sso_provider_policy.rb` (that is the entire
   `app/policies/` directory). There is **no `verify_authorized` after-action** and **no `rescue_from
   Pundit::NotAuthorizedError`** - noted in-repo at `app/controllers/admin/users_controller.rb:133` and `:148`.
   Representative policy: `AccountPolicy#update?` requires `:owner`/`:full_control` via `record.permission_for(user)`
   - `app/policies/account_policy.rb:12-15`; `Scope#resolve` delegates to `scope.accessible_by(user)` `:33-37`.
2. **`AccountAuthorizable#require_account_permission!(account, level = :write, redirect_path: nil)`** is the
   dominant mechanism in web controllers - `app/controllers/concerns/account_authorizable.rb:10-29`. Levels:
   `:write` -> `[:owner, :full_control]`, `:annotate` -> owner or `AccountShare::ANNOTATE_PERMISSIONS`, `:owner`.
   On denial it redirects HTML / streams a redirect for Turbo / returns 403 JSON. Representative call:
   `app/controllers/transactions_controller.rb:145` (`create`), `:251` (`update_tags`, `:annotate`).
   Strong-params are additionally filtered by permission: `#permitted_entry_params`  - 
   `app/controllers/transactions_controller.rb:711-733` (read_write users get only notes/category/merchant/tags;
   read_only gets `{}`).
3. Role gates live directly on `ApplicationController`: `require_admin!` (`:46-55`) and `require_non_guest!` (`:59-68`).
4. API surface uses Doorkeeper scopes, not Pundit: `authorize_scope!(required_scope)`  - 
   `app/controllers/api/v1/base_controller.rb:197`; e.g. `app/controllers/api/v1/accounts_controller.rb:59`.

---

## 3. Request / routing conventions

- Base class is plain `ActionController::Base` (`class ApplicationController < ActionController::Base`  - 
  `app/controllers/application_controller.rb:1`), including `Authentication`, `AccountAuthorizable`,
  `SafePagination` and `Pundit::Authorization` (`:2-8`). **There is no `Api::V1::BaseController < ApplicationController`
  inheriting Pundit for HTML**; the API base is `app/controllers/api/v1/base_controller.rb`.
- Thin controllers: business logic sits in models/concerns/POROs under `app/models/` (`docs/llm-guides/architecture.md:12-15`).
  A large controller is the exception, and `TransactionsController` (879 lines) shows the intended split - the
  search object is `Transaction::Search` (`app/controllers/transactions_controller.rb:25`) and entry form/permission
  logic is delegated to concerns.
- Routes: `config/routes.rb`. Transactions are `resources :transactions, only: %i[index new create show update destroy]`
  with member routes `unlock`, `merge_duplicate`, `convert_to_trade`, `mark_as_recurring` and `patch :tags`  - 
  `config/routes.rb:573-593`; namespaced helpers come first, `namespace :transactions` with
  `resource :categorize, only: %i[show create]` plus collection `patch :assign_entry` / `get :preview_rule`
  - `config/routes.rb:564-571`.
- Concrete Turbo Frame/Stream example (route -> controller -> view -> frame id):
  1. Route: `config/routes.rb:567-569` -> `GET /transactions/categorize`, `PATCH .../categorize/assign_entry`.
  2. Controller: `Transactions::CategorizesController < ApplicationController` - `app/controllers/transactions/categorizes_controller.rb:1`;
     scopes everything through `Current.accessible_entries` (`:10`, `:31`, `:95`). `#assign_entry` (`:94-118`) builds
     `turbo_stream.remove("categorize_entry_#{entry.id}")` and `turbo_stream.replace("categorize_remaining", ...)` /
     `"categorize_group_summary"` (`:106-116`), then `render turbo_stream: streams`.
  3. View: the frame is opened in `app/views/transactions/categorizes/_entry_row.html.erb:1` as
     `turbo_frame_tag "categorize_entry_#{entry.id}"`; the summary frame is
     `app/views/transactions/categorizes/_group_summary.html.erb:1` (id `categorize_group_summary`),
     and the count frame `_remaining_count.html.erb:1` (id `categorize_remaining`).
  4. Client glue: `data: { entry_id:, action: "change->categorize#assignEntry" }` - `_entry_row.html.erb:18`.
  5. Stimulus sends a `PATCH` with `Accept: text/vnd.turbo-stream.html` and renders with
     `Turbo.renderStreamMessage(html)` - `app/javascript/controllers/categorize_controller.js:149-163`.
  A second, simpler example is `TransactionsController#update`'s `format.turbo_stream` block replacing
  `dom_id(@entry, :header)`, `dom_id(@entry, :protection)`, `dom_id(@entry)`
  - `app/controllers/transactions_controller.rb:212-242`, whose frames are
  `app/views/transactions/_transaction.html.erb:11-12` and `app/views/transactions/_notes.html.erb:2`.
- Other Turbo idioms present: `stream_redirect_back_or_to(...)` for a Turbo-stream redirect
  (`app/controllers/transactions_controller.rb:681`, `app/controllers/concerns/account_authorizable.rb:25`);
  `turbo_stream.action(:redirect, path)` in the categorizer (`categorizes_controller.rb:50`).
  Conventional partials are `app/views/**/_partial.html.erb`, rendered with explicit `locals:`.

### 3.1 Stimulus

- Controllers live in `app/javascript/controllers/*_controller.js` (125 files, plus `index.js` and `application.js`);
  file name maps to the `data-controller` token with underscores -> dashes
  (`categorize_controller.js` -> `data-controller="categorize"`).
- Representative: `app/javascript/controllers/categorize_controller.js:1-15` - `import { Controller } from "@hotwired/stimulus"`,
  `static targets = [...]`, `static values = { assignEntryUrl: String, position: Number, previewRuleUrl: String, transactionType: String }`
  (i.e. `data-categorize-assign-entry-url-value`).
- Usage in markup: `app/views/transactions/categorizes/show.html.erb:3` (`data-controller="categorize"`) and
  `:10`, `:28` for frames; list-level usage `app/views/transactions/_list.html.erb:3`
  (`data-controller="bulk-select checkbox-toggle drag-and-drop-import"`).
- Conventions to follow: plain ESM classes, `connect()`/`disconnect()` lifecycle with paired listener
  add/remove (`categorize_controller.js:17-26`), guard `has<X>Target`, CSRF header read from
  `meta[name="csrf-token"]` (`:120`), no inline jQuery, no server calls via `fetch` without the Turbo-stream `Accept`.

---

## 4. Testing conventions

- Framework: **Minitest only** for behavioral tests; RSpec/rswag is documentation-only
  (`docs/llm-guides/testing.md:3-5`). `test/` mirrors `app/`; files are `*_test.rb` (`testing.md:7`).
- Boot: `test/test_helper.rb` requires `minitest/autorun`, `mocha/minitest`, `aasm/minitest`, `webmock/minitest`,
  `rack/test` (`test/test_helper.rb:20-26`); VCR is configured to `test/vcr_cassettes` with sensitive-data filters
  (`:32-57`). Parallelization is on by default and disabled by `DISABLE_PARALLELIZATION=true` (`:67`).
  `fixtures :all` (`:81`); `Setting.clear_cache` runs before every test (`:88`).
- Family/user setup in tests comes from fixtures, not factories: `families(:dylan_family)`, `users(:family_admin)`,
  `accounts(:depository)` - fixtures at `test/fixtures/families.yml:4`, `test/fixtures/users.yml:5`, `test/fixtures/accounts.yml:1`
  (that file has ~90 fixture files, see `test/fixtures/`). Canonical pattern:
  ```ruby
  setup do
    @account = @syncable = accounts(:depository)
    @family = families(:dylan_family)
    @admin = users(:family_admin)
  end
  ```
  - `test/models/account_test.rb:6-11`. Controller tests sign in with the helper:
  `sign_in @user = users(:family_admin)` - `test/controllers/transactions_controller_test.rb:8`;
  `sign_in` is defined in `test/test_helper.rb:93-96` and also sets `Current.session`. Turbo-frame requests are
  tested by sending the header: `get transaction_url(@entry), headers: { "Turbo-Frame" => "drawer" }`
  - `test/controllers/transactions_controller_test.rb:32`.
- Test-data helpers instead of big fixtures: `EntriesTestHelper#create_transaction/create_valuation/create_trade`
  - `test/support/entries_test_helper.rb:2-40` (referenced by `testing.md:10`). Shared interface tests live in
  `test/interfaces/**` and are auto-required at `test/test_helper.rb:156`; they are mixed in, e.g.
  `include SyncableInterfaceTest, EntriesTestHelper, ActiveJob::TestHelper` - `test/models/account_test.rb:4`.
- Stubbing policy: Mocha (`expects`/`stubs`), `OpenStruct` for mock instances, no factories
  (`docs/llm-guides/testing.md:17-19`). VCR for external calls with cassettes in `test/vcr_cassettes/`
  (17 cassette files); representative usage `test/models/provider/plaid_test.rb:24`,
  `test/interfaces/exchange_rate_provider_interface_test.rb:7`. WebMock is loaded globally
  (`test/test_helper.rb:25`), so any un-stubbed HTTP call fails.
- Exact commands (all verified against `docs/llm-guides/development.md:16-31` and `:42-49`):
  | Purpose | Command |
  | --- | --- |
  | Full suite | `bin/rails test` |
  | One file | `bin/rails test test/models/account_test.rb` |
  | One test at a line | `bin/rails test test/models/account_test.rb:42` |
  | Reset test DB then test | `bin/rails test:db` |
  | System tests | `DISABLE_PARALLELIZATION=true bin/rails test:system` |
  | Ruby lint | `bin/rubocop` (pre-PR: `bin/rubocop -f github -a`) |
  | ERB lint | `bundle exec erb_lint ./app/**/*.erb -a` |
  | JS/TS lint | `npm run lint` (fix: `npm run lint:fix`) |
  | Biome format check / fix | `npm run format:check` / `npm run format` |
  | Security | `bin/brakeman --no-pager` |
  Note `bin/rubocop` is the documented lint entry point; `.rubocop.yml` was not read for this audit, so individual
  cop configuration is not asserted here.

---

## 5. UI component conventions

- `app/components/` is **plain `ViewComponent`-style Ruby classes with sidecar ERB**, not Phlex and not
  `ViewComponent::Base` subclassing by default - e.g. `class DS::Button < DS::Buttonish`
  (`app/components/DS/button.rb:5`) whose `#container` builds markup with `button_to`/`content_tag`
  (`:13-19`). Rendering is `<%= render DS::Table.new(rows: payments) do |table| %>` with `with_column` slots
  (`docs/llm-guides/design-system.md:30-35`). There is no `app/components/application_component.rb` in this checkout.
- `DS::*` inventory (33 files in `app/components/DS/`, complete list):
  `action_row`, `alert`, `button`, `buttonish`, `card`, `category_select`, `detail_row`, `dialog`, `disclosure`,
  `empty_state`, `expand_toggle`, `filled_icon`, `icon_picker`, `link`, `menu`, `menu_item`, `merchant_select`,
  `note`, `pill`, `popover`, `progress_ring`, `progress_bar`, `review_row`, `search_input`, `section`,
  `segmented_control`, `select`, `sparkline`, `tab`, `table`, `tabs`, `tag_select`, `toggle`, `tooltip`.
  (Files: `app/components/DS/*.rb` - `alert.rb`, `button.rb`, ... `table.rb` etc.)
- Reuse rule: reach for `DS::Alert`, `DS::Button`, `DS::Disclosure`, `DS::Dialog`, `DS::Menu` etc. before
  hand-building (`docs/llm-guides/design-system.md:8-12`); tables must use `DS::Table`, not hand-written `<table>`
  (`:24-28`). Icons: use the `icon` helper (`app/helpers/application_helper.rb:35-56`), never `lucide_icon`
  directly (`design-system.md:13-14`); raw SVG only inside DS primitives.
- Design tokens: the entry file `app/assets/tailwind/sure-design-system.css` only sets the `theme-dark` custom
  variant (`:12`) and imports four sheets (`:14-17`). The **GENERATED** token sheet is
  `app/assets/tailwind/sure-design-system/_generated.css` - header `:1-5` says "GENERATED - do not edit by hand.
  Source: `design/tokens/sure.tokens.json`. Build: `npm run tokens:build`".
- Complete set of handwritten `@utility` classes an author may use (38, with line numbers in
  `_generated.css`): `bg-inverse` `:315`, `bg-inverse-hover` `:320`, `bg-subdued` `:325`, `bg-overlay` `:330`,
  `bg-loader` `:335`, `text-primary` `:339`, `text-inverse` `:344`, `text-secondary` `:349`, `text-subdued` `:354`,
  `shadow-border-xs|sm|md|lg|xl` `:359-379`, `border-primary` `:384`, `border-secondary` `:389`, `border-divider` `:394`,
  `border-subdued` `:398`, `border-solid` `:403`, `border-destructive` `:408`, `border-inverse` `:413`,
  `divide-subdued` `:418`, `button-bg-primary(-hover)` `:423-431`, `button-bg-secondary(-hover)` `:433-441`,
  `button-bg-secondary-strong(-hover)` `:443-451`, `button-bg-disabled` `:453`, `button-bg-destructive(-hover)` `:458-466`,
  `button-bg-ghost-hover` `:468`, `button-bg-outline-hover` `:476`, `button-bg-accent(-hover)` `:481-489`,
  `tab-item-active` `:491`, `tab-item-hover` `:496`, `tab-bg-group` `:501`.
  Color-scheme tokens also exist and are used with opacity/variants: `bg-container`, `bg-container-hover`,
  `bg-container-inset(-hover)`, `bg-surface(-hover)`, `bg-surface-inset(-hover)`, `text-success|warning|destructive|info|link`,
  `border-destructive`, defined as `--color-*` in `_generated.css:12-44` (light) and `:251-269` (dark override).
- **Forbidden:** raw Tailwind palette classes (e.g. `text-green-600`) and hex literals  - 
  `docs/llm-guides/design-system.md:6-7` and `AGENTS.md` (UI changes section). Note a live violation of exactly
  this rule in the audited tree: `app/views/transactions/categorizes/_entry_row.html.erb:10` uses
  `text-green-600`; do not copy it. Also forbidden without explicit permission: adding styles to
  `sure-design-system.css` or `app/assets/tailwind/application.css` (`design-system.md:16-17`), i.e. the generated
  file must only change via `npm run tokens:build`. Use scale tokens rather than arbitrary pixel values (`:15`).
- Escalation policy: DS-reuse and repeated-shape violations are close/rewrite; token, icon/SVG, localization and
  scale violations are request-changes (`docs/llm-guides/design-system.md:18-19`).
- Privacy convention (not in the guides, found in code): money shown in views carries the `privacy-sensitive`
  class, implemented in `app/assets/tailwind/privacy-mode.css:2-12` (hidden when `html.privacy-mode`).
  Example use: `app/views/transactions/categorizes/_entry_row.html.erb:10`.

---

## Explicitly absent / not determined

- No `*_cents` columns and no integer-cents storage anywhere in `db/schema.rb`; cents exist only in
  `app/views/api/v1/**/*.jbuilder` via `app/helpers/api/v1/money_helper.rb:4`.
- No `app/serializers/` directory exists (glob returned nothing); API JSON is jbuilder-based.
- No `current_user` / `current_family` helpers exist in `app/`.
- No global `default_scope` tenancy; scoping is explicit via `Account.accessible_by` /
  `Current.accessible_entries` (`app/models/account.rb:70-74`, `app/models/current.rb:31-34`).
- No `rescue_from Pundit::NotAuthorizedError` and no `verify_authorized`; Pundit covers only the `admin/*`
  controllers plus the policies listed in §2.2.
- Not determined in this audit (would need files outside the read budget): `.rubocop.yml` cop configuration,
  CI workflow contents (only referenced from `docs/llm-guides/development.md:55-56`), `spec/swagger_helper.rb`
  schema details beyond the `*_cents` fields, and whether `app/services/` is a sanctioned location
  (`docs/llm-guides/architecture.md:12-13` says organize logic in `app/models/` concerns/POROs, yet
  `app/services/auto_sync_scheduler.rb` is referenced by the same guide at `:113-114`).
