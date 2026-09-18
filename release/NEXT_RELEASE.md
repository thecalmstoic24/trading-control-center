# Remaining release gates for Preview 38

- Public-source publication explicitly approved by the user on September 18, 2026. Publish the candidate to the existing `thecalmstoic24/trading-control-center` repository for validation.
- Upload the candidate source/installer, run Windows/browser CI, resolve failures, and only then advance release/latest.json with the verified installer commit/checksum. The local installer SHA256 is recorded in RELEASE_CANDIDATE_v16_38.json.
- Browser fixtures and the new NinjaTrader C# stubs still require execution. Local Chromium download timed out; PowerShell/NinjaTrader are unavailable here.

- Capture/reproduce the original Airtable HTTP 422/442 if it recurs. Actual error details are now preserved; its original cause is not proven fixed.
- Validate TccTelemetry and TccOrderSafety in the installed NinjaTrader runtime and SIM101. Their live runtime is unavailable in this development environment. Auto Quantity remains off by default.
- Pushover is intentionally deferred by the user.
