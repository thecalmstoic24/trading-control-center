# Trading Control Center 16.0-preview.8

Update the coordinator only using the usual Install or Update shortcut. Existing preview.7 VM agents are unchanged and continue to support the queue. Wait until current trades are closed before restarting the coordinator for the update.

Planning now uses nearly the full browser width. The accounts table takes three quarters of the desktop layout; a draft-pair panel occupies the right quarter. The pair queue sits below both. Smaller screens stack the panels.

Check an account, then click Add to Left or Add to Right. Each addition fills the first draft missing that side; once both sides are filled, further selections create another draft. You can also check multiple accounts to create several drafts. Assigned accounts are highlighted across the full table row. Repeated accounts are allowed across different drafts and queued pairs.

Each draft has its own matching VM selectors, quantities, instrument, direction, Currency stop loss and profit target. If exactly one registered VM lists the account, it is selected automatically. Otherwise choose the matching VM. Right stop/target amounts mirror the left. Confirm pair moves only that draft to the existing queue. It does not send an entry command. Start Queue controls execution as before.

Drafts and their settings are saved in this browser. A stable draft identity prevents a repeated confirmation after a lost response from creating duplicate queued pairs. Failed confirmations retain the draft for correction or retry.

The accounts table has a Pair status column immediately before id:
- Pairing: orange rounded rectangle, white text.
- Queue: blue rounded rectangle, white text.
- Blank when neither paired nor queued.

Pairing takes priority if the account also has a later queued use. After completion it returns to Queue if another unfinished plan uses it; otherwise the badge clears. Draft-only accounts are highlighted without a Queue badge. Status and highlights change only the Control Center display, not the Airtable Accounts schema or records.

Account sorting, hiding other columns, manual row order, Refresh Planning, and the existing manual Plan a pair dialog remain available. Account id stays visible so the selected account is identifiable.

Validation: 119 Python tests; existing dashboard/Planning tests; browser tests for multiple drafts, persistence, width, highlighting, badge priority and clearing, isolated confirmation, failed retry and no direct trading commands. Agent payloads are unchanged from preview.7. Tests use simulated data and do not place live trades.
