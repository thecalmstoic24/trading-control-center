# Preview 36

Update the Control Center computer only. VM agents are unchanged.

- Trading now has a compact progress gauge between Pair status and Date. Complete is green, Pairing is orange with moving stripes, Waiting is steady blue, and errors appear in red only when present. Pairing status text pulses softly every 1.5 seconds. Reduced-motion preferences disable animation. Counts describe the selected day/session, independently of the status filter. Canceled pairs are excluded; awaiting results remain a labeled unfinished portion.
- The Status header has a multi-select filter. Headers stay fixed while rows scroll. Long trade lists initially render 250 rows with Load more trades; recent activity displays up to 100 entries.
- Start Trading Day creates a durable, timestamped session available in the Date selector. Newly dispatched pairs join it. Earlier trades, including active/waiting pairs, retain their previous session and remain accessible through All dates. This button does not start/pause trading, reset account balances, or alter InitialBalance. Repeated requests with the same identity do not create duplicate sessions.
- Test Non-consitency suggestions preserve all eligibility and risk checks. Target-reaching trades aim for remaining required profit plus $25, rounded up to the supported $10 increment. If the cushion cannot fit under the caps, the suggestion remains below the target or is skipped when below the $100 minimum. Old suggestion drafts must be regenerated.
- Suggestions balance use across eligible firms relative to the available account pool and prefer less-used accounts in the active session. Feasible one-trade completions retain priority. No firm is hard-coded as preferred.
- Airtable accounts, view selection, and Add Airtable View share a compact row. The bulk action reads Add All to Queue. Navigation is slightly larger with neutral filled buttons; enabled controls have hover and pressed feedback.
- Performance: dashboard snapshots avoid duplicating the entire VM fleet for each legacy pair. Unchanged queue/Planning responses use conditional HTTP reads; queue snapshots omit diagnostic/draft payloads. Unchanged rows and headers retain their DOM nodes, hidden queue/VM tabs are not redrawn, and unchanged Planning data does not trigger draft rewrites. VM safety observation, order entry/exit and scheduler timing are unchanged.

The separately reported Airtable HTTP 422 upload issue is not changed by this release.
