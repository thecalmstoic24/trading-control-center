# Trading Control Center — V12 preview

A Windows browser control center with a named VM registry, selectable pairs, and automatic post-close dashboard reset. Runs on the third computer; each trading VM runs its own NinjaTrader agent. Locked to **Sim101, quantity 1, Currency**.

This release supports up to 20 registrations and **one active pair at a time**. Start with the existing two VMs, then test the two additional VMs before expanding. Actual Windows/NinjaTrader execution needs acceptance testing for this release.

## One reusable installer launcher

Download `release/Install_Trading_Control_Center.cmd`. Keep this same file on the third computer and each VM. Each run reads `release/latest.json`, downloads the numbered installer from an immutable GitHub commit, verifies its SHA-256, and opens setup. Future published releases use the same launcher. No GitHub login or manual Python installation is required while this repository remains public.

This is a user-run install/update process, not unattended fleet deployment. It does not update agents while they are trading. Setup refuses to overwrite a running release and retains previous release directories for rollback. Existing VM identity, credentials and saved setup fields are retained.

## Update the third computer first

1. Confirm all involved Sim101 accounts are Flat with no working orders. Close the running coordinator and old agent windows before updating.
2. Run the launcher on the third computer and select **Control center — my third computer**. Click **Install**.
3. Setup installs its own Python runtime and opens the local dashboard at `127.0.0.1:8788`.
4. Read **Control-Computer-Network.txt** on that computer's desktop. Use its **public IPv4 address** for VM setup, not a private address such as `192.168.x.x`.
5. Keep the coordinator running. The desktop shortcut reopens its browser session.

## Update/register named VMs

Run the same launcher on each VM and select **Named VM — NinjaTrader agent**. Fill in:

| Field | What to enter |
| --- | --- |
| VM name | A unique name, such as MFFLocDao, LCDLocDao, FNThu or FNSean |
| VM public IPv4 | This VM's public address |
| Third computer public IPv4 | The address in Control-Computer-Network.txt |
| Other trading VM public IPv4 addresses | Comma-separated public addresses of the other VMs this agent will pair with |

For four VMs, list the other three VM addresses in each agent's peer field. Existing legacy identities `vm-left` and `vm-right` are retained while their suggested display names become **MFFLocDao** and **LCDLocDao**. Names do not fix a VM permanently to the left or right position.

Setup scopes Windows inbound **TCP 8789** to the third computer and the listed peer IPs. Administrator approval is needed for this firewall step. Any attached cloud firewall needs matching source-specific rules. Do not enable broad PowerShell access or use an unrestricted source. When a public IP changes, rerun setup on affected agents to update the allowed sources.

V12 starts the agent automatically. Shared peer secrets and peer addresses are now assigned by the control center when preparing a selected pair. Click **Copy Connection Code**, then **Register VM** in the browser and paste the private code. Import the updated code for each VM, including the original two. A code contains credentials; keep it out of chat, screenshots, GitHub and logs.

The coordinator and both selected agents must use V12. Mixed V11/V12 pairs are blocked. Versioned V11 installers and launchers remain available for rollback.

## Select and operate a pair

1. Wait for the desired VMs to display fresh Sim101 / quantity 1 / Flat observations.
2. Choose their names in the left/right selectors and click **Use this pair**. Changing pairs invalidates previous preparation.
3. Set the instrument, stop loss and profit. Opposite fields mirror automatically.
4. Check both NinjaTrader windows for working orders and tick the dashboard checkbox. **Working orders are not detected automatically.**
5. Click **Prepare & Verify**. The coordinator binds the selected TLS peers, prepares both charts and verifies mirrored readback.
6. Use the named Buy/Sell buttons. Entry is sent once to the selected left VM; both agents use the baseline physical-click arm/commit logic.
7. **Close Both** sends independent close requests, then verifies both positions. An acknowledgement is not a verified fill or close.

After a normal observed open→closed cycle, both fresh, idle Flat observations automatically clear the old dashboard trade state. Your instrument and amounts remain. Check working orders and Prepare again for the next trade. The reset does not place orders or automatically confirm working orders.

If observations were missed, remain stale, or an entry was unresolved across restart, the dashboard stays blocked. Inspect both windows, check working orders and use **Verify Both Flat**. It never treats Unknown as Flat.

## Acceptance sequence

First test MFFLocDao / LCDLocDao: both entry directions, manual Close Both, natural exit/partner close, and automatic dashboard reset. Confirm another preparation and trade cycle works without reloading the browser. Then register FNThu and FNSean and repeat on a newly selected pair. Keep the coordinator and VM desktops interactive; test browser closure separately from stopping the coordinator.

The reported **5–6-second entry delay** remains a baseline measurement, not a promised fix. TLS peer transport changes the communication path; measure the actual delay in this release.

## Implementation and limits

- The original `agent/Paired_VM_Agent_v10_4.ps1` remains verbatim. The build appends integration before `ShowDialog`.
- V12 overrides the legacy TCP listener and peer transport with certificate-pinned TLS. It retains baseline arm/commit/click, eight-second missing-peer grace, and partner-close functions.
- Both coordinator-to-agent and peer connections authenticate over TLS 1.2, checking the certificate before sending credentials. Agents use inbound TCP 8789 with scoped sources; outbound-only fleet connections remain a future change.
- Connection credentials are encrypted with Windows DPAPI for the current user. The local browser API requires a session token and matching Host/Origin.
- Agents continue peer monitoring without the browser. A frozen, locked or disconnected VM cannot be assumed remotely closable. A running Windows UI action can delay processing a close.
- This preview does not include Airtable, live accounts, concurrent trading pairs, working-order detection, or unattended updates.

## Validation and build

Run:

```text
python -m unittest discover -s tests -v
node tests/test_dashboard.cjs
pwsh -NoProfile -File tests/Test-Gateway.ps1
python scripts/build_package.py
```

Automated checks cover mirrored preparation, four-VM routing, old-preparation invalidation, active-pair locks, stale and pending-close reset guards, restart protection, independent closes, uncertain-entry recovery, registration limits, dashboard reset, TLS pinning/authentication and cached-peer expiry. PowerShell syntax and C# compilation are checked in PowerShell 7/Linux. These do not validate Windows PowerShell 5.1 GUI installation or actual NinjaTrader clicks; those require the Windows acceptance sequence.

Coordinator log: `%LOCALAPPDATA%\TradingControlCenter\coordinator-data\activity.log`.
Agent core log: `%TEMP%\Paired_VM_Agent_v10_4.log`.

Rollback only after confirming Flat/no working orders and closing the new processes. Reinstall a retained V11 installer on the third computer and both agents, with their previous peer settings. V12 has no background updater that would replace this rollback.

The runtime is the checksum-pinned official Python 3.13.15 Windows embeddable package. Installers contain application files only, not local identity or network configuration.
