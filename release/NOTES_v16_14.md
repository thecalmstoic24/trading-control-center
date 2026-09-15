# Trading Control Center 16.0-preview.14

Coordinator-only update. VM agent payloads are unchanged.

- Planning shows only unstarted plans. Start Queue submits the current batch to Trading; execution remains sequential. Plans added afterward require a new Start Queue. Resume Queue resumes the existing batch only.
- Trading has a pair-status table for submitted/waiting, preparing, pairing, completed, canceled, and error states. The old registered-VM/create-pair selectors are removed; live pair controls remain available.
- Checkboxes and Remove selected in both tables delete only eligible waiting pairs and their Airtable Pair records. Canceled history is retained locally and never uploaded again. Preparing or active trades cannot be removed.
- VM checkboxes and Refresh selected refresh only chosen VMs; individual and Refresh All actions remain available.
- Planning financial columns display USD currency with separators and two decimals; account IDs, day counts, and percentages remain unchanged. Positive/negative Realized PnL colors remain.
- Larger master account names in Build pairs.

Update the Control Center after current trades finish. Existing agents need no update. Automated backend and browser tests cover batch isolation, cancellation persistence, bulk removal, VM selection, layout, and trade controls. No live trades were executed during validation.
