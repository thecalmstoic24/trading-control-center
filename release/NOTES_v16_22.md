# Preview 22

- Duplicate is available for completed and canceled pairs, including canceled history. A duplicate gets a new pair ID and execution key and waits for Start.
- With Preview 22 on both participating agents, Start Queue reuses discovered account lists and the latest confirmed account snapshot. It does not refresh accounts, export starting CSVs, or sync intermediate queue states to Airtable.
- Preparation and the final pre-entry checks still verify the actual chart, settings, Flat position and direct peer connection. No automatic chart calibration is added.
- After verified closure, each agent saves an immutable trade-specific CSV and capture receipt. Once both receipts are available and agents are idle, the coordinator releases their VMs. Another queued pair can immediately use them.
- Account uploads run from a durable, ordered local CSV outbox independently of trading. Pair-result uploads run on a separate coordinator thread. Upload failure does not block the scheduler or released VMs. Pending uploads retry; saved CSVs survive restarts.
- After 30 seconds, missing capture results remain pending. VMs are not released without both saved captures. Other eligible pairs continue.
- P&L uses the latest cached same-day receipt as baseline. It is unavailable where no usable baseline exists. Manual trades since that snapshot can affect the difference; no starting export is performed.
- Queue stages run at a shorter interval for the new flow. This is not a measured latency guarantee.

Update the Control Center first, then all participating VM agents to Preview 22 with trades closed. Older agents retain the legacy export-and-sync flow; both sides must support background exports for the faster flow.

Validation: 172 Python tests, browser queue interactions including canceled Duplicate, and PowerShell syntax parsing. No live Windows/NinjaTrader order execution was performed.
