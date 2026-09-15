# Preview 23

Reconstructed from published Preview 22 and the retained release requirements.

- Confirmed plans stay local to the coordinator, remain editable through **Edit**, and receive official Pair IDs when **Start Queue** is clicked. Build Pairs drafts remain saved in the browser. Existing queued pairs keep their identities.
- **Single Pair** accepts one account on either side. It reserves, prepares, enters and monitors only the selected VM. Right-side direction and currency settings are retained. A second VM is not contacted. Requires the Preview 23 agent.
- **Skip Results** stops the matching export worker, waits for its exit, removes the matching desktop retry, and persists the skipped trade identity so a delayed export cannot restart it. VMs are released only after the existing release checks. Captured CSV uploads remain in the independent background outbox. Requires Preview 23 on all participating agents.
- Canceling a reviewed error no longer pauses the queue. Eligible waiting trades can advance after the reservation is released; an explicitly paused queue stays paused.
- Pair Status includes **Completed Time**, captured in UTC and displayed in America/Chicago with CST/CDT. Terminal cancellations also receive a timestamp. Old records without a saved timestamp stay blank.
- Pair Status columns can be resized by dragging header edges. Widths persist in that browser.
- Waiting/Queued statuses are magenta; Awaiting Results is blue. VM availability is orange for Paired, blue for Available, and red for errors/attention.
- Account cards show balance, trading days, largest profit day, and drawdown calculated as **CurrentBalance - stop + Trailing max drawdown**. Missing inputs display an unavailable value rather than an invented zero.

## Update

With trades closed, run the existing Install Trading Control Center launcher on the Control Center and every participating VM. It verifies the pinned installer checksum before starting setup. Existing configuration is retained by the installer.

## Validation

178 Python tests passed, including Single Pair on either side with no second-VM commands, error cancellation handoff, Skip Results rejection/reservation retention, and deferred draft IDs. Browser checks passed for queue behavior, Single Pair creation/editing, card drawdown, status colors, Central Time and column-width persistence. Dashboard routing tests passed. PowerShell agent tests cover export termination, durable skip, rejection while a position is open, Single Pair direction and rejection of repeated entry. TLS gateway authentication/pinning and new command routing passed. Packaged PowerShell syntax and embedded payload checksums were verified.

No live Windows/NinjaTrader orders were used in validation. The underlying cause of previously reported peer network timeouts is not established by these tests.
