# Trading Control Center 16.0-preview.9

Update the coordinator only with your usual Install or Update shortcut. Wait for current trades to finish before restarting the coordinator. Existing preview.7 VM agents are unchanged.

Build pairs now shows the master account, account ID and latest Airtable CurrentBalance on separate lines, with brighter blue account cards. The numbered draft headings and VM selectors are removed. VM matching is automatic; missing or ambiguous matches show an explanation and cannot be guessed at confirmation.

Each card has Quantity, Profit, then Stop loss. The central swap button exchanges accounts and settings and reverses the ratio. Buy/Sell controls still let you reverse trade direction. Instrument, Confirm pair and Remove share one action row.

The ratio selector defaults to 1:1 and includes 2:1, 1:2, 2:3, 3:2, 3:4, 4:3, 2:5, 5:2, 3:5, 5:3, 4:5 and 5:4. It governs both contract quantities and mirrored currency amounts. Editing either side updates the other; changing ratio preserves the left amounts and quantity and recalculates the right. Currency amounts round to cents.

Instrument choices are NQ SEP26 and MNQ SEP26. Where an NQ ratio needs a fractional contract but can be represented in whole MNQ contracts, both sides convert automatically at 10 MNQ per NQ. The conversion is shown before confirmation. Unrepresentable fractional contracts are rejected, never rounded into a trade. Manual instrument changes also preserve equivalent exposure and reject fractional NQ conversions.

Ratio-specific amounts are validated, sent independently to both agents, checked against their readback and written into the existing Airtable Pair fields. Existing queued plans without a ratio retain their original behavior. New drafts still require Confirm pair and the existing Start Queue workflow.

The existing Planning Airtable accounts table retains Refresh Planning to fetch current Airtable data. Drag column headers or use the arrow controls under Show / hide columns to rearrange columns; their order is saved in this browser. Pair status stays immediately before id. These layout changes do not alter Airtable itself.

Validation: 124 Python tests; all 13 ratio calculations in both directions; swaps; whole-contract MNQ conversion; rejection of incompatible quantities; browser checks for draft persistence, settings order, automatic conversion, confirmation retries, column reorder persistence, queue controls and Trading status. Simulated agents were used; no live trades were placed. Agent source and packaged agent payloads are unchanged.
