# 16.0-preview.19

- Check the authenticated direct peer connection in both directions before entry. Each agent retries read-only ping up to three times, with a five-second connection allowance for these checks.
- A preflight failure sends no entry and requests no recovery close. Actual entry/arm/commit requests are never automatically retried; uncertain entry still triggers recovery close.
- Distinguish TCP connection timeout from TLS negotiation and include entry protocol stage in errors.
- Keep Activity visible without an active pair, and let queue explanations use the full available width.
- Remove draft rows when both account slots are empty, including restored empty drafts.
- Updated Install / Update command launcher exits automatically after successful setup; errors remain visible. Existing downloaded launcher copies must be replaced to receive this launcher change.

Update the Control Center and both agents of every pair to Preview 19 before trading. Finish active trades before updating. Direct network faults can still prevent entry; this update verifies and reports them rather than guaranteeing connectivity.
