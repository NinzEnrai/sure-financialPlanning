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

1. **P0, no migrations:** turn the planning page into an advisory dashboard from data that already exists. A health scorecard, a debt command centre, an XIRR/return card, a goal funding plan, a data-confidence panel and a tax-year readiness checklist. These make the app feel like a planner rather than four unrelated calculators, and they expose the gaps honestly instead of hiding them.
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

That is enough for a real debt dashboard today, without a migration. The two gaps are the **credit limit** (not stored as a column, but inferable as outstanding balance plus available credit) and the **India loan subtypes** (personal, gold, education, consumer durable are not in the list; they would map to "other").

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

<!-- CONTINUE -->
