# V16 Preview 30 — Planning suggestions beta

Update the Control Center only. VM agents remain at Preview 29; no VM update or recalibration is needed. This release preserves the agent files, execution protocol and existing queue logic.

## Use

In Planning, choose Strategy → Non-consistency tests, then click Suggest pairs. Checked accounts form the pool; with no accounts checked, the current loaded Airtable view forms the pool. Suggestions append to Build Pairs and preserve existing manual drafts. Review and confirm each card individually. Selecting a strategy or generating suggestions never confirms pairs, starts the queue or sends an agent command.

Each suggestion defaults to 2 NQ per account, ratio 1:1, opposite directions. Buy left / sell right is an editable starting arrangement, not a market-direction prediction. Existing contract-month resolution applies when the user confirms.

## Matching and priority

- Compare the explicit `firm` field, ignoring case and surrounding/repeated whitespace. Same-firm pairs are never suggested. Missing or ambiguous firm values, duplicate account IDs, missing calculation data, completed profit requirements and unusable amounts receive an explanation.
- Exclude accounts already in browser drafts, pending/active queue rows, or assigned pairs. Repeated clicks do not reuse them. Keep current manual draft settings and existing confirmations intact.
- First prioritize feasible one-winning-trade profit finishes, ordered by smallest remaining required profit. Then prioritize accounts nearest their target that need further trades. Compatible partners must support both directions' gain/loss limits. Random choice breaks otherwise equal priorities. Matching is greedy by priority, not a guarantee of the maximum possible number of pairs.
- Recheck explicit firm values when suggested cards receive refreshed Planning data. Preserve the existing manual confirmation and execution checks.

## Calculation

A zero or blank Consistency means no consistency cap and no $50 consistency buffer. Otherwise use the decimal fraction, for example 0.40:

RequiredTotal = max(ProfitTarget, max(largestProfitDay, CurrentPnL) / Consistency), rounded upward to cents.
RemainingProfit = max(0, RequiredTotal - CurrentProfit).
TodayAllowance = max(0, RequiredTotal * Consistency - 50 - CurrentPnL).

The largest-day input must be present when consistency applies. Including a larger current-day profit prevents relying on an outdated largestProfitDay. Negative CurrentPnL increases today's remaining allowance. Without consistency, RequiredTotal is ProfitTarget.

Each gain is capped by that account's daily allowance, its partner's RealDrawdown and the existing supported amount limit. Stops mirror the partner's gain at 1:1. No extra drawdown buffer was added; the separate proposed buffer was not approved.

NQ has a $20 point value and 0.25-point minimum tick, so 2 NQ move $10 per tick. Risk ceilings round downward to $10 increments. Remaining profit rounds up only when both ceilings permit, so $598.04 remaining can become a $600 target without exceeding either cap. A smaller permitted gain is marked as needing further trades. Sub-$10 drawdown cannot support this beta's fixed 2 NQ quantity.

Contract specification: https://www.cmegroup.com/markets/equities/nasdaq/e-mini-nasdaq-100.contractSpecs.html

Amounts are totals for the two contracts. Calculations use the current Planning snapshot, with the firm's day-boundary/account metrics supplied by Airtable. Costs and actual fills can differ; a one-win finish is a pre-cost calculation, not guaranteed account qualification. Suggestions remain editable snapshots and do not automatically recalculate when other trades finish.

## Validation

230 Python regressions and the suggestion/legacy JavaScript tests passed locally. Windows, TLS, calibration, legacy browser and beta-suggestion Chromium validation passed in run 35181028214. All VM-agent file hashes match Preview 29, and all 28 packaged files match uploaded source. No live NinjaTrader orders or broker fills were tested.
