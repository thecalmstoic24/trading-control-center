# 16.0-preview.17

- Recognize Bulenox labels with vertical bars or exclamation marks, including repeated suffixes. Preserve the raw NinjaTrader account label for selection; match clean Airtable IDs for discovery and CSV results.
- Add Refresh Trading to reconcile deleted Airtable Pair records. Active trade monitoring remains until its VMs are released; deleted records are not recreated by result sync.
- Skip errored and unavailable queue rows when looking for the next eligible pair. Failed rows are never automatically retried; their assigned VMs remain reserved until reviewed.
- Open the Trading Agent at the bottom-right of its screen working area with a 12-pixel margin above the taskbar.

Update the Control Center and affected Bulenox agents. Update other agents to receive the new window position. Finish active trades before restarting for an update.
