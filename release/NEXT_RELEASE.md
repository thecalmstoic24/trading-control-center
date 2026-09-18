# Preview 39 release checkpoint

Preview 39 implemented, published and validated. All approved layout and six-field sizing changes are included. Do not repeat completed implementation.

- Validated source/installer commit: 86a99aeba635b9522ae5744a96c87b388e46311b.
- Windows validation and all seven browser suites passed: https://github.com/thecalmstoic24/trading-control-center/actions/runs/35406791680 . 371 Python tests and 10 local JavaScript scripts passed. Final browser screenshots reviewed.
- latest.json pins the immutable validated installer and its SHA256; release candidate metadata records the checksum.
- User explicitly approved uploading full source and installer to the public repository thecalmstoic24/trading-control-center and release after validation. Publication review cleared after that direct confirmation.
- Update the coordinator and participating VM agents. Update/recompile source-VM TccTelemetry for 3/5/15-minute support; existing 1-minute feeds remain compatible. Auto Quantity is off by default. Installed NinjaTrader/SIM101 runtime checks remain a user-machine acceptance step, not a CI claim.

## Delivered

Shared UI theme, readable responsive Build pairs, six-digit P/L display, Instr./Pri. dropdowns with priority saved to queue/Airtable, separate Planning six-field Auto Quantity with preview, persistent disabled/enabled VM Release action, compact single-line VM rows, matching account/queue headers, separate queue state and upload notice, blank inactive pair statuses, and selectable NQ chart aligned with the left trading panel at 220px high.

## Remaining operational follow-up

Airtable ROW_DOES_NOT_EXIST is presented clearly in Details; missing linked records are not recreated automatically. Verify the affected account record before retrying upload. No live NinjaTrader runtime is available here. Pushover remains deferred.
