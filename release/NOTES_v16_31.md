# V16 Preview 31 — Planning selection and queue recovery

Update the Control Center for the Planning and display changes. Update VM agents to Preview 31 to enable automatic Sim101 selection on those VMs. Older compatible agents continue to work with an account already selected; they receive no unsupported recovery commands. Existing calibration defaults and saved manual Edit locations are unchanged.

## Planning and cards

- Shift-click account checkboxes or rows to select a range in the displayed order, including sorted views. Select All selects the current Airtable view; Clear Selection clears it. Changing views clears the range anchor.
- Add All to Queue confirms valid Build Pairs drafts using the existing validation and unique draft identities. Invalid or rejected drafts remain editable with errors. The summary reports how many were added. The button does not start trading; individual confirmation remains available.
- Account cards use RealDrawdown directly, remove the account Stop metric, and show scraper-note content only when present, without a label. Editable trade Stop loss inputs remain available. Scraper-note field matching ignores case, spaces and punctuation. Notes saved with queue drafts are limited to 500 characters to preserve the compact request limit.
- The browser tab and Control Center header show Preview 31, updated from the running coordinator's version.

## Recovery

Every five seconds, failed reserved pairs are rechecked for fresh idle Flat state, completed operations, and an eligible release outcome. A pre-entry error with a blank account box can be released after authenticated unbind and fresh readback. Error rows and diagnostic messages remain visible. Temporary recovery request failures do not pause the queue.

A running queue can ask an unreserved Preview 31 agent to select Sim101 only when its account box is blank. The agent rechecks the live chart, idle state, ATM availability, calibration, peer binding and unresolved entry flags before selection, then verifies Sim101 and Flat afterward. It invalidates old preparation, preserves the saved trade account and quantity, and never replaces an existing selection. Repeated requests are throttled and cannot reserve the VM during selection. A manually paused queue remains paused.

This is not an automatic retry of the failed trade. Unresolved entry outcomes, active positions, pending verification and busy operations still block release. The checks use the existing chart and agent execution state; they do not add an independent inventory of manually placed working orders.

The VMs list now identifies a blank account box rather than showing Ready, and waiting pairs name the blocked VM and reason.

## Validation

237 Python regressions passed locally. Windows run 35187960171 passed all PowerShell guard tests, authenticated TLS command transport, production HTTP assets, and browser checks. All 28 packaged files were verified against uploaded source, including the generated agent. Browser checks cover sorted Shift-selection, Select All, card values/notes, bulk partial failures, retry without duplicate drafts, and no queue-start request from bulk confirmation. No live NinjaTrader orders were submitted in validation.
