# Trading Control Center 16.0-preview.5

Control Center update only. Update the third computer; existing VM agents remain compatible and do not need updating. No trading-agent source or behavior changes are included.

## Planning

- Trading and Planning tabs within the existing dashboard.
- Read-only account grid from Airtable view `viw6K3jRjU5PJpWM4` in the Trading base. Pagination includes every record in that view. The API supplies the view's matching records; column visibility and order are configured separately in Planning.
- Refresh Planning requests current Airtable data without sending any trading-agent commands.
- Independent background refresh every 30 seconds. Observed trade-completion and sync-status changes also request refresh. Existing agents do not expose a unique event for every manual sync, so changes may appear on the following background refresh after the export finishes.
- Sort any column ascending or descending; number and date field types use corresponding comparisons when available.
- Hide or restore columns locally; drag rows or use up/down buttons in Manual Order. Return to Manual Order after sorting to restore the saved sequence.
- Row order and hidden columns persist in this browser. Refresh preserves them and appends newly visible records. Records no longer in the Airtable view disappear from the displayed grid. These controls never write to Airtable.
- Failed refresh retains the last successful in-memory snapshot and displays an error and last-update time. Data is loaded again after restarting the coordinator.

## Setup

1. When trades are finished, close the existing Control Center and run its usual Install / Update shortcut on the third computer. Select the Control Center role. Leave VM agents on their current version.
2. Open the dashboard and select Planning. If old assets remain visible, press Ctrl+F5 once.
3. In Planning → Airtable setup, enter a personal access token with `data.records:read` and access to base `appzvICrv7LLlZdxm`. Optional `schema.bases:read` includes empty columns and field types. A compatible existing token saved by NT-Airtable on this same Windows user/computer is reused automatically.
4. Save & refresh. The token is saved with Windows DPAPI encryption on the coordinator. Never put a token into GitHub or the installer. ChatGPT's Airtable connection does not automatically configure this Windows application.

Fresh pair settings default to `NQ SEP26`. Existing pair settings are preserved. Stop loss and profit target continue to start at zero.

## Verification

93 Python tests, existing dashboard regression tests, Planning model tests, and browser interaction tests. Package checks verify unchanged trading-agent bytes. Airtable requests are GET-only and mocked in tests; live Windows installation, credentials and private Airtable data require verification on the coordinator.
