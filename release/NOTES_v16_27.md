# V16 Preview 27

Update the Control Center first, then both VM agents in each pair that will use the new timing method. Keep all accounts flat, cancel working orders, and close the old agent before updating. The permanent updater installs this release once publication verification is complete.

## Coordinated entry timing

- Measure timing only after the pinned TLS connection is established. Connection setup still contributes to the scheduling lead time, but no longer distorts the clock-difference estimate.
- Use three authenticated samples to estimate the relationship between the VMs' elapsed-time counters. Stable Windows clock differences larger than 500 ms no longer automatically block entry.
- Schedule each entry against that VM's elapsed-time counter. A subsequent Windows clock adjustment does not move the committed entry countdown.
- Recheck timing once automatically before arming either side if the first measurement fails. This never resends an entry or commit.
- Retain bounds on timing uncertainty, network delay, sample stability and freshness. Retain the existing 250 ms late-entry rejection, account/quantity checks and recovery-close behavior. Both selected agents must support Preview 27 timing; mixed old/new agents stop before arming.
- These changes do not guarantee simultaneous broker fills or remove the need for healthy VM/network performance.

## Retry readiness errors

- Show **Retry** on pair errors confirmed to have stopped before entry was armed, including the previous release's exact 500 ms clock-readiness rejection.
- New agents return an authenticated, preparation-specific and binding-specific rejection receipt. Lost responses, mismatched receipts and unknown entry outcomes do not enable this retry.
- Retry refreshes both selected accounts and requires fresh, idle, Flat state, matching accounts/quantities, no observed entry, and no running operation. Settings and Pair ID are retained; preparation and timing checks run again.
- Record prior attempt details. Retry affects the selected pair only. No automatic retry follows a requested entry with an uncertain outcome.

## Trading layout

- Pair Status occupies 75% of the default width; Activity sits beside it on the right at 25%.
- Drag the divider to resize. The selection persists on this browser. The divider also supports arrow keys, Home and End. Narrow screens stack the panels.
- Retains Preview 26.1's optional, VM-local **Locate Edit button** fallback and all previous account/quantity fixes.

## Validation

199 Python regression tests and targeted JavaScript tests passed locally. Windows PowerShell 5.1 syntax and timing tests, TLS transport tests, saved-Edit regression tests and JavaScript checks passed in Windows release validation run 35120852546. Installer payloads match the checked source exactly; published installer readback is verified before the updater is advanced. No live NinjaTrader orders or broker fills are tested.

Suggest Pairs remains pending the user's suggestion types and matching rules.
