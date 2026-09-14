# Three-computer deployment

Status: implemented as v11 preview on this branch; not installed on the user's computers. The third computer is confirmed to run Windows 11. See the repository README for installation, validation status, and initial transport limitations.

## Machine assignments

| Stable ID | Display name | Previous name | Software |
| --- | --- | --- | --- |
| control-center | Control center | Third computer used for ChatGPT and GitHub | Local coordinator and browser dashboard |
| vm-left | VM left | SEAN1 | NinjaTrader and local agent |
| vm-right | VM right | SEAN2 | NinjaTrader and local agent |

These are application labels, not Windows host renames. Do not change existing VM IP addresses or peer settings merely to rename the panels. The control-center installer targets Windows 11.

## Initial configuration contract

The following describes defaults the next implementation must consume. It is not an executable configuration for the existing V10.4 agent.

```json
{
  "schemaVersion": 1,
  "coordinator": {
    "machineId": "control-center",
    "displayName": "Control center",
    "placement": "third-computer",
    "dashboardBindHost": "127.0.0.1",
    "dashboardPort": 8788
  },
  "agents": [
    { "id": "vm-left", "displayName": "VM left", "previousName": "SEAN1" },
    { "id": "vm-right", "displayName": "VM right", "previousName": "SEAN2" }
  ],
  "pair": {
    "leftAgentId": "vm-left",
    "rightAgentId": "vm-right",
    "account": "Sim101",
    "quantity": 1,
    "parameterType": "Currency",
    "mirrorStopLossAndProfit": true
  },
  "baseline": {
    "agentVersion": "10.4",
    "reportedEntryDelaySeconds": [5, 6]
  }
}
```

## Dashboard behavior

- Open locally on the third computer; the browser talks to the coordinator on that computer.
- Display VM left and VM right side by side, using stable IDs for command routing.
- Provide Prepare & Verify, Buy left / Sell right, Sell left / Buy right, and Close Both.
- Right stop loss equals left profit; right profit equals left stop loss.
- Keep Sim101, quantity 1, and Currency locked during the initial test.
- Show disconnected or stale position readings as Unknown.
- Invalidate preparation when configuration changes.
- Confirm actions from agent observations, not merely command acknowledgements.

## Connectivity and lifetime

- The coordinator runs independently of the browser. Closing a tab must not stop monitoring.
- The third computer must remain on, awake, connected, and running the coordinator while it is coordinating a pair.
- Agents remain installed on each VM and retain local trade monitoring and protective behavior.
- The existing V10.4 peer connection remains the working baseline until the new integration passes simulation tests.
- GitHub distributes versioned software; it is not the coordinator or a command relay.
- Opening GitHub in a browser does not install the coordinator or grant remote control of the third computer.
- For the centralized transport, use authenticated encrypted connections. Do not expose an unauthenticated dashboard or transmit shared secrets over public plaintext connections.
- Agent enrollment, certificates or private-network transport, and reachability must be configured locally during installation. Do not commit secrets, tokens, or personal network configuration to this public repository.
- Do not broaden existing firewall rules as part of this naming change.
- A coordinator outage must block new entries and appear as a connection error. A frozen or disconnected VM cannot be assumed remotely closable.

## Packaging targets

1. Control-center installer: run once on the third computer; set up its required runtime automatically, start the coordinator, and open the browser.
2. Agent installer: run on each trading VM; enroll it with a stable ID and editable display name.
3. Versioned GitHub downloads: retain the working V10.4 release for rollback; apply agent updates only while flat with no working orders.

## Acceptance checks for the next release

1. Verify third-computer operating system and installer compatibility.
2. Enroll VM left and VM right and verify identity and fresh heartbeats.
3. Verify accounts, quantity, mirrored parameters, flat positions, and no working orders.
4. Test both paired entry directions and Close Both using Sim101 only.
5. Confirm a temporary monitoring delay does not reproduce the V10.3 premature-close regression.
6. Close the browser during a simulated pair and confirm monitoring continues.
7. Test coordinator disconnection and show actual outcomes independently for each VM.
8. Record click-to-entry delay separately from the delay between the two VM executions. The reported V10.4 baseline is 5–6 seconds; no improvement is claimed by this configuration change.
