# Trading Control Center — v11 preview

A local Windows browser dashboard for **VM left** (formerly SEAN1) and **VM right** (formerly SEAN2), hosted on Sean's **third computer running Windows 11**.

This is a **Sim101 / quantity 1 / Currency test release**. It is implemented and packaged, but Windows installation and actual NinjaTrader execution still require the two-VM acceptance test below. Do not roll it out to the other VMs yet.

## Start on the third computer

1. Download `release/Setup_Trading_Control_Center_v11.ps1`, or use the accompanying `Download_Trading_Control_Center_v11.cmd` launcher.
2. Run setup and leave **Control center — my third computer** selected. Click **Install**.
3. Setup downloads a private, checksum-verified Python runtime and opens the dashboard. No separate Python installation, Git, or GitHub sign-in is required when the repository is public.
4. Keep the coordinator's PowerShell window open. Reopen the browser with the **Trading Control Center** desktop shortcut.
5. Setup creates **Control-Computer-Network.txt** on the desktop with the third computer's public IPv4 address, when automatic detection succeeds. You will use this when installing the agents.

The dashboard is served only on `127.0.0.1:8788`. The desktop shortcut opens an authenticated local session. Opening GitHub by itself does not start the coordinator.

## Install on the two VMs

First verify **Sim101 is Flat, there are no working orders, and the old agent is closed** on each VM. Keep the working V10.4 files for rollback.

Run the same setup on each VM:

| Machine | Setup role | VM address field | Third computer address field |
| --- | --- | --- | --- |
| Former SEAN1 | VM left | That VM's public IPv4 address | Address in Control-Computer-Network.txt |
| Former SEAN2 | VM right | That VM's public IPv4 address | Same third-computer address |

Setup adds a Windows firewall rule for **TCP 8789 from that one source address**. Windows requests administrator access for this step. It does not broaden the existing peer firewall rules. If the cloud provider has an additional firewall, allow the same destination port from the third computer's IPv4 address with `/32` there as well. Existing explicit Windows block rules can still override this allow rule.

1. Enter the same working peer IPs, port, and shared secret in the new agents. The new names are prefilled.
2. Start both agents; enable PAIR MODE and Test Peer in both directions.
3. Click **Copy Connection Code** on VM left. Paste it into VM left under **Connect VMs** on the dashboard. Repeat for VM right.
4. Treat connection codes as passwords. Do not post them to chat, GitHub, or screenshots. The dashboard saves them encrypted with Windows DPAPI for the current user.

If your home public IP changes, rerun the VM installer with the new source IP. A reinstall retains the existing agent identity and certificate. The initial installer expects IPv4 and an interactive Windows desktop on each VM.

## Operate the pair

1. Confirm both panels show fresh **Sim101 / Qty 1 / Flat** observations.
2. Choose the instrument and currency amounts. Editing either side mirrors the opposite stop loss and profit target.
3. Check NinjaTrader for working orders on both VMs and tick the dashboard confirmation. **This release does not detect working orders automatically.**
4. Click **Prepare & Verify**. Both agents prepare their own chart; the coordinator verifies mirrored readback and matching preparation IDs.
5. Click **Buy left / Sell right** or **Sell left / Buy right**. The coordinator sends one paired-entry command to VM left, which uses the existing V10.4 arm/commit and peer-monitoring functions.
6. Watch position observations. An accepted request is not proof of a fill.
7. Click **Close Both**. Close requests use separate worker capacity and are sent independently to both agents. Success requires fresh Flat observations on both.
8. Following an automatic exit or an unresolved previous entry, check working orders and use **Verify Both Flat** before preparing again.

Closing the browser does not stop the coordinator or agents. Keep the third computer awake, connected, and running the coordinator. The agents' V10.4 peer monitoring continues independently; a disconnected or frozen VM cannot be assumed remotely closable.

## Preserved baseline

- The original V10.4 script is retained verbatim in `agent/Paired_VM_Agent_v10_4.ps1`.
- The build appends browser-control integration before `ShowDialog`; existing V10.4 trading functions are unchanged.
- Paired entry timing, the eight-second peer-status grace period, and agent-side partner-close behavior remain the V10.4 baseline.
- The reported **5–6-second click-to-entry delay** is recorded, not claimed fixed. TLS access adds connection/command overhead; benchmark actual results in the SIM test.
- Displayed RTT and observation age do not measure exchange execution or fill synchronization.

## Security and limitations

- New coordinator-to-agent connections use TLS 1.2, pinned certificates, and a separate random credential per VM. The certificate is checked before sending the credential.
- Local HTTP API actions require a session token and matching Host and Origin. No control API is hosted on GitHub or publicly on the third computer.
- Existing V10.4 peer TCP transport remains unchanged, including its shared-secret authentication and scoped firewall configuration. **The TLS layer protects dashboard access, not the legacy VM-to-VM link.** Complete encrypted outbound fleet transport is a later migration.
- Entry is not retried after an uncertain response; recovery requests Close on both VMs. Gateway request IDs suppress duplicate delivery for ten minutes.
- Entry remains blocked following unresolved execution until positions are freshly verified. Local state changes invalidate dashboard preparation.
- Close cannot interrupt a Windows UI function already executing. It is prioritized over queued work, but the inherited preparation/entry handshake can delay processing. This is not a hard-real-time system.
- Stale readings are Unknown. Neither Unknown nor a sent Close request counts as Flat.
- Agents require an interactive NinjaTrader desktop. A locked/disconnected RDP session may prevent physical clicks; verify the specific VM setup.
- This preview supports one fixed pair. It does not yet provide arbitrary account selection, Airtable, 20-VM enrollment, automatic updates, or outbound agent connections to a central server.

## Validation and Windows acceptance

Automated checks cover mirrored preparation, stale status, account/quantity guards, preparation changes, one-command paired entry, uncertain-entry recovery, independent closes, and restart protection. PowerShell parsing and C# compilation are checked on PowerShell 7/Linux; this is not Windows GUI or PowerShell 5.1 execution validation. TLS integration checks certificate pinning, authentication, and duplicate-request caching. HTTP checks reject missing tokens, wrong hosts, and cross-origin actions.

On Windows, test installation and both directions of the complete pair cycle. Test Close Both, natural exit/partner close, closing the browser during an active pair, temporary coordinator disconnection, and reopening the dashboard. Inspect both NinjaTrader windows manually after each test. Compare entry delay to the V10.4 baseline before expanding deployment.

Coordinator log: `%LOCALAPPDATA%\TradingControlCenter\coordinator-data\activity.log`.
The preserved agent core writes `%TEMP%\Paired_VM_Agent_v10_4.log`.

To roll back, verify both VMs are Flat with no working orders, close the new agents and coordinator, then start the original V10.4 agents with their previous settings. No old release is deleted by this installer.

## Build

Run `python scripts/build_package.py`, then `python -m unittest discover -s tests -v`.
The self-contained setup package includes no credentials or local configuration.

Runtime: [official Python 3.13.15 release](https://www.python.org/downloads/release/python-31315/), Windows embeddable package. Installer SHA-256 values are pinned to those published there; the x64 archive was also verified against downloaded bytes.

Browser rendering automation could not run in the build environment because the browser download was unavailable. The authenticated HTTP workflow was exercised end-to-end against simulated agents; the actual browser display and Windows-specific installation remain part of the user acceptance test.
