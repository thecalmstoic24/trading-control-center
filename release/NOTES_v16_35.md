# Preview 35

Update the Control Center computer. VM agents remain unchanged.

- Compact Build pairs cards keep account IDs, balances, realized P&L, DD, best day, days, direction and any scraper note. Instrument, ratio and pair actions sit in the middle. Redundant suggestion banners and firm labels are removed from cards; suggestion rules are unchanged.
- Confirm pair immediately moves the card into Planning's Pair queue as Saving. A durable coordinator acknowledgement makes it Queued. Failed saves restore the entered card; lost responses reconcile by the same draft key. Local draft confirmation no longer fetches Airtable or waits for the scheduler I/O mutex. Current Airtable and VM membership are still validated before reservation or trade preparation.
- Start Queue immediately moves that batch out of Planning and shows Starting in Trading. New confirmations stay in Planning. Starts use a snapshot of draft keys, prevent duplicate dispatch, and restore failed submissions. The coordinator reads remote pair IDs once per batch and persists dispatch before executing it.
- Centered VMs / Planning / Trading tabs stay visible while scrolling. Contract controls sit beside the title. The old banner is removed; the remaining title includes Preview 35. VM removal has its own selector and action at the right of the top controls.
- Pair tables show shorter IDs, two-line master/account details, compact instrument quantities, green P and red L settings, and plain colored queue/result statuses. Trading completion timestamps show date and Central time on separate lines without a timezone suffix.
- Planning's queue omits result P&L/completion columns and Pause/Retry result sync. Trading keeps Pause/Resume and only shows result retry when saved result uploads are pending.
- The bottom pair-detail panel is removed. Trading Pair status and Activity fill the remaining window with independent scrolling and the existing resizable divider.

This release does not change VM entry/exit automation or suggestion financial calculations. It does not resolve the separately reported Airtable HTTP 422 data/configuration issue.
