# Trading Control Center V16 — 16.0-preview.3

- New pairs default stop loss and profit target to zero on both sides. Enter positive amounts before preparing. Existing saved pair settings are retained.
- Dedicated agent PowerShell console hides automatically; closing the agent exits its PowerShell host after existing cleanup.
- Setup closes after successful installation and launch. Errors keep setup visible. An older permanent CMD updater may still show its existing final press-any-key prompt.
- Idle paired VMs retain their last known display and matched accounts. Values are marked cached, never treated as fresh execution evidence. Background status polling pauses after an idle Flat snapshot; discovery continues polling for its completion window. Prepared and active pairs continue monitoring.
- Prepare & Verify remains clickable during stale idle status and requests fresh observations; entry still requires verified readiness on both agents.
- Account matches remain valid through the VM local calendar day. Refresh accounts explicitly after intraday changes. Prepare rechecks the actual NinjaTrader dropdown.
- Release supports fresh idle Flat / Flat or fresh idle Flat / Unknown. Unknown / Unknown and known open positions remain blocked. Release removes assignments; it does not close or verify the Unknown VM, and cannot clear that VM's remote binding while unavailable. Reusing it still requires fresh idle status and preparation.

Update the coordinator and VM agents with the existing updater when no trades are active. Refresh the browser after updating. Automated tests cover coordinator, dashboard, and PowerShell parsing/logic; Windows GUI lifecycle requires a check on one VM before rolling out to the rest.
