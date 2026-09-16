# V16 Preview 26

Update the Control Center and affected VM agents. Update both for BX-MT account support. Existing Preview 25/24 agents remain compatible with the coordinator; they do not receive the new agent fixes until updated. Close trades, cancel working orders, and stop the old agent before updating a VM.

- Recognize BX-MT Bulenox accounts, preserving the full account ID and mapping it back to the original NinjaTrader connection label. BX-M and BX-MT remain separate accounts; ambiguous matches are rejected.
- Manual NQ/MNQ selection keeps entered contract counts. A ratio/quantity edit switches NQ to MNQ only when the other side would be fractional and multiplying both sides by ten produces whole contracts. No rounding; quantities that remain fractional require another input. Contract month is retained.
- A VM reserved by an errored pair shows red **Errored** and the pair failure message. It retains its reservation until resolved normally.
- Start Queue stays in Planning and shows the number of newly started queue items for five seconds without acknowledgment. This count confirms queue submission, not trade fills.
- Trading defaults to Today in US Central Time. Select a previous completion date or All dates to inspect history. Unfinished pairs remain visible across midnight. Existing newest-completion-first sorting remains.
- Account discovery permits an empty chart Account box while still requiring fresh, idle, Flat state. Trade execution still verifies the actual selected account.
- Accounts export fits the monitor's available area and caches the verified layout. Repeated syncs reuse it; window/display changes invalidate the cache. Existing export identity and menu verification remain.
- Chart calibration locates the actual ATM Edit control through UI Automation and caches it at startup or when Calibrate Chart 1 is clicked. Preparation invokes that control instead of clicking the old fixed coordinate. It does not scan or recalibrate on every trade. Missing, ambiguous, changed, or unsupported controls stop preparation and request calibration. Select an ATM template before calibration.
- Includes Preview 25 contract settings and the existing Airtable curl fallback and permanent updater retries.

Validation: 193 Python tests passed. Production JavaScript checks passed for ratio conversion, VM error display, Central-date filtering, and the counted five-second notification. Installer payloads are checked for exact source inclusion, versions, and checksums. This environment has no PowerShell or browser executable, so the new calibration could not be run against Windows/NinjaTrader and full browser tests were not rerun. No live trades were executed. Verify Chart 1 and ATM Edit calibration on the first updated VM before using it for trades.

Deferred: Suggest Pairs dropdown and separate rule sets, pending the user's suggestion types and matching rules. The existing clock-difference readiness check remains unchanged.
