# Preview 33 — revised beta pair suggestions

Control Center only. Existing Preview 31 agents remain compatible; no VM agent update is required. Manual pairing, queued/active trades, execution, account sync and VM calibration are unchanged.

## Inputs and calculations

- `InitialBalance` means today's opening account balance, not original account size. Set it before trading each day, hold it fixed during that trading day, and do not overwrite it with periodic website syncs.
- `Realized PnL` replaces `CurrentPnL` for today's consistency allowance. Consistency zero/blank still means no consistency cap and no division.
- Suggestions compare `CurrentBalance - InitialBalance` with `Realized PnL` (one cent tolerance). Missing inputs or mismatches skip the account with a specific message. Check open positions, fees, day boundaries and stale syncs before retrying.
- Website `balance` and `CurrentProfit` must belong to the same scraper snapshot. Opening total profit = `CurrentProfit - (balance - InitialBalance)`; current total profit = opening total profit + `(CurrentBalance - InitialBalance)`. This adjusts website profit by NinjaTrader's balance difference and avoids adding today's realized P&L twice when the website catches up. No fixed $50,000 starting capital is assumed.
- `ProfitTarget` stays the required profit amount (for example $3,000), not the target balance ($53,000).
- Required total profit remains max(ProfitTarget, largest day / Consistency). The daily allowance remains required total × Consistency − $50 − Realized PnL.
- Minimum suggested gain is $100 on BOTH sides. Never exceed the actual ProfitTarget by more than $100, the consistency allowance, or the partner's RealDrawdown. An account whose consistency requirement exceeds ProfitTarget + $100 is skipped for separate review.
- Near-target accounts can receive a $100 gain only when all caps permit it. Two NQ each, whole-tick dollar rounding, cross-firm matching, closest feasible one-win priority and mirrored stops remain in effect.
- Saved older unconfirmed suggestions require regeneration. Refreshed data and edited amounts are rechecked before confirming or adding all. Manual cards are unaffected.

## User examples checked

- MFF: current balance $52,382.94, website balance $52,024.46, website profit $2,024.46, opening balance $52,024.46 and realized P&L $358.48 produces total profit $2,382.94 and a $620 target (if partner caps permit). Refreshing the website snapshot to balance $52,382.94/profit $2,382.94 produces the same result.
- FundedNext: $927.72 realized today with a $2,500 target and 40% consistency leaves only $22.28 after the $50 buffer. Skip because it cannot support the $100 minimum.
- A daily loss of $451.52 expands the same consistency allowance to $1,401.52; total-target progress is still capped separately.

Validation: suggestion math regression tests, compact payload checks, 242 Python tests, and Windows/browser release validation. No live trades were placed during testing.
