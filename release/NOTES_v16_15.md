# Trading Control Center 16.0-preview.15

Coordinator-only update; VM agents and trading execution are unchanged.

- Add Airtable views in Planning using a full https://airtable.com/app.../tbl.../viw... link, or a viw ID for the Trading Accounts table. Optional display names make views easy to identify.
- Switch saved views using the Airtable view selector. The view list and selected view persist on this Control Center.
- Each base/table/view has an independent browser layout: hidden columns, column order and widths, sorting, manual row order, and panel split. Save View applies to the selected view only. The original Accounts layout is preserved.
- Account selections clear when switching. Separate data caches prevent delayed responses from showing the wrong view's accounts.
- The selected view refreshes automatically every 30 seconds, on selection, and through Refresh Planning. Existing trade/sync refresh triggers remain in place. Additional bases require access through the saved Planning token.
- Airtable account browsing remains read-only; no view, field, or account record is changed in Airtable.

Validated with 140 backend tests, the Planning browser suite, and a multi-view browser test covering add/switch, saved-layout isolation across tables, reload, refresh, invalid links, and stale response handling. The packaged coordinator starts in isolated Python; VM agent files match the prior release byte-for-byte.

Install on the Control Center computer after current trades finish. No VM agent updates required.
