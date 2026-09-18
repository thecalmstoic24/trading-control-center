# Preview 38 candidate — workflow completion and Auto Quantity Beta

**Release candidate.** Public-source publication is approved. The updater remains on Preview 37 until Windows and browser validation passes.

Update the Control Center **and every participating VM agent**. Existing identities, saved connections, and trade history are retained. Updating software does not start trading.

## One-time NinjaTrader setup

On each VM, close NinjaTrader, run the new **Install NinjaTrader Telemetry** desktop shortcut, reopen NinjaTrader, and compile in NinjaScript Editor (F5). The read-only TccOrderSafety add-on supplies account connection, working-order, and position checks for recovery. No orders are submitted or canceled by this add-on. Release recovery requires fresh telemetry for the original account even if Chart Trader now shows another account. Missing/stale telemetry blocks recovery with a setup message.

On **only the designated candle-source VM**, add **TccTelemetry** to a 1-minute NQ or MNQ chart using the same quarterly contract as the Control Center. Keep that chart connected. Select that VM in Planning's Auto Quantity Beta settings. The settings default to off, 10 completed bars, and a 1× multiplier; bar count and multiplier are editable. Those numerical defaults are implementation defaults, not previously agreed fixed values.

## Changes

- VM-tab Release VMs clears the entire pair reservation after fresh Flat, original-account position/order, and pending-command checks. Errors retain Error status and are never automatically re-entered. Automatic error recovery checks every five seconds. Recovery no longer deadlocks on a retained agent pair-active flag or changed selected account/quantity. Skip Results stops only the related export before verified release.
- Error replaces Errored. Missing/ambiguous VM matches show red Need check and do not hold up other pairs. Error details use an inline i button. Cancel appears before Skip Results/Retry.
- Sticky navigation keeps compact VM error names left, tabs centered, and session progress right. Waiting pulses blue every 1.5 seconds, Pairing uses soft amber, and reduced-motion preferences are honored. Activity times use Central Time with seconds. Headers remain sticky and queue text is larger.
- Qty/Profit/Loss inputs support six visible digits, confirmation labels fit, and balance/P&L cells show Buy/Sell arrows.
- Group by Fund has independent per-fund column sorting and counts.
- Airtable Priority 1, 2, 3, then blank regular determines eligible dispatch order. Priority and left/right quantities refresh for unstarted pairs; invalid changes block only that pair. Settings freeze when preparation starts. Background edit reads do not occupy the scheduler's network path.
- Test Non-consistency rounds limiting drawdown up to the next $10 and permits that rounding excess. Automatic suggestions retain the $100 minimum and target cushion of remaining profit + $25. Manual edits can be below $100. Other consistency/overshoot caps remain enforced.
- Calculated/submitted currency amounts round upward to whole dollars. Quantity is never blindly rounded up.
- Auto Quantity Beta uses wick-inclusive completed 1-minute high-low ranges from one shared VM, selected bar count/multiplier, and the left profit target. Sizing uses 0.25-point distance increments and whole ratio-preserving NQ/MNQ contracts. Planning shows estimates; sizing recalculates immediately before reservation/preparation and freezes then. Wrong-contract, insufficient, stale, zero-range, and invalid feeds block automatic sizing. Qty/instrument inputs hide while ratio stays editable. Disable Beta for manual sizing; confirmed pairs retain their captured mode/settings.
- TradingView chart appears below Trading. Its continuous NQ display is separate from the specific-contract NinjaTrader sizing feed and may follow TradingView's data entitlement/delay rules.
- Existing sessions/history, New Non-consistency eligibility ($48,700–$50,300 inclusive), maximum different-fund pairing, reciprocal drawdown presets, and Add All to Queue are retained.

## Airtable error investigation

The live Pair schema was inspected. Combined Result is writable currency and remains uploaded. Priority is an existing single-select with 1/2/3 choices. Need check and Removing are not existing Airtable status choices; their local display states map to supported remote statuses to avoid introducing a new 422 failure. Both Python and Windows curl now retain Airtable's actual error type/message instead of hiding it behind a token-scope hint. Failed uploads remain retryable, and failed pre-entry uploads prevent that pair from entering while other eligible pairs may advance.

**The original reported HTTP 422/442 response was not available in recovered history or the inspected recent records. Its specific cause has not been reproduced or certified fixed.** The diagnostics in this release will expose the actual server response if it recurs; no unrelated record/schema changes were made speculatively.

## Validation scope

Completed locally: 360 Python checks and 10 JavaScript regression scripts. Coordinator and queue tests use simulated agents. Windows and browser checks are pending: public upload was blocked, and the local Chromium download timed out. The release workflow is configured to parse PowerShell, compile transport and SDK-shaped telemetry interfaces, and run browser regressions. A compile check against stubs is not live NinjaTrader certification. Live NinjaTrader compilation, feed arrival and SIM101 end-to-end sizing/recovery must be verified on the installed VMs before using Beta for real-account execution. No live orders were placed during development.

Pushover remains deferred as requested.
