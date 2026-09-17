# Preview 32 — VM and draft removal

- Registered VMs now have a Remove VM button beside Refresh and Sync Airtable. Confirmation removes the saved Control Center connection only; it does not uninstall the agent or delete Airtable accounts or historical pairs.
- Removal is blocked for pair-owned VMs, unfinished queued pairs, running refresh/default-account/sync requests, or known positions and unfinished agent operations. Disconnected, unassigned registrations can be removed after confirmation; removal never closes a remote position.
- Registration removal is serialized with queue dispatch and saved before the live registry changes. Polling stops for the removed registration; it can be registered again with its connection code.
- Build pairs now has Remove All Pairs. Confirmation clears only unconfirmed browser drafts; queued/active pairs and history stay intact. Disabled while confirmations are being sent.
- The Control Center title shows Preview 32. Existing Preview 31 agents remain compatible and do not need an update for these controls. Agent code and trade execution behavior are unchanged.

Validation: 242 Python tests, VM action JavaScript tests, and Windows release/browser validation. No live NinjaTrader orders were placed during testing.

The proposed suggestion minimum/target-overrun changes remain pending clarification of the requested realized-P&L limit. No new suggestion formula or Airtable sync matching changes are included.
