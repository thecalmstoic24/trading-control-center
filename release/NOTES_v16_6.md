# Trading Control Center 16.0-preview.6

Update the Control Center computer only. VM agent files are unchanged and existing agents remain compatible.

- Trading now has a narrow status panel to the right of both VM cards. It displays pair progress, each VM's observed position, and post-trade account-refresh progress. On smaller screens it moves below the cards.
- The large position number on both cards becomes **Pairing** in orange while the pair is active or unresolved, and **Complete** in green after verified closure. Actual quantity stays in the Quantity fields. Missing observations remain visible in the position detail; Pairing does not imply confirmed execution on both sides.
- Once both sides have been verified closed, the coordinator starts post-trade Airtable export as before, waits for each VM to become idle, and automatically requests account discovery. The next preparation becomes available when this finishes. No automatic Prepare, Buy or Sell commands are sent.
- Account refresh runs in coordinator background workers, including when the browser is closed. Other pairs retain their independent monitoring. An unavailable VM, changed position, or timeout produces an attention message; Refresh accounts remains available for retry when background work ends.
- Planning, its saved row order and column choices, and its read-only Airtable refresh remain available.

Wait until all active trades have finished before updating. Close the running coordinator, run the usual updater, and select the Control Center role. Reopen the dashboard; use Ctrl+F5 if the browser retains old assets. Existing saved accounts and quantities are preserved.

Validation: 99 Python tests; dashboard regression and Planning model tests; browser tests for status labels/colors, sidebar placement, retained quantity, preparation gating, Planning sorting/dragging/persistence/refresh. Packaged agent files are byte-for-byte unchanged. Automated tests use simulated agents and Airtable data; live NinjaTrader desktop behavior must be checked on the user's machines.
