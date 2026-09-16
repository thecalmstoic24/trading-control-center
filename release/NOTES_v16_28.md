# V16 Preview 28

Update the Control Center for the confirmation, queue and dashboard changes. Update VM agents for the restored calibration preset and bottom-left window placement. Close trades, cancel working orders and close old agents before installing. Preview 27 and 28 agents share the same elapsed-time entry protocol; older agents still need updating on both sides to use it.

## Confirm Pair

Confirmation sends only the editable trade settings, account references and displayed numeric metrics. Full Airtable records and unrelated fields no longer travel in the request. This fixes oversized confirmations without changing quantity, ratio, instrument, or the server's 16 KB request limit. Existing browser drafts benefit when confirmed after reloading the updated dashboard.

## Calibration and agent window

- Restore Preview 24's preset ATM Edit location as the normal path. Startup calibration no longer requires discovering a unique UI Automation Edit control.
- Keep Locate Edit button optional. An explicitly saved, verified location overrides the preset only on that VM. A changed saved layout requires updating that override; it is not silently ignored.
- Retain chart identity, foreground/occlusion checks, account and quantity readback, parameters dialog verification, and the two-attempt limit.
- Place the agent at the bottom-left of its monitor's usable desktop, retaining the 12-pixel bottom spacing.

## Failed pairs and queue recovery

- Keep a failed row marked Error while automatically releasing its reservation when its VMs are freshly verified idle and Flat and entry is known not to have been sent, or closure was recorded.
- Wait for outstanding operations and synchronization. Recheck after authenticated unbind. Offline, busy, scheduled, pending, closing, open or uncertain-entry states remain reserved.
- For closed errors with pending results, stop that trade's export retries before release; unavailable results remain flagged as skipped, not fabricated.
- Waiting pairs can then reuse those VMs without manually canceling the errored row. A manual Retry retains the failed pair's settings and queues behind any new owner; it never takes over another pair's VMs.

## Dashboard

- Use the available browser width on all tabs with modest edge padding, replacing the fixed-width center column.
- Add VM Activity beside the VM list: 80% list / 20% activity by default. Drag the divider or use arrow keys, Home and End. Save widths in this browser; stack panels on narrow screens.
- Show VM names and Central Time timestamps for connection, calibration, account, sync, preparation, queue and error changes. Keep the latest 200 events for the running coordinator without repeating unchanged status on every refresh.
- Preserve Trading's resizable 75% Pair Status / 25% Activity layout and improve divider hit areas.

## Validation

206 Python tests and targeted JavaScript regressions passed. Windows PowerShell calibration/timing, TLS, saved-location and browser layout/confirmation checks passed in Windows release validation run 35124218901. All 27 packaged files matched the tested source; published installer readback is verified before the permanent updater is advanced. No live NinjaTrader orders or broker fills were tested.

Suggest Pairs remains pending the user's suggestion types and matching rules.
