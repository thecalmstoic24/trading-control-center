# 16.0-preview.21

- Compact read-only selected pair cards show full accounts, direction, instrument, quantities, ratio, profit, stop and results. Select a pair by clicking its table row.
- Remove the large editable trade workspace and separate status panel from the displayed workflow. Show applicable row/card actions: Retry, Cancel, Close Pair, Retry sync, or Duplicate.
- Duplicate completed pairs with a new Pair ID and execution key, unchanged trading configuration, no copied results, and a separate Airtable record. New duplicates appear below the source and wait for explicit Start.
- Use Trade closed / Syncing results until the queue confirms completion.
- Click account rows to toggle selection; text selection, controls and dragging do not toggle it.
- Remove periodic Airtable fetches and sync-status-triggered fetches. Initial/view setup, manual refresh and completed queued pairs refresh Planning; browser polling reads only coordinator cache.

Control Center update only; Preview 20 agents remain compatible. Finish active trades before restarting the coordinator. Broader CSV export and instant planning-save performance changes remain pending.
