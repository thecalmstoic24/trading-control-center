# Trading Control Center 16.0-preview.13

Coordinator-only update. VM agent payloads are unchanged.

- Bright light theme across VMs, Planning, Trading, and setup dialogs.
- Planning accounts Realized PnL text: red negative, green positive, normal zero.
- Remove queued or waiting pairs from both the queue and the Airtable Pair table. Account records are untouched.
- Removal is saved before contacting Airtable; failed or interrupted deletions remain excluded from trading and can be retried. Preparing, trading, and completed pairs cannot be deleted by this action.
- Existing saved views, column widths, draft pairs, and trading behavior are retained.

Install on the Control Center computer after current trades finish.
