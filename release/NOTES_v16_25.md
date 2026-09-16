# Preview 25

Update the Control Center for contract-month settings. Working Preview 24.2 VM agents remain compatible and do not need updating. VMs still affected by Airtable PowerShell timeouts should install this release as a Named VM agent. The agent retains protocol version 24 for compatibility.

- Contract month is saved on the coordinator and defaults to DEC26. Change it once at rollover, for example MAR27.
- Select NQ or MNQ in Planning. Confirmation resolves them to the configured month, such as NQ DEC26 and MNQ DEC26.
- Confirmed, queued, active and historical pairs retain their assigned contract. Editing a confirmed draft preserves its contract until you choose NQ or MNQ again. Older browser drafts also retain explicit symbols.
- NQ/MNQ quantity and ratio conversion works across contract months.
- Includes the working Preview 24.2 Windows PowerShell-compatible Airtable curl fallback and the installer download retries/GitHub API fallback.
- Setup displays the full release version. No calendar-based automatic rollover.
