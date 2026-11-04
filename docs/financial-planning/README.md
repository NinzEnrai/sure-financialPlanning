# Financial planning module — a plain-language guide

This module turns Sure from a record of what happened into a plan for what to do
next. It is built for the household, not for an adviser's back office: every
card answers one question, states the data it used, and says "not enough data"
instead of inventing a number.

It is deliberately **not** a regulated advisory service. It shows the
household's own numbers, the checks a planner would run, and the questions to
ask. It never recommends a product, never places a trade, and never files tax.

The research behind it is in advisory-framework.md in this folder.

## The planning page at a glance

Open **Investments → Financial Planning** (preview feature). In order:

| Card | Question it answers | Data it needs |
| --- | --- | --- |
| Health check | Where should we look first? | Savings, cash, debt, goals, insurance |
| Savings rate | How much of income are we keeping? | Transactions (12 months) |
| FIRE progress | How far from financial independence? | Net worth, spending, withdrawal rate |
| Emergency fund | How long could we last without income? | Bank/cash balances, spending |
| Debt | What is the debt costing us, and when is it gone? | Liabilities, rates, minimum payments |
| Portfolio return | What did the money we put in earn? | Trades or contributions, portfolio value |
| Goal funding | Can we afford all our goals at once? | Goals, linked balances, pace |
| Allocation & concentration | Is one position deciding the outcome? | Holdings, security metadata |
| Cash-flow forecast | Will cash last until payday? | Cash, income, spending, debt, premiums |
| Coaching | Is anything in tension? | The same figures, compared |
| Data confidence | What is missing behind these figures? | Accounts, prices, FX, classification |
| Tax readiness | What tax work does the data support? | Trades, prices, purchase dates, accounts |
| Realised gains | What did we sell this year, and what did it realise? | Trades, prices, FX rates |
| Capital gains estimate | What is each person's taxable gain? | The above, per account owner |
| Tax harvesting | Are there losses worth booking? | Open lots, latest prices |
| Tax profile | What has each person declared for tax? | Regime and declared deductions |
| Budget split | Are we inside our own 50/30/20? | Categories, transactions |
| Wealth projection | Where could current savings take us? | Net worth, savings pace, growth |
| Retirement stress test | How likely is the money to last? | Age, spending, savings, growth assumption |

A **Year in review** page (linked from the page header) rolls the important
figures into one printable summary with a review date.

## What can be changed

- **Emergency target** — 1–24 months, directly on the emergency fund card.
- **Budget split** — needs/wants/savings shares that must total 100.
- **Risk profile** — conservative/moderate/aggressive; frames the allocation
  card's conventional equity range and the rebalancing plan.
- **Goal priority** — high/medium/low; orders the goal-funding plan.
- **Goal inflation** — optional; the plan uses the future-rupee target while the
  goals page keeps the nominal figure.
- **Household and protection** — people (with ages and dependants) and insurance
  policies (cover, premiums, renewals, nominees).
- **Retirement age** — set on the retirement stress test card; age comes from
  the "self" household member's date of birth.
- **Tax profile** — per person: regime and declared deductions, for the
  household's CA. Declarations only; the module computes no tax from them.

## How the numbers stay honest

- **Unknown is a state.** A household without spending history, income, prices
  or rates sees "not enough data", never a fabricated zero.
- **Basis is printed.** Portfolio return shows its trade-based assumption, and
  says when the solver's answer is ambiguous.
- **Guides are labelled as guides.** The 10x income life-cover rule, the 5–10%
  premium band, the 3–6 month buffer, concentration bands and the equity ranges
  are stated as practitioner heuristics, not rules.
- **Tax is estimated, not filed.** FIFO lots, fees, splits and currency at
  transaction dates; set-off and the Indian long-term exemption are applied,
  but no tax rate is quoted, and every tax card says a chartered accountant
  must review it.
- **No orders, no products, no shaming.** The coaching card names tensions and
  stops there.

## The tax layer, step by step

1. **Import purchase dates** — Zerodha Console → Reports → Tradebook, exported as
   CSV, uploaded from the tax-readiness card. Safe to run twice; unknown symbols
   are reported, not invented.
2. **FIFO lots** (Portfolio::TaxLots) — oldest shares first, fees capitalised,
   splits applied on their ex-date, internal transfers ignored, unknown-origin
   sales flagged.
3. **Realised gains** (FinancialPlanning::RealisedGains) — this year's sales in
   the family currency at their transaction dates.
4. **Capital gains estimate** (FinancialPlanning::CapitalGainsEstimate) — per
   account owner, short-vs-long set-off, ₹1.25 lakh Indian long-term exemption,
   carried-forward losses, debt funds slab-taxed.
5. **Harvesting** (FinancialPlanning::TaxHarvesting) — open lots at a loss,
   with the costs of selling stated.
6. **Schedule FA** — foreign holdings raise a disclosure note on the readiness
   card.

## Verifying it locally

From the repository root (the development environment is set up on this host):

    bin/rails test                                   # full suite, must be green
    bin/rails test test/models/financial_planning    # planning models
    bin/rails test test/models/portfolio             # lots, XIRR, flows
    bin/rubocop                                      # Ruby style
    bundle exec erb_lint ./app/**/*.erb              # templates

The full suite covers the empty, single-account, multi-currency and missing-data
paths for these cards; if a card changes, change its tests with it.

## Where the code lives

- Models: app/models/financial_planning/ (one PORO per card), plus
  app/models/portfolio/tax_lots.rb and app/models/portfolio/console_tradebook.rb.
- Controller: app/controllers/financial_planning_controller.rb (plus the
  household-members and insurance-policies controllers).
- Views: app/views/financial_planning/ (one partial per card).
- Locales: config/locales/views/financial_planning/en.yml.
- The owner-facing project record stays in PROJECT_DETAILS.md.

## Known limitations

- Tax rates, surcharge and cess are **not** applied; rates must be re-checked
  against the current Finance Act. The tax-profile card records declared
  deductions but does not compare regimes or compute any liability.
- Asset classification for allocation and tax rules relies on security metadata;
  unclassified holdings are shown as such and debt-fund detection needs the
  mutual-fund + fixed-income flags.
- The cash-flow forecast is average-based, not a day-level bill calendar.
- The retirement stress test draws independent returns; real markets cluster
  their bad years, and taxes, fees and health shocks are outside the model.
- Insurance cover adequacy for health is a country-aware guide, not advice.
- Household members are add/remove only; income per member and editing are not
  implemented yet.
