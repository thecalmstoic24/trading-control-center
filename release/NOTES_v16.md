# V16 preview 1

- Compact 400 x 330 logical-pixel installer; native-height name controls and DPI scaling.
- Compact agent with connection status, copying, Master Account mapping, Airtable setup and sync. Legacy trading controls removed from the visible form; core execution and monitoring retained.
- Optional Tailscale auth-key enrollment through official architecture-specific signed MSI. Administrator approval remains required. Key entered locally, DPAPI-protected for elevation, passed to CLI using a restricted temporary file, removed afterward. Enrollment selects no exit node. Existing connected devices need no key.
- Startup checks saved Airtable login once; prompts locally when missing or rejected, then requests a current Accounts export after successful setup. No recurring credential prompt loop. Setup has a ten-minute timeout.
- Manual Accounts sync, automatic sync after a managed pair finishes, and busy-desktop queue preserved. Export never uses the trading chart account as its source.
- Clipboard retries on a timer with separate manual-copy window after repeated failure.
- State refresh watchdog resumes a stopped timer and retries stale reads without inventing Flat status. Worker and scheduled-action guards remain.
- 50 registered VMs, 20 independent pairs, one pair per VM retained. This is logical capacity, not a real-machine performance guarantee.
- Local coordinator browser only. Remote browser access remains pending.

Update the coordinator and VM agents using the existing updater, with accounts flat and no working orders and old programs closed. Identity and saved credentials are retained. Test one VM's startup sync before rolling out to the remaining VMs.

Validation: PowerShell syntax, bridge, clipboard retry/startup handoff, manual sync, private address validation, gateway TLS tests, Python coordinator tests and JavaScript dashboard tests. Actual Windows layout at different DPI settings, first-time Tailscale enrollment, NinjaTrader export and Airtable upload require user-machine validation. No trading commands or Airtable writes were sent to real systems during development.

Tailscale references:
- https://tailscale.com/docs/reference/tailscale-cli/up
- https://tailscale.com/docs/features/access-control/auth-keys
- https://pkgs.tailscale.com/stable/
