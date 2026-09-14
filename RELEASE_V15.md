# Trading Control Center — V15 preview

V15 removes manual public/controller/peer-IP entry. The existing third computer remains the coordinator. Every computer joins the same Tailscale private network; setup detects its private address automatically. Paired agents keep the established direct, certificate-pinned TLS protocol over that private network. This is a private-network migration, not the earlier proposed central relay or a hosted public website. Remote web hosting remains deferred.

## Update all participating computers

1. Verify all accounts are flat with no working orders, then close the old agents and coordinator.
2. Run the existing permanent updater on the third computer and each VM. Keep each computer's existing role.
3. Click **SET UP PRIVATE NETWORK (TAILSCALE)** if needed. Setup downloads Tailscale's official Windows installer and checks its Authenticode publisher signature before launching it. Finish the official client sign-in using the SAME Tailscale network on every computer. No shared auth keys are placed in the installer or repository. Choose the appropriate personal/business plan in Tailscale; this application does not purchase one.
4. Click **CHECK CONNECTION**, then **INSTALL**. There is no peer-IP field. Subsequent updates reuse the installed Tailscale connection.
5. On each VM, **Copy Connection Code** and import it in the third computer's **Register VM** dialog once to migrate its address. Existing idle pairs can retain their membership if the identity, name, port, certificate and token are unchanged and the new endpoint confirms fresh, idle Flat status. Active or unresolved pairs cannot migrate.
6. **Refresh accounts**, select an account and quantity, then **Prepare & Verify**. First test Sim101 quantity 1, paired entry, Close Pair, and post-trade sync.

The Tailscale Windows client must remain running and logged in. Devices must be able to communicate on TCP 8789 under your tailnet access policy. Setup enables only that control port on the detected private network interface/address. The V15 agent binds only to that private address and retains certificate pinning and per-agent credentials. It removes the old public control rule owned by this application. Adding another VM requires no IP-list updates on existing VMs.

## Preserved account and export behavior

The dropdown shows the intersection of NinjaTrader account IDs and Airtable rows for this VM's Master Account, plus Sim101. It does NOT expose all unmatched accounts. Match failures and account-discovery errors remain visible. Account and quantity selections are verified before entry; quantities default to 1 and Sim101 remains the default account.

V14 patch 2's accounts/post_trade gateway fixes are included. Post-trade exports and Airtable uploads retain the existing DPAPI login, pending CSV retry, and exclusive desktop use. The original fixed Accounts-window export layout remains; verify it on each VM. Existing sync-pending files and account targets are preserved.

## Validation and limitations

Automated tests cover pair isolation, per-account quantities, close handling, migration of idle registrations, rejection of active/stale migrations, private address detection, login requirements, PowerShell parsing, authenticated TLS command dispatch and UI draft behavior. Build-time checks cannot validate actual Windows firewall/UAC, Tailscale sign-in, or NinjaTrader clicks. The installer is a preview requiring those on-machine tests. No trades or Airtable writes occurred during development.

Tailscale documentation: https://tailscale.com/docs/install/windows
Tailscale plans: https://tailscale.com/pricing
Personal plan is not intended for commercial use: https://tailscale.com/docs/account/manage-plans/downgrade-plan

V14 releases and their installers remain available by immutable commit for rollback. Reinstalling V14 reconfigures its previous public connection mode; do not mix V14 and V15 agents in a pair.
