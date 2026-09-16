# V16 Preview 29

Update the Control Center for deferred VM matching and the results timeout. Update each VM agent to enable its dashboard Sync Airtable button and automatic account refresh when the agent starts. Install with accounts flat, no working orders, and old agents closed. Existing Preview 28 agents remain compatible with the coordinator and retain their calibration settings.

## Confirm first, match before preparation

Confirm Pair saves the selected accounts and settings even without a connected or matched VM. Quantities, ratios, currency amounts, account identities and fund rules remain validated. The contract month is fixed at confirmation. Single Pair supports either side.

After Start Queue, the coordinator finds a unique registered VM for each account and revalidates the mapping before reserving VMs or preparing charts. Missing, ambiguous or same-VM matches remain Waiting with a specific explanation and retry automatically. Other eligible pairs can proceed. No trade entry is sent by confirmation or account matching. Existing confirmed pairs retain their assigned VMs.

## Awaiting Results timeout

After 30 seconds awaiting results, automatically request that every participating agent stop exports for that trade. Once the stop is acknowledged and the VMs are freshly verified idle and Flat, mark the pair Complete with results skipped and release the VMs for queued pairs. Missing P&L remains unavailable.

If a VM is disconnected, busy, still closing, or an export request remains in flight, retain its reservation and retry cleanup. A timeout never resends entry or frees an unverified VM. Manual Skip Results uses the same cleanup.

## VM controls

- Add Sync Airtable beside Refresh on each VM row. It invokes the same agent workflow as Sync Airtable Now, retaining a queued request while the desktop is busy. Show progress in VM Activity and suppress duplicate in-flight clicks.
- Automatically refresh a VM's accounts once per authenticated agent process session. Defer until calibration and current trading operations permit it; retry failed refreshes with a delay. A periodic connection check detects restarts even when a previous idle snapshot was held.
- Older agents show a disabled Sync Airtable button with an update explanation. They do not receive startup refresh commands without the new session capability.

## Validation

230 Python regressions and targeted JavaScript tests passed locally. Windows PowerShell 5.1, TLS command dispatch, saved calibration and Chromium confirmation checks are required before publishing the installer. No live NinjaTrader orders or broker fills were tested.

Suggest Pairs remains pending the user's suggestion types and rules.
