# Advisory framework for Sure's financial planning module

**Status:** product research document, November 2026.
**Audience:** the owner and whoever builds the next planning features.
**Scope:** one practitioner's view of what a complete household financial plan covers, mapped honestly onto what this Rails app can compute today, plus a build order.

This is not financial advice, not a SEBI-registered investment advisory service, and not a substitute for a qualified adviser, chartered accountant or lawyer. It is a product framework. Nothing here recommends a specific mutual fund, insurer, policy or security. The app should stay an **educational planning and diagnostic tool**: it can show a household its own numbers, the checks a planner would run, and the questions to ask. It should not present itself as telling someone what to buy.

Tax figures are treated as **unverified** throughout. The app's own project notes say the same thing: rates, limits and thresholds must be re-checked against the current Finance Act before any number ships. Where this document gives a figure, it is there to show the shape of the calculation, not to be trusted as this year's law.

---

## Contents

0. The short version
1. What "complete" means: the CFP process, mapped to this app
2. The household picture: what data the app already holds
3. The eleven domains
   3.1 Cash flow and budgeting
   3.2 Emergency and liquidity reserve
   3.3 Debt management
   3.4 Protection: health, life and nominations
   3.5 Savings and investing: allocation, diversification, rebalancing, fees
   3.6 Retirement and FIRE
   3.7 Tax planning for India
   3.8 Goal-based planning
   3.9 Estate and succession basics
   3.10 Behavioural coaching
   3.11 Review cadence
4. Data gaps and schema proposals
5. Feature map
6. Prioritised build order
7. Benchmarks and assumptions reference
8. How the features should look and behave
9. Source notes and verification log
Appendix A. Plain-English glossary
Appendix B. India-specific annual checklist

**How to read it.** If you only read one section, read 0 and 6. If you are deciding what to build next, read 4, 5 and 6 together. If you are checking whether a number on screen is trustworthy, read 2.4 and 7.

**Confidence labels used in this document:**

| Label | Meaning |
| --- | --- |
| Built | The app already computes this, or nearly does, from existing data. |
| Partial | The inputs exist but a definition, a classification or a UI is missing. |
| Missing | The data does not exist in the schema, so the feature needs a migration or a manual input. |

**Effort labels:** S is roughly one to three focused days, M is one to two weeks, L is three weeks or more for one developer, including tests and copy. They assume the house style in the repository guides and no new external service.

---

## 0. The short version

The app already has the hard, unglamorous half of a financial plan: a real balance sheet, a real income statement, account-level debt, goals with linked accounts, holdings with cost basis and daily prices, an XIRR engine, a savings-rate engine, a 50/30/20 analyzer, a FIRE calculator and an emergency-fund coverage card. Most "financial planning" features in consumer apps are built on estimates; this app is built on the household's actual ledger, which is a genuine advantage.

What it does not have is the **person** and the **protection** side of planning. There is no date of birth, no dependant, no risk profile, no insurance policy, no nominee, no tax profile, no purchase date for an existing holding, and no target asset allocation. A veteran adviser spends much of a first meeting on exactly those things, because they decide how much risk a household can actually carry and what happens if the income stops.

The recommended order is therefore:

1. **P0, no migrations:** turn the planning page into an advisory dashboard from data that already exists. A health scorecard, a debt command centre, an XIRR/return card, a goal funding plan, a data-confidence panel and a tax-year readiness checklist. These make the app feel like a planner rather than a set of unrelated calculators, and they expose the gaps honestly instead of hiding them.
2. **P1, small schema:** add the household profile (dates of birth, dependants), the protection register (policies, cover, premiums, nominees, renewals), a target allocation, editable budget targets, and an annual review report. This is where the app stops being a portfolio tracker and starts being a planning tool.
3. **P2, larger schema and logic:** the India tax workspace (profile, regime comparison, deduction tracking), capital gains on FIFO lots with the Console CSV import already scoped in the project notes, rebalancing, fee audit, retirement income and withdrawal planning, estate/nomination register and Schedule FA.
4. **Later:** Monte Carlo and sequence-risk simulation, advisor export, document vault, multi-person tax planning, automated rebalancing (which the app should probably never do).

Five findings deserve to be stated up front because they change how existing numbers should be read:

- **FIRE progress uses total net worth, including the house and vehicles.** A self-occupied home does not pay for groceries. The FIRE card should show investable net worth, or both figures, before anyone treats the percentage as a retirement answer.
- **The FIRE target uses today's expenses while the projection compounds at a nominal growth rate.** If expenses inflate and the corpus does not, the target is understated and the ETA is optimistic. The app needs either a real return or an inflation-aware target.
- **Loan payments are counted as expenses in full, including principal.** Principal repayment builds equity; treating it as consumption distorts both the savings rate and the 50/30/20 split. This is a definitional choice that needs to be visible.
- **Tax-advantaged accounts are excluded from the income statement.** That is sensible for day-to-day budgeting, but it means PPF, EPF and NPS contributions can be invisible in the savings-rate card unless they are recorded as transfers from a counted account. A retirement saver can look like a spender.
- **The app cannot yet tell essential spending from discretionary spending.** The emergency fund uses total expenses as a conservative stand-in, which is defensible, but "six months of essentials" and "six months of everything" are different numbers.

None of these are bugs in the sense of wrong arithmetic. They are **definitional choices that need to be surfaced**. A veteran adviser would ask "what is included in this number?" before trusting it, and the app should answer that question on the card itself.

---

## 1. What "complete" means: the CFP process, mapped to this app

The CFP Board's practice standards describe financial planning as a seven-step process. The steps are useful as a completeness checklist for the product, not as a claim that the app is a CFP.

| Step | What it means in practice | What this app already supports | What is missing |
| --- | --- | --- | --- |
| 1. Understand the client's personal and financial circumstances | Household, ages, dependants, health, income stability, assets, liabilities, goals, risk attitude, existing policies | Accounts, balances, transactions, holdings, loans, cards, goals, family members who log in | Ages, dependants, health, income stability, insurance, tax profile, risk attitude |
| 2. Identify and select goals | What the money is for, by when, with what priority | Goals with target amount, target date, linked accounts, progress, pace | Goal priority, goal type, inflation, owner, conflict detection |
| 3. Analyse the current course and alternatives | Is the current saving/spending/investing path going to get there? What else could work? | Savings rate, 50/30/20, net worth, debt, FIRE projection, XIRR engine | Scenario comparison, what-if on goals, tax-adjusted returns, protection gap |
| 4. Develop the recommendations | Specific, prioritised actions across all domains | Almost nothing: the app shows numbers, not a recommended sequence | Rules/checklists that say "do this next", with the reasoning |
| 5. Present the recommendations | Explain trade-offs, assumptions, alternatives | Cards, charts, disclosures, assumptions forms | A single coherent plan view and a printable review |
| 6. Implement the recommendations | Open accounts, set up SIPs, buy cover, change nominations | No execution by design | Deliberate: this app should not execute trades or sell products |
| 7. Monitor progress and update | Review, rebalance, update goals and cover | Insights feed, goal tracking, daily prices, sync | Review cadence, last-reviewed date, annual report, rebalancing |

Two conclusions follow.

First, the app is strongest at steps 1 and 3 and weakest at 2, 4 and 7. The cheapest way to feel like a planner is not another calculator; it is to close the loop between "here are your numbers" and "here is what to look at next, and when".

Second, the app should stop at **diagnosis and education**, not at **product recommendation**. In India, investment advice is regulated by SEBI, and insurance advice is regulated by IRDAI. A self-hosted personal tool that says "your term cover looks low relative to your liabilities; talk to a licensed adviser" is education. A tool that says "buy this term plan from this insurer" is a different regulatory animal. The same distinction applies to tax: the app can estimate and produce a schedule to hand to a CA; it should not file a return.

### 1.1 The domains a veteran actually covers

The list below is the working structure of this document. It matches the topics SEBI's investor-education material lists for personal finance (saving, goal setting, budgeting, inflation and investing, debt management, insurance, retirement planning and estate planning) and the domains in the CFP process.

1. Cash flow and budgeting
2. Emergency and liquidity reserve
3. Debt management
4. Protection: health, life, disability, property, nominations
5. Savings and investing: asset allocation, diversification, rebalancing, costs
6. Retirement and FIRE: accumulation, withdrawal, sequence risk
7. Tax planning for India
8. Goal-based planning
9. Estate and succession basics
10. Behavioural coaching
11. Review cadence

### 1.2 The advice ladder

It helps to be explicit about how far up the ladder a feature goes.

| Rung | What it looks like | Should this app do it? |
| --- | --- | --- |
| 0. Record | Store accounts, transactions, holdings, policies | Yes, already does |
| 1. Describe | Show net worth, cash flow, allocation, debt | Yes, already does |
| 2. Diagnose | Compare to a benchmark; flag a gap; show the trend | Yes, the P0 layer |
| 3. Educate | Explain why the gap matters and what the options are | Yes, with neutral copy |
| 4. Recommend a course of action | "Pay the card first, then build the buffer" | Yes, if framed as a planning heuristic, not a personalised product recommendation |
| 5. Recommend a product | "Buy this fund or this policy" | No |
| 6. Execute | Place the trade, buy the policy | No |

The P0 features are deliberately rung 2 and 3. The P1 features add rung 4 for protection and goals. Nothing in this framework requires rung 5 or 6.

---

## 2. The household picture: what data the app already holds

This section is the inventory that every later "can we build it?" answer depends on. It is deliberately detailed, because most planning features fail not on arithmetic but on a missing input that nobody noticed until the card rendered zero.

### 2.1 The data inventory

| Planning data | Where it lives | What it enables | Quality caveats |
| --- | --- | --- | --- |
| Net worth | accounts, balances, valuations, holdings, exchange_rates | Balance sheet, FIRE progress, wealth projection | Includes self-occupied property and vehicles; family currency conversion; excluded accounts |
| Cash flow | entries, transactions, categories, transfers | Income, expenses, savings rate, 50/30/20, emergency months | Pending excluded; one-time excluded from analytics; loan principal counted as expense |
| Income | transactions classified as income | Savings rate, DTI, affordability | Recorded inflows, not gross salary; irregular income; taxes may or may not be recorded |
| Expenses | transactions classified as expense | Budget split, emergency fund, FIRE target | No essential/discretionary flag; categories are not typed income vs expense |
| Debt | loans, credit_cards, balances | Debt dashboard, DTI, payoff projection, credit utilisation | Credit limit is not a column; India loan subtypes are missing; EMI day not stored |
| Investments | holdings, securities, trades, prices | Allocation, concentration, XIRR, cost basis, tax lots | Security asset_class is not populated; purchase dates missing; some prices stale |
| Goals | goals, goal_accounts, goal_pledges | Goal progress, pace, monthly target, projections | No priority, inflation, owner or goal type |
| Budgets | budgets, budget_categories, categories, planning_settings | Budget vs actual, 50/30/20 buckets | Targets hardcoded; bucket mapping is a heuristic |
| Tax | investment subtypes, categories, trades, prices | Tax-treatment labels, capital gains foundation | No tax profile, regime, slab, deductions, TDS, advance tax, purchase dates |
| Protection | insurance expense category, investment subtype "life_insurance" | Almost nothing | No policy, cover, premium, renewal or nominee data |
| Estate | none | Nothing | No nominations, will, executor, guardianship or documents |
| Household | users, families, account_shares, accounts.owner_id | Who can see what; per-person ownership of accounts | No ages, dependants, relationships, health or risk profile |
| Prices and FX | security_prices, exchange_rates | Valuation, returns | Missing FX rates fall back to 1.0 with a logged warning; illiquid securities go stale |

### 2.2 Derived figures the app can already produce

These are the building blocks for the P0 dashboard. Most of them already exist as methods; the work is presentation and definition, not new data.

| Figure | How it is computed today | Where it lives | Advisory use |
| --- | --- | --- | --- |
| Net worth | Assets minus liabilities, in family currency | BalanceSheet | Overall progress; not the same as investable wealth |
| Investable net worth | Net worth excluding property, vehicles and other non-income assets | Derivable from accounts by accountable_type | FIRE and retirement |
| Monthly income | IncomeStatement totals for a period | IncomeStatement | Savings rate, DTI, affordability |
| Monthly expenses | IncomeStatement totals, minus investment contributions where relevant | IncomeStatement, SavingsRate | Budget, emergency fund, FIRE |
| Savings rate | Cash savings plus invested, divided by income | FinancialPlanning::SavingsRate | The single most useful behavioural metric |
| Trailing savings rate | Income-weighted over 6 or 12 months | SavingsRate#trailing_rate | Removes one-month noise |
| 50/30/20 split | Category buckets against income | FinancialPlanning::BudgetAnalyzer | Spending shape, not just total |
| Emergency months | Liquid balances divided by average monthly expenses | FinancialPlanning::EmergencyFund | Resilience |
| Debt-to-income | Monthly debt service divided by recorded monthly income | Derivable from loans, cards and income | Leverage and affordability |
| Credit utilisation | Card balance divided by inferred limit | Derivable from credit_cards | Credit health |
| Loan payoff date | Amortisation or payoff projection | Loan#payoff_projection | Debt freedom date |
| Interest cost next 12 months | Amortisation schedule and card APR | Loan, CreditCard | The real cost of debt |
| Portfolio XIRR | Money-weighted return over classified flows | Portfolio::Xirr, Portfolio::MoneyWeightedReturn | What the investor actually earned |
| Holding weights | Holding value divided by account or portfolio value | Holding#weight | Concentration |
| Goal funding gap | Target minus current backing; monthly target minus pace | Goal | On-track/behind |
| FIRE multiple | Annual expenses divided by withdrawal rate | FinancialPlanning::FireProgress | Retirement number |
| Coast FIRE status | Projected balance at target date versus target | FireProgress | "Can I stop saving so hard?" |
| Budget variance | Budgeted versus actual by category | Budget, BudgetCategory | Spending control |

### 2.3 The India-specific data the app already has

The fork has more India support than a generic Sure install, and the framework should build on it rather than reinvent it:

- **Currency and formatting:** INR as a family currency, and a lakh/crore number format independent of currency. This matters: an Indian reader parses 12,34,567 faster than 1,234,567, and a planning screen that formats money the wrong way loses trust immediately.
- **Investment subtypes:** NPS, APY, life insurance, Indian stocks, Indian equity, Indian ETF, EPF, PPF, SSY, NSC, SCSS, FD, RD, POMIS, KVP, G-Sec, SDL, corporate bond, infrastructure bond, tax-free bond, gold ETF, gold mutual fund, SGB, mutual fund. This is a usable taxonomy for both allocation and tax hints.
- **Tax-treatment labels:** each investment subtype carries taxable, tax_deferred, tax_exempt or tax_advantaged. The family uses that to exclude tax-advantaged accounts from the income statement.
- **Categories:** insurance, taxes, loan payments, gifts and donations, fees, savings and investments are built in. They are enough to find insurance premiums, tax payments, donations and loan EMIs in the ledger.
- **Kite/Zerodha:** holdings, trades, mutual funds via AMFI, daily prices. This is the source of the owner's actual portfolio data.
- **AMFI scheme codes:** mutual funds can be resolved to official NAVs rather than a US price provider.
- **India-aware taxonomy elsewhere:** country list, Indian English locale, INR default when the country is India.

What is not India-specific: tax rules, insurance, retirement products and estate law. The investment subtype list is a vocabulary, not a tax engine.

### 2.4 Data-quality caveats that must appear on screen

These are the "read the label" items. Each one should be visible somewhere near the number it affects, ideally in a disclosure on the card rather than in a documentation page nobody opens.

1. **Family is not a tax unit.** The app is family-scoped. Income tax is assessed per person (per PAN). Any tax figure must be per person and must never present a household total as one taxable person's income. Accounts already have owner_id; goals and new tax entities do not.
2. **Tax-advantaged accounts are excluded from the income statement.** PPF, EPF, NPS, SSY, NSC and similar accounts are removed from budget and cash-flow totals by design. Contributions made directly inside them are invisible; contributions recorded as transfers out of a counted account may still appear. A retirement saver can therefore look like a low saver.
3. **Loan payments count as expenses in full.** The loan_payment kind is treated as an expense for budgeting, but the principal portion is repayment of a liability, not consumption. This overstates expenses and understates the savings rate for anyone aggressively repaying a loan.
4. **Investment contributions are treated as spending by default.** The family setting investment_contributions_as_spending defaults to true. The savings-rate card adjusts for this, but other surfaces may not.
5. **FIRE progress uses total net worth.** It includes the self-occupied house, vehicles, gold and other assets that cannot fund living expenses without being sold or borrowed against. It also includes tax-advantaged retirement accounts whose access is restricted.
6. **The FIRE target does not inflate expenses.** The target is today's average annual expense divided by the withdrawal rate. The projection compounds at the configured nominal growth rate. Comparing a nominal future corpus with today's expenses overstates progress unless the growth rate is meant to be real.
7. **Missing exchange rates fall back to 1.0.** For a family with foreign accounts, a missing rate can make a converted figure wrong by a large factor. The fallback logs a warning, but a planning card should not quietly present the result as certain.
8. **Pending and one-time transactions are excluded from analytics.** That is right for a stable picture, but it means a large annual insurance premium or tax payment may not appear in the month the user expects.
9. **Security asset classification is schema-only.** The columns asset_class, asset_sub_class, sector and region exist, but nothing populates them yet; every security is unclassified. Allocation by asset class is therefore not available until a classifier or manual tagging exists.
10. **Purchase dates and lots do not exist.** Holdings carry a valuation date, not an acquisition date. Capital gains need a tradebook CSV import or forward trade capture; the project notes cover this in detail and this framework does not re-plan it.
11. **Account visibility changes the numbers.** exclude_from_reports, account shares, personal budgets and the per-user account scope mean two people in the same family can legitimately see different savings rates. That is correct for privacy; it is confusing for a shared plan unless the card says whose view it is.
12. **Recorded income is not gross salary.** The app sees inflows into counted accounts. It does not know the salary structure, HRA, employer PF, TDS or in-hand versus CTC. DTI and tax estimates based on it are approximations and must say so.
13. **Prices go stale.** Daily closes exist for many securities, but illiquid, offline or recently added securities may not have current prices. A portfolio value is only as good as its last price date.
14. **Goal earmarks are accounting, not segregation.** Money earmarked for a goal still sits in the same account as the emergency fund. The app can reserve it logically; the bank does not.
15. **The emergency fund uses total expenses.** It is a deliberately conservative stand-in for essential expenses, not a measurement of them.

### 2.5 A confidence rule for every advisory card

The single most useful design rule for this whole area: **every advisory number should carry three things** — the basis (what is included), the as-of date, and a confidence note when an input is missing or approximated.

A small DS::Disclosure at the bottom of each card is enough:

- Basis: "12-month average expenses; bank and cash accounts only; excludes investments and earmarked goal money."
- As of: "prices to 3 November 2026; FX rates to 2 November 2026."
- Confidence: "No purchase dates for 4 holdings; capital gains not included."

This is what separates a planning tool from a dashboard. It also protects the owner from the most dangerous failure mode in personal finance software: a confident-looking number built on a missing input.

---

## 3. The eleven domains

Each domain below follows the same shape: why it matters, what a veteran checks, what this app can compute today, what is missing, and what that implies for features. The feature IDs (F1, F2, ...) are defined in section 5.

### 3.0 Domain map at a glance

| Domain | Data in app today | Advisory readiness | Biggest blocker |
| --- | --- | --- | --- |
| Cash flow and budgeting | Strong | Good | Essential versus discretionary; custom targets |
| Emergency reserve | Strong | Good, and improving | Target months and "essential" definition; encumbered cash |
| Debt management | Strong | Good | Credit limit column; India loan subtypes; principal/interest split |
| Protection | Almost none | Weak | No policy, cover, premium, renewal or nominee data |
| Savings and investing | Strong but unclassified | Partial | Asset classification; target allocation; fees |
| Retirement and FIRE | Strong | Partial | Ages; inflation; investable net worth; pensions; sequence risk |
| Tax (India) | Partial | Weak | Tax profile; purchase dates; rates config; per-person |
| Goal-based planning | Strong | Good | Priority, inflation, goal type, conflict detection |
| Estate and succession | None | Missing | Nominations, will, documents |
| Behavioural coaching | Partial | Partial | Commitment devices; spending-versus-income trend |
| Review cadence | Partial | Partial | Last-reviewed date; review report; reminders |

### 3.1 Cash flow and budgeting

**Why it matters.** Every other domain is funded from the gap between income and spending. If the household does not know that gap — and most do not, because income arrives in several accounts and annual bills hide in a few months — no amount of portfolio analysis can fix the plan. Cash flow is also the earliest warning system: a savings rate that drifts down for three months is a better signal than a net worth chart that is still rising.

**What a veteran checks.**

| Check | Common benchmark | How to read it | Caveat |
| --- | --- | --- | --- |
| Savings rate | 20% of income is the 50/30/20 starting point; 30% or more for an aggressive FIRE goal | Savings (cash plus invested) divided by income | Definition matters: pre-tax or post-tax, employer PF included or not, loan principal counted as spending or not |
| 50/30/20 split | Needs 50%, wants 30%, savings 20% | Needs and wants are ceilings; savings is a floor | A starting point, not a law. Indian metro households often run higher needs because of rent, school fees and family support |
| Fixed versus variable costs | Fixed costs under roughly 50–60% of income | Rent, EMIs, insurance, school fees, utilities, subscriptions | Fixed costs are hard to cut in a crisis; they are the real fragility |
| Housing cost | Under 30% of income is the common affordability rule | Rent or EMI plus maintenance and property tax | Metro India often exceeds this; the trade-off is commute, school and family support |
| Income concentration | One earner or one employer is a risk | Share of income from the largest source | Two incomes in the same industry are less diversified than they look |
| Spending growth versus income growth | Spending should not grow faster than income for long | Year-on-year growth of each | Lifestyle inflation is the quiet killer of savings rates |
| One-off normalisation | Compare 3-month and 12-month averages | Exclude or note annual insurance, taxes, school fees, festivals | A single month can flatter or ruin a rate |
| Budget variance | Actual versus budget by category | Variance in rupees and percent | A budget that is never used is worse than no budget |
| Sinking funds | Annual bills funded monthly | Insurance premium, school fees, festivals, car service | The app can model these as goals or recurring bills |

**What this app can compute today.**

- Income and expense totals for any period, with pending and one-time transactions excluded and everything converted to the family currency.
- Savings rate, cash savings rate, total savings rate including investments, and a 12-month series.
- Trailing income-weighted savings rate over 6 or 12 months, and average monthly savings.
- 50/30/20 bucket totals, per-category spend, unassigned-category warnings, and per-category bucket overrides.
- Budgets with budgeted spending, expected income, per-category limits and rollover.
- Recurring transactions, including bills and subscriptions, with next expected dates.
- Insight generators for a savings-rate change, a spending anomaly, a subscription audit and budget pressure.
- Cash-flow graphs by category or group.

That is genuinely strong. The main definitional issue is that the app does not know which expenses are **essential**. The 50/30/20 buckets are a spending-shape heuristic, not an essentials list. "Needs" includes things a household could cut in an emergency (some transport, some utilities), and "wants" includes things it would not cut (medicines bought under a "shopping" category, for example).

**What is missing.**

- Essential versus discretionary tagging, separate from the 50/30/20 bucket. This is one flag per category (or per category and household), used by the emergency fund, the FIRE target and a "bare-bones" stress test.
- Editable 50/30/20 targets. They are constants in PlanningSetting today.
- Income typing. Categories are effectively expense categories; income is inferred from transaction direction and account type, not from a category classification. A salary, a rental receipt, a dividend and a reimbursement can all land in the same bucket.
- Irregular-income handling: a business owner or consultant needs a "lowest month" or "annual average" basis, not a single month.
- Annual and festival spending normalisation. The 12-month average helps; a dedicated sinking-fund view would help more.
- A cash-flow forecast (next 30/60/90 days) that combines recurring bills, EMIs, card dues, premiums and expected income.

**Feature implications.** The P0 scorecard should use the trailing 12-month savings rate, not the current month, and it should say which definition it used. Editable targets and an essential flag are P1 because they need a small schema change but unlock the emergency fund, FIRE and stress-test features. A cash-flow forecast is P1 and depends on recurring-transaction quality more than on new schema.

**India-specific notes.** Income is often irregular (business, consulting, agriculture), cash spending is common, and family obligations (parents, siblings, school fees) are real fixed costs. Festival spending is lumpy and predictable; it belongs in a sinking fund, not in a "bad month" narrative. Gold purchases are often savings and consumption at the same time; the app should not force them into one bucket without asking.

---

### 3.2 Emergency and liquidity reserve

**Why it matters.** The emergency fund is the difference between a bad month and a forced sale. Without one, a job loss, a medical bill or a family emergency gets funded by credit-card debt at 30–45% interest or by selling long-term investments at the worst possible time. It is the first thing a planner checks and the last thing a household wants to build, because it feels like money doing nothing.

**What a veteran checks.**

| Check | Common benchmark | Notes |
| --- | --- | --- |
| Months of coverage | 3–6 months of essential expenses | 6–12 months for a single income, variable income, dependants, a health condition or a business owner |
| What counts | Bank savings, cash, short fixed deposits, liquid or overnight funds, a sweep account | Not equity, not a credit-card limit, not a loan against securities |
| Access speed | Same day or next day | A 3-year FD is not an emergency fund |
| Currency match | Held in the currency the emergency will be spent in | A USD buffer does not pay an INR hospital bill without FX and settlement risk |
| Separation from goals | Buffer money is not earmarked for a vacation or a car | Logical separation is enough; physical separation is better |
| Replenishment | Refill after use within a defined period | A drained buffer is a new goal, not a failure to be ignored |
| Review | Annually, or when fixed costs change | Rent, school fees, EMIs and insurance change the number |
| Insurance coordination | Health cover reduces the medical-shock part of the need | Insurance is not a substitute for cash, but it changes the size of the buffer |

The 3–6 month figure is practitioner consensus, not a statutory rule. This pass could not retrieve the CFPB page that is usually cited for it (the fetch returned the site navigation but not the article body), so treat the number as a well-established heuristic rather than a verified citation.

**What this app can compute today.**

The planning module now includes an emergency-fund coverage card. Its model is a good example of the house style:

- Liquid balance is the sum of visible depository accounts the viewer can access, converted to family currency, excluding accounts deliberately kept out of reports.
- Monthly expenses are the trailing 12-month average, not the current month.
- Coverage is liquid balance divided by monthly expenses, shown in months.
- The target is six months; the minimum acceptable is three; the status is funded, building or critical.
- Shortfall or surplus is shown in rupees.
- If there is no spending history, the card says it cannot compute rather than showing zero.

There is also a second, older way to model a reserve: a **maintained goal** with target mode "months of expenses". It derives its target from the family's median monthly spend, refreshes monthly, and produces a "reserve depleted" insight if it falls below its floor. That is a better long-term home for the emergency fund than a standalone card, because it links the buffer to a specific account and lets the household pledge money to it.

**What is missing.**

- A configurable target (3, 6, 9 or 12 months) instead of a hardcoded six, and a reason field ("single income", "business income", "dependant").
- An essential-expense basis. The current card uses all expenses, which is conservative and honest, but a household with a large discretionary budget may be told it needs a buffer it does not.
- Encumbered-cash awareness. If the same savings account is earmarked to a goal, the emergency card counts it as available. A goal earmark is a logical reservation, not a legal one; the card should either subtract it or disclose it.
- A "replenish by" date after a drawdown.
- A link to the maintained goal, so the household sees one number rather than two competing ones.
- A liquidity ladder: cash, savings, liquid fund, FD with maturity date, and the penalty for breaking each.

**Feature implications.** The emergency-fund card is the right P0 baseline and should not be rebuilt. P1 should add settings (target months, include/exclude accounts, essential basis) and reconcile the card with a maintained goal so the app does not show two different "emergency fund" numbers. The scorecard should treat "coverage below three months" as the highest-priority red flag in the whole app.

**India-specific notes.** Keep the buffer in a savings account, sweep FD or liquid fund; a credit-card limit is not a buffer. Hospital bills are the classic Indian emergency, so health cover and the buffer should be planned together. If the household supports parents, the buffer should cover their medical contingency too. Senior citizens may prefer SCSS or FDs, which are less liquid than a savings account; the liquidity ladder matters more than the label.

---

### 3.3 Debt management

**Why it matters.** Debt is leverage in both directions. A home loan at 8–9% can be sensible; a credit card at 30–45% is a compounding emergency. Debt also sets the household's risk capacity: a large EMI reduces the amount of equity risk the household can afford, because a job loss turns a market dip into a solvency problem. A planner looks at debt before recommending any investment.

**What a veteran checks.**

| Check | Common benchmark | Notes |
| --- | --- | --- |
| Debt-to-income (DTI) | Under 36% is the common US framing | Indian lenders usually assess a Fixed Obligation to Income Ratio (FOIR), often capping total EMIs at roughly 40–50% of income. Treat 36–40% as a conservative planning band, not a legal limit |
| Housing EMI | Under 30% of income is the affordability rule | Include maintenance, property tax and insurance |
| Credit utilisation | Under 30% of the credit limit | High utilisation hurts credit scores and signals reliance on debt |
| High-cost debt | Clear credit cards and personal loans before investing beyond the employer match | Compare the interest rate with the expected after-tax return; debt repayment is a risk-free return |
| Minimum payment | Paying only the minimum on a card is a trap | The app already estimates monthly interest from APR |
| Payoff order | Avalanche (highest rate first) saves the most interest; snowball (smallest balance first) changes behaviour | The app should show both and let the household choose |
| Emergency fund versus debt | Build a small starter buffer before aggressive prepayment | Otherwise the next emergency goes back on the card |
| Prepayment | Check the prepayment penalty and the effective after-tax cost | A low-rate home loan may be better kept while investing; a high-rate personal loan is usually better cleared |
| Loan purpose and collateral | Secured versus unsecured; recourse versus non-recourse | Gold loans, loan against securities and loans from family are easy to miss |
| Credit report | Check annually for errors and fraud | The app has no credit-score integration |
| Tax treatment | Home-loan interest may be deductible under section 24(b); education-loan interest under 80E | Re-check current limits and regime eligibility; do not hardcode |

**What this app can compute today.**

The debt data is better than most consumer apps:

- Every liability is an account with a balance: Loan, CreditCard or OtherLiability.
- Loans store subtype, interest rate, rate type, term, start date, day-count convention, down payment, insurance rate, variable-rate schedule, and can produce an amortisation schedule, a monthly payment, a remaining balance, a paid ratio and a payoff projection with extra payments.
- Credit cards store APR, minimum payment, annual fee, available credit, statement close day and due day, and can produce a statement summary, days until due, estimated monthly interest and a minimum-payment shortfall flag.
- The income statement provides recorded income for a DTI calculation.
- The balance sheet provides total liabilities and net worth.

That is enough for a real debt dashboard today, without a migration. The two gaps are the **credit limit** (not stored as a column, but inferable as outstanding balance plus available credit) and the **India loan subtypes** (personal, gold, consumer-durable and loan-against-securities are not in the list; education maps to student, and the rest would map to "other").

**What is missing.**

- A first-class credit-limit column. Inferring it from available credit plus balance works only when available credit is current and correct.
- India loan subtypes and fields: lender, EMI day, prepayment penalty, floating-rate benchmark, co-borrower, loan purpose.
- A principal-versus-interest split on loan payments. The amortisation schedule can derive it, but the ledger does not label the split.
- A credit score or credit-report import. This is optional and privacy-sensitive; it should not be a P0.
- A "debt freedom date" and interest-saved figure on the planning page, which is a presentation gap rather than a data gap.
- A link between a home loan and the property account, so net worth does not double-count or omit the asset.

**Feature implications.** A **debt command centre** is the strongest P0 feature after the scorecard: total debt, weighted average rate, monthly obligation, DTI, credit utilisation, interest cost over the next 12 months, payoff order and payoff date with an extra-payment slider. Everything needed is already in the schema. The "minimum payment trap" warning and the avalanche-versus-snowball comparison are copy and arithmetic, not new data.

**India-specific notes.** Home loans are often joint and floating-rate; a repo-rate change alters the EMI or the tenure, and the app's variable-rate schedule can model it if the owner enters the changes. Gold loans and loans against securities are common and often undocumented in apps; they should be addable as OtherLiability with a rate. Credit-card EMI conversions and BNPL plans are high-cost debt and should not be hidden inside "shopping" transactions. Family loans are real obligations even when there is no interest; the app should allow a zero-rate loan with a repayment plan.

---

### 3.4 Protection: health, life and nominations

**Why it matters.** Protection is the only domain where the correct outcome is usually that nothing happens. A single uninsured hospitalisation or the death of an earning member can undo a decade of saving. Insurance is risk transfer, not an investment; the app's job is to make sure the household knows what it is covered for, what it is not, when it renews, and who is nominated.

**What a veteran checks.**

| Area | What is checked | Typical benchmark or rule of thumb |
| --- | --- | --- |
| Health cover | Sum insured, family floater versus individual, super top-up, room-rent limits, co-pay, waiting periods, pre-existing conditions, network hospitals, day-care procedures | A separate family floater plus a super top-up is common; employer group cover is not portable. Sum insured should reflect metro hospital costs, not the cheapest premium |
| Term life | Cover amount, policy term, premium, riders, claim-settlement record, medical underwriting | A common heuristic is 10–15 times annual income, plus liabilities, minus liquid assets, and enough to cover dependants until independence. Term only; endowment and ULIP are not protection |
| Disability and critical illness | Own-occupation disability, critical-illness rider, personal accident | Often missing entirely; a disability can be financially worse than death because expenses continue |
| Property and vehicle | Home structure and contents, vehicle comprehensive cover | Home insurance is frequently skipped in India even by homeowners |
| Premium affordability | Total premium as a share of income | A rough planning band is 2–4% of income for a young household, rising with age and cover. This is a heuristic, not a rule |
| Renewals | Grace period, no-claim benefits, portability | A lapsed health policy can restart waiting periods |
| Nominations | Bank, demat, mutual fund, EPF/PPF/NPS, insurance, locker | A nomination is not a will; it tells the institution who to release money to, subject to succession law |
| Employer cover | Group health and group term | Convenient but not portable; a job change can leave a gap |
| Documents | Policy schedule, terms, premium receipts, medical records | The app has no document vault for these |

**What this app can compute today.** Very little, and this is the largest honest gap in the product.

- Insurance premiums can be found in the ledger under the built-in insurance category, and recurring transactions can capture renewals.
- There is an investment subtype called "life insurance". That is useful if a ULIP or endowment policy is being tracked as an investment, but it is **not** term cover and it carries no sum assured, premium, nominee or renewal data.
- There is no health-insurance representation at all.
- Accounts have an owner, so a per-person view is possible for accounts, but there is no household-member record for someone who does not log in (a spouse, a child, a parent).

A veteran adviser would not accept "we have an insurance category" as protection data. The app cannot currently answer the three questions that matter: **how much cover exists, for whom, and until when.**

**What is missing.**

- An insurance policy entity: policy type (term, health, personal accident, critical illness, home, vehicle, travel), insurer, masked policy number, sum assured or sum insured, premium, premium frequency, start date, renewal date, status, riders, covered members, nominee, employer-group flag, notes and an optional document attachment.
- Household members: name, relationship, date of birth, dependent flag, and whether they are covered. This also unlocks age-based planning elsewhere.
- A protection-gap calculation: term cover needed versus existing cover; health cover versus a cost benchmark; premium versus income.
- Renewal reminders, using the existing recurring-transaction or notification machinery.
- Nomination status across accounts and policies, which overlaps with the estate register.

**Feature implications.** A **protection register** is the single highest-value P1 feature, and it needs a migration. It is also the feature that most changes the product's perceived seriousness: a planning page that knows the household's term cover and health cover is a different product from one that only knows its net worth. The gap calculator should come after the register, because a gap calculator with no policy data is a quiz, not a tool.

**India-specific notes.** IRDAI regulates insurers and policyholder rights. Employer group health cover is common in salaried households and usually ends with the job; the register should mark it as such. Health premiums rise sharply with age, and pre-existing conditions have waiting periods, so starting early matters. Term premiums are low for young, healthy lives; a smoker or someone with a health condition may need underwriting help. Section 80D deductions may apply under the old regime; re-check the current limits and eligibility. A nominee on a demat account or mutual fund folio is required in practice; SEBI's investor-education page explains the facility, though the deadline text on that page is out of date and should not be quoted as current.

### 3.5 Savings and investing: allocation, diversification, rebalancing, fees

**Why it matters.** Saving is necessary but not sufficient; inflation erodes cash, and the household needs a portfolio whose risk matches its goals and its stomach. Most investing mistakes are not stock-picking mistakes. They are allocation mistakes (too much equity for a three-year goal), concentration mistakes (one employer stock, one property, one sector), cost mistakes (a 2% expense ratio over 30 years) and behaviour mistakes (selling in a drawdown).

**What a veteran checks.**

| Check | Common benchmark | Notes |
| --- | --- | --- |
| Asset allocation | Equity, debt, gold, real estate, cash and alternatives in proportions that match goal horizons and risk capacity | "100 minus age" in equity is a heuristic, not a rule. Human capital, income stability, liabilities and dependants matter more |
| Goal-horizon matching | Under 3 years: debt or cash; 3–7 years: a mix; over 7–10 years: equity can be considered | A goal's money should not be in an asset that can halve in the year it is needed |
| Diversification | No single stock over roughly 5–10%; no single sector over roughly 25–30%; no single fund house or strategy dominating | These are heuristics. Employer stock and a self-occupied home are concentration risks too |
| Fund overlap | Two "diversified" funds can hold the same top 20 stocks | The app has no holdings look-through |
| Rebalancing | Bands of plus or minus 5 percentage points, or 20% relative drift, are common triggers | Rebalancing is risk control, not return enhancement; it also has tax costs |
| Costs | Expense ratio, advisory fee, brokerage, stamp duty, exit load, tax | A 1.5–2% annual cost can consume a large share of a 30-year return. Index funds are usually cheaper; the app cannot see TER today |
| Cash drag | Idle cash beyond the emergency buffer | The idle-cash insight already flags some of this |
| Tax efficiency | Holding periods, tax-advantaged accounts, asset location | Tax is covered in 3.7 |
| Benchmark | Compare XIRR with an appropriate index, not with a fixed deposit | The app has no benchmark index series |
| Nominations | Demat and mutual-fund folios | Overlaps with estate planning |

**What this app can compute today.**

- Holdings by account and security, with quantity, price, market value, cost basis, weight in the account and day change.
- Daily security prices, including AMFI NAVs for mutual funds, and exchange rates for foreign holdings.
- Portfolio value, cash balance, holdings value, contributions, withdrawals, dividends and interest through the investment statement.
- A working XIRR implementation: Portfolio::Xirr is a Newton-Raphson solver with a bisection fallback and an ambiguity check; Portfolio::MoneyWeightedReturn decides what the cash-flow series is, with two bases (external flows or trades) and a stated assumption for portfolios anchored from holdings.
- A security taxonomy in the schema: asset class, sub-class, sector, industry, country, region, mutual-fund flag, ISIN, AMFI code.
- Investment subtypes that already distinguish Indian equity, debt, gold, NPS, PPF, EPF and so on.

The XIRR engine is the most under-used asset in the codebase. It is built, documented and tested, and it answers the question every investor actually asks: "what return did I get on the money I put in?" It is not yet surfaced on the planning page.

**What is missing.**

- **Asset classification is not populated.** The columns exist, but nothing writes them; every security is unclassified. A real allocation chart needs either a classification job/provider or a simple manual "asset class" picker per holding.
- **Target allocation.** There is no investment policy statement and no target weights, so the app can describe the current allocation but cannot say whether it is right for the household.
- **Fund look-through and overlap.** Two mutual funds may hold the same stocks; the app sees funds as single securities.
- **Expense ratio and other costs.** Brokerage fees are in trades, and a "fees" expense category exists, but mutual-fund TER, advisory fees and exit loads are not captured.
- **Benchmark series.** There is no Nifty 50, Sensex, CRISIL or MSCI series to compare against. The app can show an XIRR but not whether it is good.
- **Purchase dates and lots** for tax-aware selling; this is the project's known capital-gains blocker.
- **Real estate, gold and unlisted holdings** are tracked as balances, not as assets with a valuation method, rental yield or liquidity discount.
- **Per-person ownership** of holdings and goals. Accounts have owner_id, but the planning views are family-level.

**Feature implications.** A **return card** (P0) should surface the existing XIRR, with the basis label and an ambiguity hedge, because it is cheap and immediately useful. An **allocation and concentration card** (P1) should start with the taxonomy that is already reliable — investment subtype, account type, country and mutual-fund flag — and treat security-level asset class as a later enhancement, not a blocker. **Rebalancing** (P2) needs target weights and should be tax-aware. A **fee audit** (P2) needs an expense-ratio field and a way to enter advisory fees.

**India-specific notes.** Indian households often hold a large share of wealth in real estate and gold, and a large share of financial wealth in EPF/PPF/NPS, which are debt-like and long-locked. Equity mutual funds, direct stocks, ETFs, SGBs, REITs/InvITs, PMS/AIF and ESOPs all behave differently. "Direct" versus "regular" mutual-fund plans is a pure cost decision. ELSS has a three-year lock-in. Sectoral and thematic funds are concentration bets, not diversification. The app's subtype list covers most of these; the missing piece is the target allocation and the look-through.

---

### 3.6 Retirement and FIRE

**Why it matters.** Retirement is the largest, longest and least reversible goal. It is also the one where a small assumption error compounds the most: a 1% difference in return or inflation over 30 years changes the required corpus by a large multiple. A planner spends more time on the assumptions than on the product.

**What a veteran checks.**

| Check | Common benchmark | Notes |
| --- | --- | --- |
| Replacement ratio | 70–80% of pre-retirement income is a common starting point | Expenses often fall in some categories and rise in healthcare |
| Corpus multiple | 25 times annual expenses at a 4% withdrawal rate; 30 times at 3.3%; 20 times at 5% | The 4% rule is a US historical starting point, not a guarantee, and it is pre-tax and pre-fee |
| Inflation | India has historically run higher inflation than the US; 5–7% is a common planning assumption | Healthcare inflation is usually higher than headline inflation |
| Longevity | Plan to age 90 or beyond, or use a joint-life horizon for a couple | A 60-year retirement is possible |
| Sequence-of-returns risk | A poor return in the first five years of withdrawal is much worse than the same return later | The app's projection is deterministic and does not model this |
| Withdrawal flexibility | Guardrails, bucket strategy, a cash buffer of 1–3 years of expenses | Fixed real withdrawals are brittle |
| Pension and annuity income | EPS, NPS annuity, employer pension, SCSS, annuities | These reduce the corpus needed and are not in the app |
| Healthcare | Separate cover and a medical contingency fund | A single hospitalisation can be larger than a year's expenses |
| Taxes and fees | Withdrawal taxes, annuity taxation, fund TER, advisory fees | The app's withdrawal rate is gross |
| One more year | The option to work one more year is a powerful safety valve | A plan that needs no flexibility is fragile |
| Stress test | Lower return, higher inflation, longer life, a bad early decade | Not modelled today |

**What this app can compute today.**

| Figure | Formula | Where | Caveat |
| --- | --- | --- | --- |
| FIRE target | Average annual expenses divided by withdrawal rate | FireProgress | Uses today's expenses; no inflation |
| FIRE multiple | 1 divided by withdrawal rate | PlanningSetting | 25x at 4% |
| FIRE progress | Net worth divided by target | FireProgress | Includes home, vehicles and restricted accounts |
| Remaining | Target minus net worth, floored at zero | FireProgress | Same inclusion issue |
| ETA | Closed-form months from current net worth, monthly savings and growth rate | WealthProjector#months_to_target | Assumes constant returns; no volatility |
| Coast FIRE | Projected balance at a target year versus target | FireProgress | Same inflation and inclusion issues |
| FIRE variants | Lean 3.3%, coast 4.0%, barista 6.5%, standard 4.0%, fat 3.0% | PlanningSetting | Variant rates are illustrations, not recommendations |
| 10-year projection | Opening balance compounded at a configured growth rate, plus annual contributions | WealthProjector | Contributions applied at year end; no taxes |

The engineering is clean and the UI is honest about assumptions. The problem is the **model**, not the code.

**Five things to fix before adding more FIRE features.**

1. **Use investable net worth.** A self-occupied house, a car and a gold necklace are not a retirement corpus unless the plan is to sell or borrow against them. The FIRE card should show both total net worth and investable net worth, and the progress bar should use the investable figure, or clearly label which one it uses.
2. **Make inflation explicit.** Either grow expenses at an inflation assumption to get a future target, or use a real return (nominal return minus inflation) for the projection. The current combination of today's expenses and a nominal growth rate is optimistic. A single "inflation" field in PlanningSetting would fix the first version.
3. **Model taxes and fees in the withdrawal rate.** A 4% gross withdrawal is not 4% net. EPF, NPS, PPF, equity capital gains and interest income are taxed differently; fund TER and advisory fees reduce the portfolio. At minimum, offer a "net withdrawal rate" input.
4. **Say that the projection is deterministic.** The ETA is a single path, not a probability. A range or a "what if returns are 2% lower" toggle would be more honest than a second decimal place.
5. **Separate accumulation from withdrawal.** The app answers "when can I stop?" reasonably. It does not answer "how do I take money out without running out?" That needs a withdrawal plan, a cash bucket and a sequence-risk stress test.

**What is missing.**

- Dates of birth and a retirement age; the app has no age anywhere.
- Expected retirement expenses, separately from current expenses (some costs fall, healthcare rises).
- Pension, annuity, EPF/EPS, NPS and other retirement income.
- Inflation assumption and inflation-linked expenses.
- Healthcare cost inflation.
- Withdrawal plan and sequence-risk analysis.
- Tax treatment at withdrawal.
- A Monte Carlo or historical-scenario engine.
- A per-person view for a couple with different retirement dates.

**Feature implications.** The P0 work is not a new FIRE calculator; it is a **FIRE honesty pass**: show investable net worth, add an inflation assumption, add a sensitivity table (3%, 3.5%, 4%, 4.5%) and label the ETA as a deterministic estimate. P1 adds retirement age and expected retirement expenses. P2 adds the withdrawal plan and stress test. A Monte Carlo engine is a later, separate project.

**India-specific notes.** EPF and EPS, NPS (accumulation and annuity phases), PPF maturity, gratuity, leave encashment, SCSS, senior-citizen FDs, reverse mortgage and family support all change the retirement picture. There is no universal social security, so the corpus has to carry more of the risk. Health costs rise with age, and health insurance premiums rise too. Many households plan to downsize or rent out property; that is a legitimate strategy, but it should be modelled explicitly rather than assumed.

---

### 3.7 Tax planning for India

**Why it matters.** Tax is one of the largest controllable costs in a household's financial life. The choice between the old and new regimes, the use of deduction headroom, the timing of capital gains, the holding period of an investment and the disclosure of foreign assets can change the outcome by lakhs over a decade. It is also the domain with the highest compliance risk: a missed Schedule FA disclosure or a late return can cost more than the tax saved.

**What a veteran checks.**

| Area | What is checked | What the app would need |
| --- | --- | --- |
| Regime choice | Old versus new regime, year by year; deductions only help under the old regime for most heads | Salary income, other income, deduction claims, regime |
| 80C | EPF, PPF, ELSS, life-insurance premium, principal repayment, tuition fees, NSC, SSY, etc., within the overall limit | Deduction tagging or account/subtype mapping |
| 80CCD(1B) | Additional NPS contribution, over and above the 80C ceiling | NPS account and contribution data |
| 80CCD(2) | Employer NPS contribution; the new regime allows a higher employer share | Salary structure and employer contribution |
| 80D | Health-insurance premium for self, family and parents; preventive health check-up | Policy data and premium payments |
| 24(b) | Home-loan interest on a self-occupied property | Loan interest split and property linkage |
| HRA | Least of actual HRA, rent minus 10% of basic, or 50%/40% of basic depending on city | Salary structure, basic, HRA, rent receipts |
| LTA | Travel allowance, subject to conditions | Salary structure and travel proof |
| 80G, 80TTA/80TTB | Donations; savings-account and senior-citizen interest | Categorised transactions |
| Capital gains | Holding period, STT, exemption, set-off, cess and surcharge | Purchase dates, lots, sale proceeds, expenses |
| Advance tax | Quarterly instalments and interest for shortfall | Estimated annual tax and payments |
| TDS and AIS | Form 26AS, AIS/TIS, mismatches | Import or manual entry |
| Foreign assets | Schedule FA disclosure for foreign accounts and securities | Country, owner, peak value, acquisition date |
| NPS/EPF/PPF exit | Tax treatment at withdrawal, annuity requirement | Product rules and balances |
| Business/professional income | Presumptive taxation, books, GST (not personal) | Out of scope for a personal app, but flag it |
| Crypto and unlisted shares | Special rates and reporting | Security classification and lots |

**The rules the app's own notes say to encode, and to re-check.**

The project notes record the capital-gains shape as last confirmed against the Finance (No. 2) Act 2024 for gains on or after 23 July 2024. That is a record of the app's research, not a verification for the current year. Treat every line below as **shape, not law**:

| Situation | Treatment in the notes | Status |
| --- | --- | --- |
| Listed equity and equity-oriented funds, held 12 months or less | Short-term, 20% under section 111A | Unverified for the current year |
| Listed equity and equity-oriented funds, held more than 12 months | Long-term, 12.5% under section 112A, first ₹1.25 lakh of long-term gains per person per year exempt, no indexation | Unverified for the current year |
| Debt or specified mutual funds bought on or after 1 April 2023 | Slab rate whenever sold; no long-term rate | Unverified for the current year |
| Unlisted and foreign shares | Long-term threshold 24 months, 12.5% long-term, slab short-term | Unverified for the current year |
| Set-off | Short-term losses offset short-term first, then long-term; long-term losses offset only long-term; carry forward 8 assessment years if the return is filed on time | Unverified for the current year |
| Cess and surcharge | 4% health and education cess; surcharge thresholds with a 15% cap on 111A/112A gains | Unverified for the current year |
| Grandfathering | Listed equity bought before 31 January 2018 may use the higher of actual cost and 31 January 2018 fair market value | Unverified for the current year |
| Wash sale | India has no wash-sale rule; tax-loss harvesting by selling and buying back is legitimate | Unverified for the current year |
| Dividends | Slab income, not capital gains | Unverified for the current year |

Other long-standing deduction figures are equally time-sensitive. NPS Trust's page (fetched for this document) states 80CCD(1B) at ₹50,000 over the 80CCE ceiling of ₹1.5 lakh, and employer NPS at 10% of salary under the old regime and 14% under the new regime. Those figures should be stored in one versioned configuration with effective dates, not hardcoded in a view, and re-checked before release. Section 80D, 24(b), the standard deduction and the slab rates all need the same treatment.

**What this app can compute today.**

- Tax-treatment labels on investment subtypes (taxable, tax-deferred, tax-exempt, tax-advantaged) and India-specific subtypes (NPS, PPF, EPF, SSY, NSC, SGB, etc.).
- Insurance, taxes, loan-payment and donation categories in the ledger.
- Trades, prices, holdings and cost basis; an XIRR engine.
- Exchange rates for foreign holdings.
- Per-account owner_id, which is the beginning of a per-person tax view.
- No tax profile, no slab, no regime, no deductions, no TDS, no advance tax, no purchase dates and no tax-rate configuration.

**What is missing, in the order that matters.**

1. **A per-person tax profile:** age, regime, salary income and structure, other income, deduction claims, TDS, advance tax paid, and a flag for foreign assets. This is the single largest schema gap after insurance.
2. **Purchase dates and FIFO lots.** The project notes cover the blocker in detail: holdings have a valuation date, not an acquisition date; Kite's API only returns the current day's tradebook; the Console tradebook CSV is the practical source. The lot engine and CSV import are already planned and should not be re-planned here.
3. **A dated tax-rule configuration.** Rates, limits, thresholds, surcharge bands and effective dates in one place, with a "verified on" date and a "re-check required" flag.
4. **Capital-gains computation and an estimator view**, per person, per financial year, with set-off and the exemption applied.
5. **A deduction tracker:** how much of 80C, 80CCD(1B), 80D and 24(b) is already used, and how much headroom remains.
6. **Schedule FA support:** a list of foreign accounts and securities by owner, country, peak value and acquisition date. The app can produce a checklist even before it computes anything.
7. **Advance-tax and TDS tracking**, with the quarterly instalment dates and a simple interest estimate.

**Feature implications.** The cheapest honest tax feature is a **tax-year readiness checklist** (P0): it shows what data exists, what is missing, and which figures are estimates. It does not need a migration and it prevents the app from shipping a confident wrong number. The **tax profile and regime comparison** is P1/P2 and needs a migration. **Capital gains** is P2 and depends on lots and the CSV import; the project's build order in the notes should be followed rather than duplicated. **Schedule FA** and **advance tax** are P2.

**India-specific cautions.** The financial year runs April to March, not the calendar year. The tax unit is the person, not the family; a household total must never be presented as one person's taxable income. The old-versus-new regime choice is made each year, and the "default" regime has changed before; do not assume. A return filed late can forfeit loss carry-forward. Foreign assets and signing authority in foreign accounts can trigger Schedule FA even when there is no income. Crypto, unlisted shares, ESOPs, RSUs and foreign broker accounts each have their own reporting quirks. The app should say "estimate", show its assumptions, and produce a schedule for a CA, never an ITR.

---

### 3.8 Goal-based planning

**Why it matters.** Goals convert an abstract "save more" into a funded, time-bound commitment. They also expose conflicts: the same money cannot fund a house down payment, a child's education and an early retirement at the same time. A planner uses goals to set the savings rate, choose the asset mix and decide what to sacrifice when the numbers do not fit.

**What a veteran checks.**

| Check | What is checked | Notes |
| --- | --- | --- |
| Specific and costed | A target amount in today's rupees, inflated to the goal date | Education and healthcare inflate faster than headline inflation |
| Time horizon | The date, and therefore the asset mix | Under 3 years: capital protection; over 7–10 years: equity can be considered |
| Priority | Essential versus important versus aspirational | Emergency fund and insurance come before discretionary goals |
| Funding source | Which account, which contribution, which asset | The app links accounts and pledges |
| Monthly requirement | Target gap divided by months remaining | The app already computes a monthly target |
| Current pace | Actual net inflow over the last 90 days | The app already computes pace |
| On-track status | Monthly requirement versus pace | The app already computes on-track/behind |
| Goal conflict | Two goals relying on the same account or the same rupee | The app's shared-pool logic handles some of this |
| Inflation and return | A goal-specific inflation and expected return | Not in the app |
| Review | Re-cost the goal annually and after life events | Not in the app |

**What this app can compute today.**

This is one of the strongest parts of the fork:

- Goals with target amount, target date, currency, kind (one-off or maintained), progress basis (balance or contributions), state and notes.
- Linked accounts with earmarks, shared-pool allocation and exclusivity rules that prevent double-counting.
- Current balance, progress percent, remaining amount, consumed amount, monthly target, 90-day pace, status, projection payload and a projection chart.
- Pledges: an intent to save, matched against incoming transfers or manual saves.
- Maintained reserves with a "months of expenses" target that refreshes monthly.
- A Plan hub that fronts budgets and goals.

A goal funding plan is therefore mostly a **presentation and what-if** feature, not a new data model.

**What is missing.**

- Goal priority and goal type (emergency, education, home, retirement, travel, wedding, vehicle, business).
- A goal-specific inflation assumption and expected return, so the target can be expressed in future rupees.
- A goal owner (per person) and a link to a household member.
- Conflict detection beyond the shared pool: "these three goals need more than your current surplus".
- A roll-up that compares total monthly goal requirements with actual monthly savings, and says which goal is short.
- A "what if I increase the contribution by ₹X" slider, and a "what if I delay this goal by a year" view.
- Integration with the retirement goal, so the same surplus is not counted twice.

**Feature implications.** A **goal funding plan** is a P0 feature: a single card that lists every active goal, its monthly requirement, its current pace, its projected completion date and the total gap, with a what-if slider. It uses existing Goal methods and needs no migration. Priority and inflation are P1 and need small schema additions. A goal wizard that recommends an asset mix by horizon is P2 and should be educational, not a product recommendation.

**India-specific notes.** Education costs inflate faster than headline inflation; a wedding or a house down payment is often a family project rather than an individual one; gold is both a goal and a store of value; parents' healthcare may be an implicit goal that never gets a name. The app should allow a goal to be shared by the household and should not assume every goal belongs to one person. The lakh/crore formatting matters most here, because goal amounts are the numbers a household actually talks about.

### 3.9 Estate and succession basics

**Why it matters.** A financial plan that works while you are alive but leaves a mess when you are not is incomplete. Unclaimed accounts, missing nominations, a stale will and no guardian for a minor can freeze a family's money for years and cost a large share of it in legal fees. Estate planning is not only for the wealthy; it is mostly administration, and the cheapest time to do it is now.

**What a veteran checks.**

| Check | What is checked | Notes |
| --- | --- | --- |
| Will | A valid, signed will; an executor; a guardian for minor children; a residue clause | Registration is optional in India but can help; state law and probate vary |
| Nominations | Bank accounts, demat, mutual-fund folios, EPF/PPF/NPS, insurance, locker | A nominee is a custodian, not necessarily the owner; succession law still applies |
| Joint holdings | Joint accounts, joint demat, joint property | "Either or survivor" versus "jointly" changes what happens |
| Succession law | Which law applies (Hindu Succession Act, Indian Succession Act, community custom) | A lawyer should confirm; the app should not give legal advice |
| Trusts | Special-needs trust, minor trust, family trust | More complex; usually needs a lawyer and a trustee |
| Power of attorney | Financial and medical POA; durability | Useful for incapacity, not only death |
| Digital assets | Email, cloud, brokerage, crypto, social accounts, passwords | A written inventory and a trusted contact |
| Foreign assets | Succession and tax treatment across borders | Overlaps with Schedule FA |
| Documents | Will, policies, deeds, loan documents, nomination acknowledgements | The app has no document vault for these |
| Review | After marriage, birth, death, divorce, a large asset purchase or a move | An out-of-date will can be worse than none |

**What this app can compute today.** Nothing. There is no nomination field, no will record, no beneficiary, no document vault and no estate checklist. Accounts have an owner and family members have logins, but that is not a succession plan.

**What is missing.**

- A simple estate register: item type (will, nomination, power of attorney, trust, document), asset or institution, status, nominee or beneficiary, last reviewed, notes and an optional attachment.
- Nomination fields on the assets the app already knows about: accounts, holdings, policies.
- A "documents" area, or at least links to where the documents live. The app should not become a password vault.
- Review prompts after life events, and an annual "are your nominations still right?" check.
- A household-member record, so a guardian and beneficiaries can be named.

**Feature implications.** An **estate and nomination register** is P2. It is mostly a checklist with attachments and review dates, and it does not need to compute anything. It should be explicit that the app records status, not legal validity, and that a lawyer should review the will. The nomination part can be folded into the protection register and the account detail pages, so the household sees one place for "who gets this if I am gone".

**India-specific notes.** Nomination rules differ by asset: SEBI requires nomination or an opt-out for demat accounts and mutual-fund folios; EPF, PPF and NPS have their own nomination forms; insurance policies have nominee clauses; bank accounts have nomination facilities. A nominee is not automatically the legal heir. Hindu succession, Muslim personal law, Christian succession and the Indian Succession Act apply differently, and probate is required in some jurisdictions for some wills. The app should link to the official sources and stay out of legal conclusions.

---

### 3.10 Behavioural coaching

**Why it matters.** The difference between a good plan and a good outcome is usually behaviour. Investors underperform their own funds because they buy after good performance and sell after bad; savers under-save because the future is abstract and the present is concrete. A planner's job is to design the environment so the right behaviour is the easy behaviour.

**What a veteran checks.**

| Behaviour | What to look for | What helps |
| --- | --- | --- |
| Automation | Are savings and investments automatic on salary day? | SIP, auto-debit, standing instructions, "pay yourself first" |
| Consistency | Is the savings rate stable, or does it swing with mood and markets? | A target range, not a perfect number; automated escalation |
| Lifestyle inflation | Is spending growing faster than income? | A rule for raises and windfalls (save a fixed share of every increase) |
| Loss aversion | Does the household sell in a drawdown? | Pre-commitment, a written policy, fewer portfolio checks |
| Recency bias | Is the plan extrapolating the last two years? | Long-horizon assumptions, scenario ranges |
| Overconfidence | Is the household concentrated in a stock, sector or employer? | Concentration limits, diversification nudges |
| Mental accounting | Is "found money" treated differently from salary? | One plan, explicit windfall rules |
| Status quo | Are old, expensive or unsuitable products still held? | Annual review, cost audit |
| Herd behaviour | Are investments driven by tips and social media? | Education, source hygiene, a cooling-off rule |
| Present bias | Is the emergency fund always "next month"? | Small starter goal, automatic transfer, visible progress |
| Checking frequency | Does the household check daily and trade monthly? | A review cadence, not a dashboard habit |

**What this app can compute today.**

- An insights feed with generators for a savings-rate change, spending anomalies, subscription creep, idle cash, budget pressure and a depleted maintained goal. These are exactly the right kind of nudges: specific, timely and based on the household's own data.
- Recurring transactions and bills, which make automation visible.
- Goals with progress, pace and pledges, which make commitment visible.
- Budgets and the 50/30/20 split, which make trade-offs visible.
- No behavioural profile, no commitment-device settings, no "save a share of every raise" rule, no panic-selling detection, no spending-versus-income growth comparison.

**What is missing.**

- A "commitment device" layer: automate a monthly increase, ring-fence windfalls, set a rule for bonuses and gifts, and turn a goal into a recurring transfer.
- A lifestyle-inflation check: spending growth versus income growth, by category, over 12 and 36 months.
- A drawdown-behaviour check: did the household sell equity after a market fall? This needs price history and trade dates, both of which exist.
- A nudge cadence: how often the app speaks, and about what. Too many nudges train dismissal.
- A "decision journal" for major financial choices, so the household can review the reasoning later.

**Feature implications.** Extending the insight generators is P1 and cheap: a lifestyle-inflation insight, a "windfall rule" prompt, a "raise the SIP by 10%" prompt and a "you sold after a fall" observation are all possible with existing data. A commitment-device settings page is P2. The app should never use dark patterns or shame; the tone should be the calm, specific voice the existing insight copy already uses.

**India-specific notes.** Festival spending, family obligations, gold purchases, real-estate FOMO, WhatsApp tips and derivatives speculation are common behavioural traps. A "cooling-off" rule for large purchases and a "no tips" rule for investments are culturally specific and useful. The app should be careful with notification volume; a household that mutes the app has lost the coaching channel entirely.

---

### 3.11 Review cadence

**Why it matters.** A plan is a snapshot of assumptions, and assumptions decay. Incomes change, families grow, markets move, tax law changes and products become unsuitable. A veteran adviser schedules the review before it is needed, because the household will not.

**What a veteran checks.**

| Cadence | What happens | Why |
| --- | --- | --- |
| Monthly | Cash-flow check, budget variance, savings rate, upcoming bills | Catch drift early; no trading |
| Quarterly | Goal progress, debt payoff, emergency coverage, investment contributions | Correct course without overreacting |
| Annually | Full review: goals, insurance, nominations, tax, allocation, fees, estate | The minimum viable planning relationship |
| Event-driven | Job change, marriage, child, death, inheritance, home purchase, business sale, market fall of 20% or more, tax-law change, health event | The plan may be wrong immediately |
| Rebalancing | When a band is breached, not on a calendar | Avoid unnecessary trades and taxes |
| Tax year-end | January to March: investment proof, tax-saving investments, capital-gains harvesting, advance tax | Indian tax year ends 31 March |
| Insurance renewals | Before the grace period | A lapse can restart waiting periods |

**What this app can compute today.** The pieces exist but the loop does not close. The app can show the planning cards, the insights feed, goal progress and budget variance; it cannot record when the household last reviewed the plan, cannot generate a review report, and cannot remind anyone. There is no last_reviewed_at anywhere.

**What is missing.**

- A last-reviewed date and a next-review-due date, at family level.
- A review checklist that persists state: goals re-costed, insurance checked, nominations checked, tax documents collected, allocation reviewed, beneficiaries updated.
- A printable or shareable annual review report: opening and closing net worth, savings rate, debt paid, investment return, goal progress, protection status, tax actions and next year's priorities.
- Reminders, through the existing notification or recurring-transaction machinery.
- A decision log, so the household can see what changed and why.

**Feature implications.** An **annual review report** is a P1 feature and a natural companion to the P0 scorecard. It is mostly aggregation and print styling, and it gives the planning page a reason to exist every year. Review reminders and a persisted checklist are P1/P2 and need a small settings change. The report should be exportable as a clean PDF or print view, because the household may want to take it to an adviser or a CA.

**India-specific notes.** The tax year ends 31 March, so the review cadence should anchor to it: January–February for investment proof and tax-saving decisions, March for capital-gains harvesting and advance tax, April for the new year's plan. School admissions, insurance renewals and festival spending are predictable annual events that belong on the same calendar.

---

## 4. Data gaps and schema proposals

This section separates what can be fixed with a definition or a query from what genuinely needs a migration. The distinction matters because the P0 list is supposed to be buildable without migrations.

### 4.1 The four questions every advisory feature must answer

Before a feature is built, it should be able to answer these four questions on screen:

1. **Whose money is this?** The family, a person, a joint holding, a dependant. Tax and insurance are per person; the app is family-scoped.
2. **What period is it for?** This month, the trailing 12 months, the financial year, the goal horizon. Mixing periods is the most common source of wrong planning numbers.
3. **What is included?** Which accounts, which transactions, which assets, which liabilities, which currencies. The app has strong scoping tools; the feature must expose them.
4. **How confident is it?** Which inputs are missing, approximated or stale. This is the data-confidence rule from section 2.5.

A feature that cannot answer these is not ready to show a number.

### 4.2 Gaps that need no migration

These can be built from existing data plus a definition. They are the P0 layer.

| Gap | Workaround | Where it shows |
| --- | --- | --- |
| Investable net worth | Filter accounts by accountable_type: exclude Property, Vehicle, OtherAsset and restricted retirement accounts; show both figures | FIRE card, scorecard |
| Inflation-aware FIRE | Add an inflation input to the projection or show a real-return sensitivity table; no schema needed for a read-only sensitivity | FIRE card |
| Debt-to-income | Sum monthly loan payments and card minimums, divide by recorded monthly income | Debt card |
| Credit utilisation | Infer limit as balance plus available credit; flag when available credit is stale | Debt card |
| Interest cost next 12 months | Amortisation schedule plus card APR | Debt card |
| Portfolio XIRR | Portfolio::MoneyWeightedReturn with closing value from the balance sheet | Return card |
| Concentration | Holding value divided by portfolio value; top holding, top three, sector if available | Allocation card |
| Goal funding gap | Goal monthly target minus pace; projected completion from pace | Goal card |
| Tax-year readiness | Check whether trades have dates and prices, whether foreign holdings exist, whether tax-advantaged accounts exist, whether purchase dates are missing | Tax readiness card |
| Data confidence | A PORO that checks FX coverage, price staleness, excluded accounts, unclassified securities, missing purchase dates | Confidence panel |
| Essential-expense approximation | Use the needs bucket or a manual category list stored in PlanningSetting JSONB | Emergency and FIRE cards |
| Annual review report | Aggregate existing metrics and render a print view | Review page |

### 4.3 Gaps that need a small migration

These are one table, one JSONB column or a few columns. They unlock a large amount of value per unit of schema risk.

| Gap | Proposed change | Unlocks | Priority |
| --- | --- | --- | --- |
| Household ages and dependants | household_members table: family_id, user_id nullable, name, relationship, date_of_birth, dependent, notes | Age-based allocation, insurance needs, retirement dates, education goals, estate | P1 |
| Emergency target and basis | planning_settings columns or JSONB: emergency_target_months, emergency_include_accounts, essential_category_ids | Configurable buffer, honest coverage | P1 |
| Editable 50/30/20 targets | planning_settings JSONB: budget_targets | Household-specific split | P1 |
| Target allocation and IPS | planning_settings JSONB: target_allocation with asset classes and bands | Allocation drift, rebalancing | P1/P2 |
| Goal priority, type, inflation | goals columns: priority, goal_type, inflation_rate_pct, expected_return_pct, household_member_id | Goal ordering, future-rupee targets, conflict detection | P1 |
| Retirement profile | planning_settings: retirement_age, retirement_expenses, pension_income, inflation_rate_pct | A retirement plan rather than a FIRE percentage | P1 |
| Last reviewed / review due | planning_settings: last_reviewed_at, review_due_at, review_checklist JSONB | Review cadence and report | P1 |
| Risk profile | risk_profiles table or user JSONB: answers, score, horizon, capacity, updated_at | Allocation guidance, suitability notes | P2 |
| Credit limit | credit_cards.credit_limit | Accurate utilisation and available credit | P1 |
| Expense ratio | securities.expense_ratio (and a manual override) | Fee audit and cost drag | P2 |
| India loan fields | loans: lender, emi_day, prepayment_penalty, co_borrower; more subtype keys (code-only) | Realistic debt plan | P2 |
| Account beneficiary | accounts/holdings nominee fields or an estate_items link | Nomination register | P2 |

### 4.4 Gaps that need new tables

These are the domains where the app has no data at all.

**insurance_policies**

Proposed fields: family_id, owner_id (user or household member), policy_type (term, health, personal accident, critical illness, home, vehicle, travel), insurer_name, policy_number_masked, cover_amount, premium_amount, premium_frequency, start_date, renewal_date, status, employer_group, nominee_name, notes, document attachment, timestamps. A join table for covered members. Why: protection is the largest gap and the one a veteran adviser notices first.

**tax_profiles**

Proposed fields: family_id, user_id, financial_year, regime, age_category, salary_income, other_income, deduction_claims JSONB, tds_paid, advance_tax_paid, foreign_assets, notes. Why: tax is per person and the app currently has no person-level tax data. A separate tax_deductions table may be better if the owner wants line-by-line tracking.

**estate_items**

Proposed fields: family_id, owner_id, item_type (will, nomination, power of attorney, trust, document), institution_or_asset, status, nominee_or_beneficiary, last_reviewed_at, notes, document attachment. Why: estate is a checklist domain; it does not need much computation, but it needs a home.

**household_members**

Proposed fields: family_id, user_id nullable, name, relationship, date_of_birth, dependent, notes. Why: ages and dependants are prerequisites for protection, retirement, education goals and estate. A user is not the same as a household member; a spouse or child may not log in.

### 4.5 Data-quality work that is not a schema change

These are jobs, backfills and definitions that make existing data trustworthy.

1. **Populate security asset classification.** The columns exist; write a classifier or a manual picker and set classification_source. Until then, allocation must be labelled as approximate.
2. **Backfill purchase dates and lots** through the Console tradebook CSV, as the project notes already plan. Until then, capital gains must say "not available" rather than estimate from average cost.
3. **FX coverage.** For advisory cards, fail closed: if a foreign account has no rate, show "unavailable", not a rate-1.0 conversion. Log and surface the missing currency.
4. **Price staleness.** Show the price date next to any portfolio value; flag securities with no price in the last N days.
5. **Account scope definitions.** Mark accounts that are non-investable (self-occupied property, vehicle, personal effects) and accounts that are restricted (EPF/PPF/NPS) so FIRE and allocation can use the right set.
6. **Essential categories.** Either reuse the needs bucket or add a separate essential flag; do not conflate the two silently.
7. **Loan principal/interest split.** Use the amortisation schedule to split payments for reporting, and label the choice.
8. **Tax-advantaged visibility.** Add a reconciliation view that shows retirement contributions that the income statement excludes, so the savings rate is not misleading.
9. **Per-person ownership.** Ensure every new planning entity has an owner. Accounts already do; goals and policies should.
10. **Data provenance.** Store the source and as-of date for imported data (prices, FX, holdings, CSV imports) so the confidence panel can report it.

### 4.6 Tenancy, privacy and advice boundaries

- **Family tenancy is not optional.** Every query must be scoped to the family; new tables must carry family_id and be authorised consistently. Accounts already have sharing rules; new planning entities should follow them.
- **Tax and insurance are per person.** Do not aggregate them into a family figure without labelling it. The app should never imply a household total is one person's taxable income.
- **Sensitive data.** Health conditions, policy numbers, PAN, nominations and estate documents are sensitive. Store the minimum, mask identifiers in the UI, and do not add a document vault without thinking about encryption, sharing and deletion.
- **No product recommendations.** The app can say "your cover looks low relative to your liabilities" and "consider speaking to a licensed adviser". It should not rank insurers or funds.
- **No execution.** No trading, no policy purchase, no ITR filing, no auto-rebalancing. The app produces a plan and a schedule; the human acts.
- **Estimates, not filings.** Every tax and insurance number is an estimate with assumptions shown. The app's own project notes say this for tax and the same standard should apply to protection.

---

## 5. Feature map

The table below is the bridge between the framework and the code. It lists every feature proposed in this document, its inputs, the output the household sees, what data exists, what schema it needs, where it belongs, how big it is and what it depends on.

**Reading the columns:**

- **Inputs:** the data the feature reads. If an input is missing from the schema, the New schema column says so.
- **Output UI:** the card, table or report the household sees.
- **Data today:** Built means the app already has the inputs; Partial means some inputs exist but a definition or classification is missing; Missing means the data does not exist.
- **New schema:** No means no migration; Small means a column or JSONB setting; Table means a new table.
- **Placement:** Planning card means the /financial_planning page; New page means a new preview-gated page; Plan hub means the budgets-and-goals page; Account page means the existing accounts/investments area.
- **Gate:** all new planning surfaces should be preview-gated at the entry point and marked with the Preview pill, following the repository's gating guide.

| ID | Feature | Domain | Inputs | Output UI | Data today | New schema | Placement | Effort | Depends on | Gate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | Planning health scorecard | All | Savings rate, emergency coverage, DTI, goal pace, XIRR, protection-data presence | Six traffic-light rows, one "next best action" line | Built | No | Planning card at top | M | Existing SavingsRate, EmergencyFund, loans, cards, goals, XIRR | Yes |
| F2 | Debt command centre | Debt | Loan balances, rates and terms; card APR, minimum and limit; recorded income | Total debt, weighted rate, DTI, utilisation, interest cost, payoff order, extra-payment slider | Built | No | Planning card or a new debt section | M | Loan amortisation and payoff projection, CreditCard APR, income statement | Yes |
| F3 | Portfolio return card | Investing | Contribution and withdrawal flows, closing value, account scope | Portfolio and per-account XIRR, basis label, ambiguity hedge, flow summary, as-of date | Built | No | Planning card; link to account page | S/M | Portfolio::MoneyWeightedReturn, balance sheet | Yes |
| F4 | Goal funding plan | Goals | Goal targets and dates, linked balances, pace, pledges | Monthly requirement, current pace, projected completion, total gap, what-if slider | Built | No | Plan hub and planning card | S/M | Goal methods, GoalPledge pace | Yes |
| F5 | Data confidence panel | All | FX coverage, price dates, account scope, classification, purchase dates | Missing or stale input list with links to fix | Built | No | Planning footer or disclosure | S | Existing diagnostics | Yes |
| F6 | Tax-year readiness checklist | Tax | Trades, prices, holdings, accounts, categories | What exists, what is missing, what is an estimate; purchase-date coverage; foreign-asset flag | Partial | No | Planning card or new tax page | S | Trades, securities, accounts, categories | Yes |
| F7 | Emergency fund settings | Emergency | Liquid balances, expenses, target months, linked goal | Target months, account scope, essential basis, replenish-by date | Built | Small | Emergency card settings | S | EmergencyFund, PlanningSetting, Goal | Yes |
| F8 | Protection register | Protection | Policy details, covered members, premiums, renewal dates, nominees | Policy list by person, cover, premium, renewal, nominee, attachment | Missing | Table | New protection page or planning card | L | Household members | Yes |
| F9 | Household profile | All | Names, relationships, dates of birth, dependants, earner status | Member list, ages, dependants, coverage status | Missing | Table | Settings or new household page | M | Users, family | Yes |
| F10 | Allocation and concentration card | Investing | Holdings, security taxonomy, target weights | Allocation by type, subtype, geography and asset class; top holdings; concentration warnings; drift | Partial | Small for targets | Planning card or new portfolio page | M | Holdings, securities taxonomy, classification work | Yes |
| F11 | Cash-flow forecast | Cash flow | Recurring bills and income, EMIs, card dues, premiums, SIPs | Next 30/60/90 days; lowest projected cash point | Partial | No | Planning card or dashboard | M/L | Recurring transactions, loans, cards | Yes |
| F12 | Editable budget targets and essential flag | Cash flow | Category assignments, target percentages, essential flags | Editable split, essential-category list | Built | Small | Budget analyzer card | S | PlanningSetting, categories | Yes |
| F13 | Annual review report | Review | All P0 metrics, protection status, tax actions, review date | Printable year in review with priorities | Built | Small for review date | New planning page | M | F1, F2, F3, F4 | Yes |
| F14 | Behavioural nudges pack | Behaviour | Transactions, trades, income trend, subscriptions | Lifestyle-inflation check, windfall rule, raise-the-SIP prompt, drawdown-selling observation | Partial | No | Insights feed and planning card | S/M | Existing insight generators, transactions, trades | Yes |
| F15 | Protection gap calculator | Protection | Policy cover, income, liabilities, ages, dependants | Term cover needed versus held; health cover benchmark; premium share; renewal gaps | Missing | Small after F8/F9 | Protection page | M | F8, F9, income statement | Yes |
| F16 | Goal priority, inflation and wizard | Goals | Goal fields, inflation, expected return, household member | Priority order, future-rupee target, conflict detection, horizon-based mix | Partial | Small | Goals form and planning card | M | Goals, household profile | Yes |
| F17 | Tax profile and regime comparison | Tax | Income, deductions, regime, tax rules | Per-person profile, old versus new regime estimate, deduction headroom, marginal rate | Missing | Table | New tax page | L | Tax rules config, household profile | Yes |
| F18 | Capital gains and harvesting | Tax | Trades, purchase dates, prices, expenses, tax rules | FIFO lots, short/long-term buckets, exemption, set-off, cess/surcharge, "if sold today", harvesting candidates | Partial | No for lot engine; import path | New tax page | L | Purchase dates, Console CSV, lots | Yes |
| F19 | Rebalancing bands and trade plan | Investing | Current weights, target weights, bands | Drift table, buy/sell amounts, tax-aware suggestions | Missing | Small | Portfolio page | M | F10, target allocation | Yes |
| F20 | Fee and cost audit | Investing | Trade fees, expense ratios, advisory fees | Brokerage, TER, advisory fees, exit loads, total cost, cost-drag projection | Partial | Small | Portfolio page | M | Trades fees, expense categories, expense-ratio field | Yes |
| F21 | Retirement income and withdrawal plan | Retirement | Age, retirement expenses, pension, corpus, inflation | Corpus gap, withdrawal schedule, cash bucket, sequence-risk stress test | Partial | Small | New retirement page | L | F9, FIRE model, inflation | Yes |
| F22 | Risk profile questionnaire | All | Questionnaire answers | Tolerance, capacity, horizon, date; suggested allocation range | Missing | Small | Settings or onboarding | S/M | None | Yes |
| F23 | Estate and nomination register | Estate | Will and nomination details, family members, documents | Checklist by asset, nominee, executor, guardian, review date | Missing | Table | New estate page | M | F8, F9 | Yes |
| F24 | Schedule FA foreign-asset register | Tax | Foreign accounts and securities, owner, country, peak value, dates | Disclosure checklist by owner and country | Partial | No | Tax page | M | Securities country, accounts, lots | Yes |
| F25 | Tax-advantaged contribution tracker | Tax | Account and subtype mapping, contributions, tax limits | 80C, 80CCD(1B), 80D and 24(b) headroom | Partial | Small | Tax page | M | F17, account mapping | Yes |
| F26 | Advance tax and TDS tracker | Tax | Estimated tax, payments, TDS | Quarterly instalments, paid amounts, simple interest estimate | Missing | Small | Tax page | M | F17 | Yes |
| F27 | Monte Carlo and sequence-risk simulation | Retirement | Return and inflation assumptions, withdrawal plan | Distribution of outcomes, success probability, bad-decade scenarios | Missing | No | Retirement page | L | Historical return assumptions, F21 | Yes |
| F28 | Advisor export pack | All | All plan data | Clean PDF/CSV pack for an adviser or CA | Built | No | Planning page | M | F13, F17 | Yes |
| F29 | Document vault | Protection and estate | Policy, will and nomination documents | Upload, share, delete, retention | Missing | Table | Protection/estate pages | L | Storage, encryption, retention policy | Yes |
| F30 | Automated rebalancing or trading | Investing | Broker integration | Places trades | Not applicable | Not applicable | Not applicable | Not applicable | Broker integration | No: do not build |

### 5.1 What fits the existing preview gate

Every feature above that adds a planning surface should be gated exactly the way the planning page already is:

- Add require_preview_features! to the controller, or scope it to the new actions.
- Mark the page header with the Preview pill.
- Gate the nav entry with preview_gated_nav_item if the feature gets its own entry.
- Gate any background job at the family level if it manufactures data for every family; do not gate a job that only moves existing data.
- Test both states: a preview user sees the feature, a non-preview user is redirected with the flash.

Features that are pure additions to an existing preview page (F1–F7, F12, F14) inherit the page's gate and do not need a new one. Features that add a new page (F8, F17, F18, F21, F23) need the gate on their own controller. Settings-only features (F9, F22) need the gate only on the planning-specific view, not on the whole settings page.

### 5.2 What fits the design system

- Use DS::Card for every planning card, DS::ProgressBar for coverage and progress, DS::DetailRow for label/value pairs, DS::Pill for status and Preview, DS::Disclosure for assumptions and basis notes, DS::Note for caveats and DS::Alert for warnings.
- Use DS::Table for the debt list, policy list and tax checklist, with numeric: true for figures.
- Use the icon helper and functional tokens only; no raw palette classes or hex literals.
- Keep the copy in locale files; the planning page already has a full en.yml with long explanatory strings, and that is the right pattern.
- Money must be formatted through the existing money helpers so lakh/crore grouping applies automatically.
- Any new chart should reuse the existing chart controllers and follow the accessible chart description pattern already used on the savings-rate and wealth-projection cards.

---

## 6. Prioritised build order

The ordering principle is simple: **make the existing numbers trustworthy and useful before adding new data**. A planning page that says "your savings rate is 18%, your emergency cover is 2.4 months, your debt costs ₹X in interest next year, and here is what to do next" is more valuable than a page with ten new fields and no opinion.

### 6.1 P0: the advisory dashboard, no migrations

All six P0 features are buildable from existing data. They should ship as one coherent release, because together they turn the page from a set of calculators into a plan.

**F1. Planning health scorecard.** This is the feature that makes the module feel like a planner. It gathers six checks that already have data behind them — savings rate, emergency coverage, debt-to-income, goal funding, investment return and protection-data readiness — and shows each as a traffic light with a one-line reason and a "what to look at next" link. The value is not the score; it is the **definitional honesty**. Building it forces the team to decide and display what each figure includes, which is exactly the work that prevents a confident wrong number later. It is also the natural home for the "unknown" state: a household with no spending history should see "not enough data", not a red light. Effort is M because the copy, the empty states and the definitions matter more than the queries.

**F2. Debt command centre.** High-interest debt is the one place where a household gets a guaranteed, tax-free return by acting. The app already has everything needed: loan balances, rates, terms, amortisation schedules, payoff projections, card APRs, minimum payments, statement dates and recorded income. The card should show total debt, weighted average rate, monthly obligation, DTI, credit utilisation, interest cost over the next 12 months, and a payoff order with an extra-payment slider. It should show avalanche and snowball side by side and let the household choose; the point is the trade-off, not a lecture. It must label DTI as based on recorded income, not gross salary, and it must not treat a home loan and a credit card as the same kind of debt. Effort is M because the amortisation and projection logic already exists; most of the work is aggregation, copy and the extra-payment interaction.

**F3. Portfolio return card.** This is the cheapest high-value feature in the document. Portfolio::Xirr and Portfolio::MoneyWeightedReturn are already built, documented and tested; the card just needs a closing value, an account scope and a place to render. It answers the question every investor actually asks — "what return did I get on the money I put in?" — rather than the question the app currently answers, "what is my net worth?" It must show the basis (external flows or trades), because a portfolio anchored from holdings uses the trades approximation, and it must hedge when the solver reports ambiguity rather than presenting one root as the answer. It should also show contributions, withdrawals, dividends and fees for the period, so the return is explainable. Effort is S/M; the main risk is getting the account scope and the basis label right.

**F4. Goal funding plan.** Goals are already the most complete planning surface in the app. What is missing is the roll-up: every active goal, its monthly requirement, its current pace, its projected completion date and the total monthly gap, with a what-if slider. That single view answers the household's real question — "can I afford all of this?" — and it exposes goal conflict without a new data model. It should reuse the existing Goal methods (monthly_target_amount, pace, projection) rather than recompute them, and it should show "on track", "behind" and "no deadline" in the same visual language as the goals index. Effort is S/M; it is mostly composition and one interactive control.

**F5. Data confidence panel.** Trust is the product. This panel checks the inputs behind every advisory number — FX coverage, price staleness, accounts excluded from reports, unclassified securities, missing purchase dates, tax-advantaged exclusions — and says plainly what is missing. It is cheap (a PORO plus a disclosure) and it prevents the most damaging failure mode: a number that looks precise because nobody can see the missing input. It also gives the owner a to-do list for improving the data, which is more useful than a generic "connect more accounts" prompt. Effort is S; the value is disproportionate.

**F6. Tax-year readiness checklist.** Tax is the P2 project, but the readiness checklist belongs in P0 because it prevents the app from shipping a tax number it cannot support. It shows whether trades have dates and prices, how many securities lack purchase dates, whether foreign holdings exist (Schedule FA), which tax-advantaged accounts exist, and which deduction-relevant categories have activity. It should not compute tax. It should end with a clear action: "download the Console tradebook CSV" or "add purchase dates for these holdings". Effort is S; it is a diagnostic, not an engine.

**Implementation status (5 November 2026).** F1 is shipped: the planning page opens with a six-check health card — savings rate, emergency cover, debt-to-income, expensive debt, goal funding, protection — each with a state (on track / watch / needs attention / unknown) and one next action. F2 is partly shipped: the debt card reports total debt, the high-interest slice, the balance-weighted rate, the monthly interest cost, debt-to-assets and the avalanche order, and its monthly obligation and DTI feed the scorecard; the payoff-date simulator, credit utilisation and avalanche-versus-snowball comparison are still open. F3 is shipped as a planning-page portfolio-return card: money-weighted return (XIRR) with its trade basis stated, the ambiguity hedge, portfolio value, trailing-year money in and income, and a link to the full report. F4 is shipped: goal funding rolls dated active goals into a monthly requirement versus current pace, with the per-goal gap and status. F5 is shipped as a data-confidence card (missing FX rates, stale prices, missing purchase dates, unclassified securities, excluded accounts) and F6 as a tax-year readiness card (trades, trade prices, purchase dates, foreign assets, tax-advantaged accounts — no tax computed). That completes the no-migration P0 set, and F2's remaining pieces are now shipped too: the debt card shows credit utilisation and a server-rendered payoff plan (current payments versus +50% and +100%, with months to debt-free and total interest), plus avalanche and snowball orderings. F7 is shipped as a configurable emergency target (1–24 months, stored on the planning setting), and the card, budget targets and health bands read it. The P0 layer is therefore complete.

P1 is under way: F9 (household profile) is shipped as a household card on the planning page backed by a new `household_members` table — names, relationships, dates of birth and a dependant flag, with ages computed from the date and no requirement that a person be an app user. The card is preview-gated with the rest of the page.

F8 (protection register) is now shipped: an `insurance_policies` table and a Protection card holding type, insurer, covered member, cover amount, premium and frequency, renewal date and nominee, with add/remove and renewal warnings inside 30 days. F15 (protection gap) has a first pass on top of it: the card totals life and health cover and annual premiums, compares life cover with ten times recorded annual income, counts dependants from the household profile, and the health scorecard's protection check now turns from "unknown" into a real on-track/needs-attention state once cover and income exist. F15 now also reports premium affordability (annual premiums as a share of recorded income, with 5% and 10% watch bands) and whether any health cover is recorded at all; per-member cover adequacy is the remaining piece. F12 (editable budget targets) is shipped too: needs/wants/savings shares are stored on the planning setting, must total 100, and the budget analyzer scores against the household's own split rather than the fixed 50/30/20. F10 (allocation and concentration) is shipped as a planning card: invested vs cash, the largest position with 10%/20% concentration bands, the five largest holdings with weight bars, and a breakdown by asset class (unclassified holdings are grouped, not dropped). What F10 still needs is target weights and a rebalancing view (F19), which depend on a risk profile. F16 is now fully shipped: goals carry high/medium/low priority (default medium) and an optional inflation assumption. The goal-funding card presents high-priority goals first and plans against the future-rupee target when inflation is set, while the goals page keeps the nominal figure. F22 (risk profile) is shipped as an optional conservative/moderate/aggressive setting on the planning page; the allocation card compares the current equity share with a conventional range for that profile (10 points outside is a watch, further is attention). This gives F19 its foundation. F19's rebalancing plan is now shipped: when the equity share sits outside the profile's band, the allocation card says how much to move back to the middle of the band, with the explicit caveat that it is a tax-unaware plan and Sure never places orders. P2's tax layer is under way. The FIFO lot engine (Portfolio::TaxLots) is shipped: oldest lots first, buy fees capitalised, sell fees allocated, splits scaled before the trades on their ex-date, internal transfers ignored, and a sale with no matching purchase reported as unknown-origin rather than given a fabricated cost. Above it, FinancialPlanning::RealisedGains reports the current financial year's sales split into short and long term at 365 days, converting proceeds at the sale date and cost at the purchase date. FinancialPlanning::CapitalGainsEstimate adds the mechanics that decide the taxable amount: a per-owner tax unit (nil owners grouped as unassigned), short-term losses offset against long-term gains, long-term losses only against long-term gains, the Indian ₹1.25 lakh LTCG exemption applied after set-off, and unused losses reported as carried forward. Rates are deliberately not applied. Both cards state clearly that they are estimates from recorded data, not tax calculations. Asset-specific holding rules are now applied from the security metadata the app already stores: domestic listed equity turns long-term after 365 days, foreign and unlisted shares after 730, and debt funds (mutual fund plus fixed income) are slab-taxed whenever sold and kept outside the exemption and the short/long set-off. The Zerodha Console tradebook import is shipped: a preview-capable service parses the CSV (ISIN first, ticker second), reports unresolved symbols instead of inventing securities, skips rows already recorded so the same file can be re-run, and records trades with zero fees (the tradebook carries none). It is wired to a file-upload form on the tax-readiness card. Still open: current-year rates and surcharge/cess, and the Schedule FA disclosure flag. F14 (behavioural nudges) has a first pass shipped as a Coaching card: it names two tensions the figures already show — cash sitting well beyond the household's own buffer target, and high-interest debt held alongside investments — and nothing else. Judgement-heavy nudges (lifestyle-inflation definitions, windfall rules) are deliberately not invented yet. F11 (cash-flow forecast) is shipped as a planning card: cash on hand plus the trailing monthly surplus (income minus spending, debt service and insurance premiums), projected 30/60/90 days ahead with a warning when the line crosses zero. It is deliberately an average-based projection, not a day-level bill calendar, and says so; a missing debt payment is flagged rather than silently treated as zero. F15's per-member piece is partly shipped too: the protection card now counts adults with life cover attached and names the adults without any, treating a household-wide policy as covering everyone. F13 (annual review report) is shipped as a preview-gated "Year in review" page linked from the planning header: a twelve-month net-worth movement, savings rate and amounts, invested/withdrawn/investment income, a protection snapshot, goal progress, the scorecard checks and the priorities carried into next year, with a "mark reviewed" action stored on the planning setting.


**P0 definition of done:**

- Every number has a basis line and an as-of date, or a visible "unavailable" state.
- The scorecard allows "unknown" and never turns a missing input into a red light.
- No P0 feature needs a migration.
- The cards work for a household with one account, multiple currencies and no spending history.
- The copy is reviewed for tone: calm, specific, non-judgemental, no product recommendations.
- The preview gate and the Preview pill are in place.
- Tests cover the empty, single-account, multi-currency and missing-FX states.

### 6.2 P1: the household and protection layer

P1 is where the app stops being a portfolio tracker and starts being a planning tool. The order within P1 matters:

1. **F9 Household profile** first. Dates of birth and dependants are prerequisites for protection, retirement, education goals and estate. It is a small table and a settings form, but everything else waits on it.
2. **F8 Protection register** second. It is the largest single gap in the product and the feature a veteran adviser would notice first. It needs F9 for covered members and owners.
3. **F15 Protection gap calculator** third, because a gap calculator without a register is a quiz. It also needs income and liabilities, which already exist.
4. **F7 Emergency fund settings** alongside F8, because the emergency card already exists and only needs configuration and a link to a maintained goal.
5. **F10 Allocation and concentration card** next. Start with the reliable taxonomy — account type, investment subtype, country, mutual-fund flag — and add security-level asset class as the classifier improves. Do not block the card on perfect classification.
6. **F11 Cash-flow forecast** after that, because it depends on recurring-transaction quality and on the emergency and debt cards for context.
7. **F12 Editable budget targets and essential flag** can run in parallel; it is a small settings change that improves the emergency fund, FIRE and the budget analyzer.
8. **F13 Annual review report** last in P1, because it aggregates the P0 cards and the P1 protection data.
9. **F14 Behavioural nudges pack** can run alongside; it extends the existing insight generators and needs no schema.
10. **F16 Goal priority and inflation** can run alongside F4; it is a small schema addition to the goals table.

P1 rationale in one line each: the household profile makes every other domain possible; protection is the biggest gap; the emergency settings make an existing card honest; allocation is the most requested investing view; the forecast makes cash flow actionable; budget targets remove a known limitation; the review report closes the loop; the nudges make the app a coach rather than a report; goal priority makes the funding plan decisive.

### 6.3 P2: the tax, retirement and estate layer

P2 is where the app needs real domain logic and, in places, a tax engine. The order should follow the project's existing tax build order rather than duplicate it:

1. **F17 Tax profile and regime comparison** first, because it is the per-person foundation. Store the tax rules in one dated configuration with a "verified on" date and a "re-check required" flag. Do not hardcode rates in views.
2. **F18 Capital gains and harvesting** second, following the project notes: confirm the price/data gate, wire the existing XIRR, build the FIFO lot engine, import the Console tradebook CSV, then compute per-person capital gains with set-off and the exemption. Do not compute gains from holdings or average cost.
3. **F25 Tax-advantaged contribution tracker** and **F26 Advance tax and TDS tracker** alongside F17, because they are the practical, year-round parts of tax planning.
4. **F24 Schedule FA foreign-asset register** once F17 and F18 exist, because it needs owner, country, peak value and acquisition date.
5. **F19 Rebalancing bands** and **F20 Fee audit** after F10, because both need allocation data and target weights.
6. **F21 Retirement income and withdrawal plan** after F9 and the FIRE honesty pass, because it needs ages, retirement expenses, pension income and inflation.
7. **F22 Risk profile** can run earlier if allocation guidance needs it, but it is not a blocker for the allocation card.
8. **F23 Estate and nomination register** can run in parallel with F8; it shares the household-member data and the document-attachment pattern.

### 6.4 Later, and what not to build

**Later:** F27 Monte Carlo and sequence-risk simulation, F28 advisor export pack, F29 document vault. These are valuable but expensive, and they depend on the P1/P2 data being in place.

**Do not build:**

- Product recommendations ("buy this fund", "buy this policy"). It crosses the education/advisory line and creates a regulatory and trust problem.
- Execution: trading, policy purchase, auto-rebalancing, ITR filing. The app should produce a plan and a schedule; the human acts.
- A credit-score integration that scrapes a bureau without explicit consent. If it is ever added, it should be opt-in, explained and deletable.
- A document vault without encryption, sharing rules and a deletion policy. Health and estate documents are the most sensitive data in the app.
- A "financial freedom score" that hides its inputs or shames the household. The scorecard should explain, not rank.

### 6.5 Sequencing rules and definition of done for the whole programme

- **Definition before data.** Decide and document what each figure includes before building the card. The app's strength is its scoping; the risk is presenting a scoped figure as a universal one.
- **No migration without a data-confidence story.** If a new table is added, the UI must handle "not filled in" gracefully from day one.
- **Per-person entities need an owner from the start.** Adding owner_id later is painful and creates ambiguous data.
- **Tax rules are configuration, not code.** One file or table, dated, versioned, with a verification status.
- **Every card has an empty state, an unavailable state and a stale-data state.** These are not edge cases in planning; they are the normal case for a new user.
- **Copy is part of the feature.** The planning page already has long explanatory strings; keep that standard. A number without an explanation is a dashboard, not a plan.

---

## 7. Benchmarks and assumptions reference

This table collects the rules of thumb used above, with an honest status. It is a reference for copy and defaults, not a source of legal or tax certainty.

| Benchmark | Typical value | Status | How the app should use it |
| --- | --- | --- | --- |
| Savings rate | 20% of income | Practitioner heuristic (50/30/20) | A target line on the scorecard, adjustable by the household |
| 50/30/20 split | 50 needs, 30 wants, 20 savings | Practitioner heuristic | Default only; editable |
| Emergency fund | 3–6 months of essential expenses | Practitioner consensus; the CFPB page could not be retrieved in this pass | Default six months; 3–12 configurable |
| Debt-to-income | Under 36% | US framing; Indian lenders often use FOIR around 40–50% | Show the band and label it as a heuristic |
| Housing cost | Under 30% of income | Common affordability rule | A soft warning, not a hard fail |
| Credit utilisation | Under 30% of limit | Common credit-health heuristic | A warning on the debt card |
| Equity allocation | 100 minus age, as a starting point | Heuristic; ignores human capital, liabilities and risk capacity | Do not use without age; treat as education |
| Single-stock concentration | Under 5–10% | Practitioner heuristic | A concentration warning, not a rule |
| Sector concentration | Under 25–30% | Practitioner heuristic | A warning when classification exists |
| Rebalancing band | Plus or minus 5 percentage points, or 20% relative | Practitioner heuristic | Default band; user-adjustable |
| Safe withdrawal rate | 4% (25 times expenses) | US historical rule of thumb; not a guarantee, pre-tax and pre-fee | A starting point; show sensitivity at 3%, 3.5%, 4% and 4.5% |
| FIRE multiple | 25x at 4%; 30x at 3.3%; 20x at 5% | Arithmetic from the withdrawal rate | Show the multiple next to the rate |
| Term-life cover | 10–15 times annual income, plus liabilities, minus liquid assets | Practitioner heuristic | A gap estimate, not a recommendation |
| Health cover | Enough to cover a metro hospitalisation, plus a super top-up | Practitioner heuristic; no single number | A checklist and a benchmark range, not a precise target |
| Insurance premium | 2–4% of income for a young household | Practitioner heuristic | A soft band, not a rule |
| India inflation | 5–7% | Planning assumption, not a forecast | A configurable assumption; re-check |
| Healthcare inflation | Higher than headline inflation | Planning assumption | A separate assumption for retirement |
| Equity return (India, long run) | 10–12% nominal, as a planning assumption | Assumption, not a guarantee | A configurable assumption; show a range |
| Debt return | 6–8% nominal, as a planning assumption | Assumption | A configurable assumption |
| 80C ceiling | ₹1.5 lakh | Long-standing; re-check current year | A configurable tax limit |
| 80CCD(1B) | ₹50,000 | NPS Trust page fetched for this document | A configurable tax limit |
| 80CCE ceiling | ₹1.5 lakh | NPS Trust page fetched for this document | A configurable tax limit |
| Employer NPS | 10% of salary old regime, 14% new regime | NPS Trust page fetched for this document | A configurable tax limit |
| Listed-equity STCG | 20% under section 111A | App notes, unverified for the current year | Configuration with effective dates |
| Listed-equity LTCG | 12.5% under section 112A, ₹1.25 lakh exemption | App notes, unverified for the current year | Configuration with effective dates |
| Debt-fund gains | Slab rate | App notes, unverified for the current year | Configuration with effective dates |
| Unlisted and foreign shares | 24-month long-term threshold, 12.5% long-term | App notes, unverified for the current year | Configuration with effective dates |
| Cess | 4% health and education cess | App notes, unverified for the current year | Configuration with effective dates |
| Advance tax | 15%, 45%, 75%, 100% by June, September, December, March | Standard schedule; re-check | A reminder schedule, not a computation |

### 7.1 Assumptions the app should store in one place

Today the app stores only the FIRE variant, withdrawal rate, target year and annual growth rate. A planning tool needs a small, visible assumptions set:

- Inflation rate, and a separate healthcare inflation rate.
- Expected nominal return for equity and for debt.
- Salary or income growth.
- Retirement age and life expectancy.
- Safe withdrawal rate and whether it is gross or net of tax and fees.
- Emergency target months and the essential-expense basis.
- Target asset allocation and rebalancing bands.
- Tax rates and limits, with effective dates and a verification status.

The assumptions should be editable, shown on the cards they affect, and included in the annual review report. A plan with hidden assumptions is not a plan.

### 7.2 What "estimate" means on screen

The app should use one consistent vocabulary:

- **Actual:** derived from recorded transactions and balances, with a complete data set.
- **Estimate:** derived from assumptions (returns, inflation, tax rates) and labelled as such.
- **Unavailable:** the inputs are missing; do not substitute zero or a guess.
- **Stale:** derived from data older than the card's freshness threshold; show the date.

A veteran adviser would rather see "unavailable" than a confident number built on a missing input. The same should be true of the product.

---

## 8. How the features should look and behave

The planning page already has a coherent shape: a header with a Preview pill, a two-column card grid, a period picker where the period matters, and a long disclosure for assumptions. New features should extend that shape, not invent a second one.

**Page hierarchy.**

1. **Header:** title, subtitle, Preview pill, one sentence that says what the page is for.
2. **Scorecard row:** the health scorecard and the emergency card, because they are the two "are we okay?" answers.
3. **Debt and goals row:** the two domains where action is most concrete.
4. **Return and allocation row:** what the portfolio did and what it holds.
5. **Tax and protection row:** the data-readiness and policy registers.
6. **Projection and assumptions:** FIRE and wealth projection with a disclosure.
7. **Footer:** data confidence panel and the "not financial advice" note.

**Card rules.**

- One question per card. If a card answers two questions, split it.
- The headline number is large; the basis line is small but always present.
- Every card has a link to the page or account where the user can act on it.
- Every card has an empty state that explains what data is needed, not just "no data".
- Every card has a stale-data state with the as-of date.
- Warnings are specific: "Your card balance is 62% of its limit" beats "credit utilisation is high".

**The scorecard.**

The scorecard is the one place where a summary is appropriate, but it must not become a mystery score. Use a simple traffic-light list, each row with the check name, the household's figure, the benchmark, and a one-line explanation. Allow "unknown" for every row. The "next best action" should be a single sentence chosen by a fixed priority order, not by an opaque model:

1. Emergency coverage below three months.
2. Credit-card or high-cost debt above a threshold.
3. No protection data (a data gap, not a failure).
4. Savings rate below target.
5. Goals behind pace.
6. Otherwise: keep going, review annually.

**Assumptions and basis.**

Use DS::Disclosure, as the FIRE card already does. Put the assumptions in one place: inflation, returns, withdrawal rate, tax basis, account scope, data dates. Make the assumptions editable where they change a number; do not scatter them across cards. The disclosure should be written in plain English, not actuarial notation.

**Money and formatting.**

- Use the existing money helpers so lakh/crore grouping applies.
- Show rupees without paise on planning cards; paise are noise at this altitude.
- Show percentages to one decimal place at most.
- Use tabular numerals for figures.
- Mark privacy-sensitive figures with the existing privacy-sensitive class.
- Never mix currencies in one figure without saying so; convert and show the base currency.

**Tables.**

Use DS::Table for the debt list, policy list, tax checklist and estate register. Numeric columns right-aligned with numeric: true. Inset tables inside cards. Sticky headers for long lists. A label for keyboard users when a table scrolls.

**Charts.**

Reuse the existing chart controllers and the accessible description pattern. A chart must have a text description and a table or figure alternative. Do not add a chart where a number and a sentence would do.

**Tone.**

Calm, specific, non-judgemental. "You are 2.4 months short of a six-month buffer" is useful; "you are failing at saving" is not. Avoid shame, urgency and gamification that rewards trading. The app should be the steady voice in the household's financial life, not another source of anxiety.

**Print and export.**

The annual review report should print cleanly: no nav, no interactive controls, a clear date, the household name and a page for each domain. A PDF export can come later; a print stylesheet is enough for the first version.

**Accessibility and mobile.**

The planning page is already responsive with container queries. New cards should work at one column on mobile, keep the headline number legible, and not rely on colour alone for status. Traffic lights need text labels and icons, not just red/amber/green.

**Performance.**

Every planning card reads the balance sheet, the income statement or holdings. These are expensive. The page already memoizes some of them and uses no-store headers. New cards should share the same statement instances where possible, avoid N+1 queries over accounts and holdings, and cache expensive aggregates per request. A planning page that takes five seconds will not be opened.

---

## 9. Source notes and verification log

This document uses a mix of official sources, the app's own project notes and practitioner heuristics. The log below says what was actually fetched, what it showed and what remains unverified. It is deliberately explicit, because a planning document that invents citations is worse than one that admits a gap.

### 9.1 Official sources checked

| Source | URL | What it verified | Status |
| --- | --- | --- | --- |
| SEBI Investor Education — Money Matters | https://investor.sebi.gov.in/moneymatters.html | The personal-finance topic list used in section 1: saving, goal setting, budgeting, inflation and investing, debt management, insurance, retirement planning and estate planning | Fetched successfully (200). Content read. |
| SEBI Investor Education — Personal Investments | https://investor.sebi.gov.in/personalinvestments.html | The investing topics: why invest, invest early, factors to consider, asset classes, fraud awareness | Fetched successfully (200). Content read. |
| SEBI Investor Education — Nomination | https://investor.sebi.gov.in/market-nomination.html | Nomination facility for demat accounts and mutual-fund folios; the choice between nominating and opting out | Fetched successfully (200). The page's deadline text refers to 30 June 2024 and is out of date; do not quote it as current. |
| CFP Board — Code of Ethics and Standards of Conduct | https://www.cfp.net/ethics/code-of-ethics-and-standards-of-conduct | Fiduciary duty, duties of care and loyalty, and the seven practice standards used in section 1 | Fetched successfully (200). Content read. |
| RBI — Financial Education | https://www.rbi.org.in/financialeducation/home.aspx | The RBI financial-education initiative and its scope (awareness, financial products, good practices, consumer protection) | Fetched successfully (200). No specific planning benchmark was taken from it. |
| NPS Trust — Tax Benefits under NPS | https://npstrust.org.in/benefits-of-nps | 80CCD(1), 80CCD(1B) at ₹50,000, the 80CCE ceiling of ₹1.5 lakh, and employer NPS at 10% of salary under the old regime and 14% under the new regime | Fetched successfully (200). Figures read from the page; re-check before shipping. |
| IRDAI | https://irdai.gov.in/ | The insurance regulator's site and its policyholder protection and grievance sections | Fetched successfully (200). No specific cover benchmark was taken from it. |
| AMFI | https://www.amfiindia.com/ | The mutual-fund industry body's investor resources and NAV data | Fetched successfully (200). The /investor-corner path returned 404. |
| Income Tax Department e-filing portal | https://www.incometax.gov.in/iec/foportal/ | The official e-filing portal exists and has tax-slabs and deductions sections | Fetched successfully (200), but the help-page body did not render in the fetch (navigation only), so no rate was verified. |

### 9.2 Sources that failed or could not be verified

| Source | What happened | Consequence |
| --- | --- | --- |
| CFPB — An essential guide to building an emergency fund (https://www.consumerfinance.gov/an-essential-guide-to-building-an-emergency-fund/) | The page returned 200, but the fetch captured the site navigation and not the article body; the text was not retrievable | The 3–6 month emergency-fund figure is marked as practitioner consensus, not a verified citation |
| CFPB — Ask CFPB emergency-fund page | Returned unrelated content in the fetched text | Not used |
| Investor.gov — emergency fund page | HTTP 403 Access Denied | Not used |
| incometaxindia.gov.in (tax rates and tax information pages) | HTTP 403 Access Denied | Tax rates remain unverified |
| FINRA — emergency fund page | HTTP 404 | Not used |
| AMFI investor-corner | HTTP 404 | The AMFI home page was used instead |
| SEBI education.html | HTTP 404 | The Money Matters and Personal Investments pages were used instead |

The 4% rule is described in this document as a US historical rule of thumb, usually attributed to Bengen (1994) and the Trinity study. No primary source was fetched for it in this pass, and it is not an Indian regulatory benchmark. The app already treats it as a starting point by offering 3.0%, 3.3%, 4.0% and 6.5% variants.

### 9.3 Internal sources

- PROJECT_DETAILS.md, especially section 4 (architecture), section 13 (what is not built), section 16 (API endpoints) and sections 23.3 to 23.7 (purchase dates, capital-gains rules, design decisions, build order and gotchas). The capital-gains rules in this document are copied from the app's own notes and are explicitly marked unverified for the current year.
- docs/llm-guides/architecture.md — the family/user/account/entry model, the money and currency rules, and the provider conventions.
- docs/llm-guides/design-system.md — DS primitives, tokens, icons, tables and form actions.
- docs/llm-guides/gating-a-preview-feature.md — the preview gate, the Preview pill, the nav helper and the background-job caveat.
- docs/llm-guides/goals.md — the goals data model, the shared pool, pledges, pace and projection.
- app/models/financial_planning/savings_rate.rb, budget_analyzer.rb, fire_progress.rb, wealth_projector.rb, holdings_cost_basis_series.rb and emergency_fund.rb.
- app/models/planning_setting.rb, app/controllers/financial_planning_controller.rb and app/views/financial_planning/*.
- app/models/goal.rb, loan.rb, credit_card.rb, investment.rb, security.rb, holding.rb, income_statement.rb, balance_sheet.rb and transaction.rb.
- app/models/portfolio/xirr.rb, portfolio/money_weighted_return.rb and portfolio/flow_classifier.rb.
- db/schema.rb for the tables, columns and constraints referenced in this document.

### 9.4 What remains unverified

- All current-year Indian tax rates, slabs, surcharge bands, exemption limits, deduction limits and capital-gains thresholds. The app's own notes say the same. Re-check against the current Finance Act and the Income Tax Department's published rates before shipping any figure.
- The 3–6 month emergency-fund benchmark as an official citation. It is used as a practitioner heuristic.
- The 36% debt-to-income framing and the 40–50% Indian FOIR range. Both are practitioner heuristics, not regulatory limits.
- The 10–15 times income term-cover heuristic, the 2–4% premium band, the 5–10% single-stock limit and the 25–30% sector limit. All are practitioner heuristics.
- Any claim about a specific insurer, fund, broker or product. This document makes none.
- The exact current nomination deadlines and forms. SEBI's page is out of date; check the current SEBI circular and the individual institution's process.

---

## Appendix A. Plain-English glossary

| Term | Plain-English meaning |
| --- | --- |
| Asset allocation | How the money is split between equity, debt, gold, cash, property and other assets |
| Avalanche method | Pay the highest-interest debt first, then the next, to minimise interest |
| Snowball method | Pay the smallest balance first, then the next, to build momentum |
| CFP | Certified Financial Planner, a professional certification with a published code of ethics and practice standards |
| Coast FIRE | Reach a portfolio size by a chosen age, then stop contributing and let growth carry it to retirement |
| Lean FIRE | A deliberately modest retirement, with a lower withdrawal rate and lower expenses |
| Fat FIRE | A richer retirement, requiring a larger corpus and a lower withdrawal rate |
| Barista FIRE | A partially retired state where part-time work covers part of the expenses |
| Debt-to-income (DTI) | Monthly debt payments divided by monthly income |
| FOIR | Fixed Obligation to Income Ratio; the share of income committed to fixed obligations, commonly used by Indian lenders |
| Emergency fund | Cash set aside for a loss of income or an unexpected essential expense |
| Equity | Ownership in a company, through shares or equity mutual funds |
| Debt | Lending money, through bonds, fixed deposits, debt funds or similar |
| Expense ratio / TER | The annual cost of a mutual fund or ETF, expressed as a percentage of assets |
| FIFO | First in, first out; the lot method used for capital gains |
| HRA | House Rent Allowance, a salary component with a tax exemption subject to conditions |
| HLV | Human Life Value; a way to estimate how much life cover a household needs |
| LTCG / STCG | Long-term and short-term capital gains, taxed differently |
| Liquidity | How quickly an asset can be converted to cash without a loss |
| Monte Carlo | A simulation that runs many possible market paths to show a range of outcomes |
| Nomination | Naming a person to receive an asset from an institution; not the same as a will |
| NPS | National Pension System, a long-term retirement product with tax benefits |
| Rebalancing | Bringing the portfolio back to its target allocation after drift |
| Sequence-of-returns risk | The risk that poor returns early in retirement do more damage than the same returns later |
| SIP | Systematic Investment Plan; a recurring investment, usually monthly |
| Sinking fund | Money set aside monthly for a known future expense |
| Term insurance | Pure life cover with no investment component |
| ULIP | Unit Linked Insurance Plan; insurance plus investment, usually expensive as either |
| XIRR | A money-weighted annual return for irregular cash flows; what the investor actually earned |
| TWR | Time-weighted return; what the investments did, independent of cash-flow timing |
| Withdrawal rate | The percentage of the corpus withdrawn each year in retirement |

## Appendix B. India-specific annual checklist

This is the checklist the app should eventually encode in the annual review. It is organised around the Indian financial year.

| When | What to check | Where it belongs |
| --- | --- | --- |
| April | New financial year: update income, expenses and goals; set the year's savings target | Annual review |
| April–May | Confirm tax regime for the year; estimate advance tax; check TDS and Form 26AS/AIS | Tax page |
| June | First advance-tax instalment (15%); review insurance renewals | Tax page, protection register |
| July | File the previous year's return if not already filed; check loss carry-forward | Tax page |
| September | Second advance-tax instalment (45%); review health-cover renewal | Tax page, protection register |
| October–November | Festival spending plan; check the sinking fund; review subscriptions | Cash flow, insights |
| December | Third advance-tax instalment (75%); year-end capital-gains harvesting review | Tax page |
| January–February | Investment proof for employer; 80C/80D/80CCD(1B) headroom; tax-saving investments | Tax page, contribution tracker |
| March | Fourth advance-tax instalment (100%); capital-gains harvesting; tax-year-end review | Tax page |
| Any time | Update nominations, will, insurance and emergency fund after a life event | Estate register, protection register |

The app should not assume this checklist is exhaustive or legally sufficient. It is a prompt for the household and a structure for the annual review, not a substitute for a CA or a lawyer.

---

**Final note.** The framework above is deliberately conservative about what the app can claim. The existing planning module is already better than most consumer finance apps at the hardest part: it uses the household's real ledger rather than a questionnaire. The next step is not more calculators. It is to make the existing numbers trustworthy, put them in the order a planner would use them, and be honest about the person-level data the app does not yet have. That is what a veteran adviser would recognise as a planning framework rather than a dashboard.
