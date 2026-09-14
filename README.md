# Trading Control Center — V13 preview, stage 1

V13 adds **independent simultaneous SIM pairs** to the working local control center. Up to 20 registered VMs can form up to 10 disjoint pairs. Each pair has its own settings, preparation, jobs, activity log, unresolved-entry lock and post-close reset.

**Update the third computer and all four agents to V13 before testing. Setup retains saved names, identities, certificates and network settings.** Hosted browser access and enrollment codes are the following stage; this release still runs locally with the existing TLS network setup.

## Install the coordinator update

1. Verify every involved Sim101 account is Flat with no working orders. Close the coordinator on the third computer.
2. Run your existing `Install_Trading_Control_Center.cmd`. It reads the current release manifest and verifies the numbered installer's checksum.
3. Select **Control center — my third computer**, then Install. Run the same launcher on each VM after closing its old agent, leaving its saved role and settings in place. No connection-code reimport is needed when the identity and address remain unchanged.
4. Open the dashboard through the desktop shortcut. Your four registered VMs are retained. The last V12 pair is migrated with its settings and any unresolved-entry lock.

V13's agent setup automatically detects the current computer's public IPv4 address. A **Detect this computer public IP** button allows retry. Detection failure preserves saved values and allows manual entry. Existing controller and peer addresses are retained on reinstall. This first stage still requires scoped inbound TCP 8789 and manual controller/peer configuration for a newly added VM.

The same reusable launcher remains the update entry point. Previous release directories and numbered installers are retained. No unattended updates run during a trade.

## Use multiple pairs

1. In the registry, choose two available VMs from the separate left/right dropdowns and click **Create pair**.
2. Use **View pair** to display a pair's settings and activity. Viewing another pair does not change either pair's members or stop monitoring.
3. For each pair, check both NinjaTrader windows for working orders, confirm the checkbox, set mirrored currency amounts, and **Prepare & Verify**.
4. Run MFFLocDao / LCDLocDao and FNThu / FNSean independently. Entry buttons explicitly name their destination VMs.
5. **Close Pair** acts only on the displayed pair. **Close All Pairs** dispatches independent close requests to all registered pairs. Watch each pair's separate Flat verification; a request acknowledgement is not proof of closing.
6. After an observed trade ends and both positions are freshly verified Flat and idle, that pair resets automatically and retains its settings. Prepare again before the next entry.
7. To use a VM with a different partner, close and verify its old pair, then click **Release these VMs**. Released VMs become available in the dropdowns. An active or unresolved pair cannot release a VM.

A VM belongs to one pair at a time. An idle pair also reserves its VMs until released, preventing a second browser tab or concurrent request from reassigning them accidentally. Every trading API request specifies an immutable pair ID; there is no shared global 'current pair'.

Working orders are still checked manually. Sim101, quantity 1 and Currency remain locked. Stale status is Unknown, never Flat. If a trade's observations were missed or the coordinator restarted with an unresolved entry, check the positions and working orders, then use **Verify Both Flat** for that pair.

## Four-VM acceptance test

Keep both pairs visible in the overview and verify the following on Windows:

- Start pair A; while A is open, view and prepare pair B, then start B.
- Close A and verify B remains open and monitored. Prepare A again while B remains open.
- Test the reverse entry direction and natural exit/partner close. Only the completed pair should reset.
- Test **Close All Pairs** and independently verify all four positions Flat.
- Switch views and check that the stop-loss/profit values stay with the correct pair.
- Confirm an active VM cannot be assigned to another pair. After closing and releasing, create a different pairing.
- Close and reopen the browser while both pairs run; agents and coordinator should continue monitoring.

Do not increase to the other VMs until this release passes the four-VM test. The reported 5–6-second entry delay remains a separate measurement; this release does not promise a latency improvement.

## Persistence, transport and rollback

- Coordinator settings and DPAPI-encrypted connection credentials remain under `%LOCALAPPDATA%\TradingControlCenter\coordinator-data`.
- `pairs-v13.json` stores pair membership. Each pair has its own directory below `pairs`, including `activity.log` and any `entry-unresolved.json` marker.
- Unresolved locks survive coordinator restarts independently for all pairs. Releasing a pair invalidates its agents' readiness before freeing the reservation.
- There is one background poller per VM. Pair preparation and closing use separate worker pools, so a slow pair does not consume another pair's execution workers.
- V13 requires V13 agents: coordinator closes act locally on each explicitly targeted VM, release clears the old peer binding, and stale peer-close requests cannot cancel another pair’s queued commands. Transport remains certificate-pinned TLS on 8789. V13 retains the original V10.4 physical-click functions, monitoring grace and recovery behavior.
- The dashboard still listens only on `127.0.0.1:8788`, requires its session token, and checks Host/Origin. No public control endpoint has been opened.
- Closing the browser does not stop the running coordinator or agent monitoring. A frozen or inaccessible Windows desktop cannot be assumed remotely closable.

For rollback, first verify **all pairs** Flat with no working orders and close V13. Reinstall the retained V12 coordinator. Restore V12 agents on the two VMs being used with V12. V12 cannot manage V13's multiple-pair state; do not roll back during an active or unresolved trade.

## Next stage: hosted control and enrollment

The next deployment needs a continuously reachable coordinator host and an HTTPS domain. Its scope is outbound agent enrollment/connections, authenticated remote browser sessions with MFA, and a transport migration that preserves independent agent monitoring during browser disconnections. No server was provisioned, remote authentication deployed, or inbound agent rules removed in this local release. GitHub distributes software; it does not host the running coordinator.

## Build and verification

```text
python -m unittest discover -s tests -v
node tests/test_dashboard.cjs
pwsh -NoProfile -File tests/Test-Gateway.ps1
pwsh -NoProfile -File tests/Test-Bridge.ps1
python scripts/build_package.py
```

Tests exercise actual coordinator and HTTP handlers with simulated VM agents: simultaneous entries, isolation of close/reset/settings, Close All with one blocked VM, duplicate reservations, release/re-pair, explicit pair-ID routing, restart locks, V12 configuration migration and incompatible-agent rejection. Dashboard tests exercise the rendering and action-routing code. PowerShell parsing and C# compilation run on PowerShell 7/Linux; they do not validate Windows GUI installation or NinjaTrader execution.

Installers contain application code only, without VM credentials or local network settings. Setup downloads a checksum-pinned private Python runtime on the control computer; no manual Python installation or GitHub login is needed while this repository is public.
