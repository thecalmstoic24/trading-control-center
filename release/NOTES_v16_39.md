# Preview 39 — unified workspace layout

- Shared pale-blue table headers, typography, buttons, cards, dialogs and status notices across the program.
- Build pairs preserves all account information while resizing. Narrow quantity/P/L columns fit six digits, and cards reflow at small panel widths. Instr. and Pri. share one row. Priority persists to the queue and Airtable. Auto mode keeps ratio and priority visible.
- Auto Quantity moved from Build pairs to the Planning account header. Six editable controls: source VM, reference contract, timeframe (1/3/5/15 minutes), lookback, distance multiplier and median exclusion (0 disables filtering). Preview sizing uses the first draft's left profit and ratio without saving settings. Existing saved configurations keep their sizing behavior.
- Source NinjaTrader chart must match reference and timeframe. Update/recompile TccTelemetry on the source VM for 3/5/15-minute support. Existing 1-minute telemetry remains compatible. Sizing uses completed candles, validates freshness and contract, preserves the ratio, and locks before Preparing.
- VM rows stay on one line. Release VMs always remains visible, disabled when there is no reservation; existing flat/order verification remains enforced.
- Account pair status stays completely empty when inactive. Queue Running/Paused badge is separate from a result-upload notice; full errors are behind Details. Retry upload does not resume trading.
- TradingView defaults to NQ continuous, enables symbol selection, follows the left trading panel's width, and has a 220px height (half the previous 440px).

## Updating
Run Update_Trading_Control_Center_API.cmd on the coordinator. Update participating agents to Preview 39 for consistent version reporting; source-VM telemetry update is required for the newly supported timeframes. Close NinjaTrader before running Install NinjaTrader Telemetry, reopen and compile, then configure the source chart to match the six-field panel. Auto Quantity is off by default. Validate in SIM101 before real-account use; the installed NinjaTrader runtime is not available in CI.

The Airtable ROW_DOES_NOT_EXIST condition is now presented clearly; this release does not recreate missing Airtable records automatically.
