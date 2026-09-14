# Trading Control Center 16.0-preview.11

Update the Control Center computer only with the usual Install or Update shortcut after current trades finish. Existing VM agents remain unchanged.

The tabs are now VMs, Planning, Trading, with VMs open first. The VMs tab lists registrations in larger text, one row per VM, with connection, position, availability, expandable account IDs, Register VM, individual Refresh and Refresh All. All tabs use the same coordinator observations and account lists. Refresh retrieves fresh state and starts account discovery on the selected idle VM. It does not release pairs or pretend a disconnected or active VM is available; errors remain visible. Active/prepared pair operations are protected from account-discovery interference.

Planning now has a draggable divider between Airtable accounts and Build pairs. Drag left to enlarge the builder; drag right to enlarge the table. Keyboard left/right also adjusts a focused divider. Save View confirms storage of column order, visible columns, sorting, row order and panel widths in this browser. Layout autosaving is retained. Small screens stack the panels.

Column and account-row arrow buttons are removed from the Airtable accounts table. Drag column titles horizontally to reorder; drag rows in Manual Order. Column sorting and visibility controls remain. Pair status stays adjacent to account id. No Airtable schema/data changes are made by layout actions.

Individual account boxes can move between draft pairs and sides. Dropping onto an occupied box swaps the accounts so neither is lost. Draft settings stay with their slots; the central swap still exchanges both accounts and settings. The small x removes only one account; the bottom Remove removes the full draft. Empty boxes have a neutral, unhighlighted background.

Same-fund master prefixes disable confirmation and replace its label with Same fund. Server validation also rejects same-fund real accounts when adding a plan. Quantity validation immediately disables confirmation when quantities are fractional, outside supported bounds or incompatible with the ratio. The existing conversion to whole MNQ quantities remains available; fractional contracts cannot execute.

Validation: 130 Python tests, ratio unit checks, browser checks for account drag/swap/removal, same-fund blocking, fractional blocking, VM list and refresh, shared pair account state, divider resizing/persistence, Save View, column drag, queue and Trading status. The actual packaged coordinator is checked with isolated Python startup. Tests use simulated agents; no live trades placed. Agent payloads are byte-for-byte unchanged.
