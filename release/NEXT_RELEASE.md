# Preview 38 release checkpoint and remaining follow-up

- Public-source publication explicitly approved by the user on September 18, 2026. Preview 38 is published to `thecalmstoic24/trading-control-center`, branch `control-center-third-computer`.
- Source/installer commit: `cd7067963a1605bd6125364d4e608e33acef26ce`. The updater manifest pins this exact installer and its SHA256 recorded in RELEASE_CANDIDATE_v16_38.json.
- Windows release validation and all seven browser suites passed: https://github.com/thecalmstoic24/trading-control-center/actions/runs/35394715715 . 360 Python tests and 10 local JavaScript scripts passed. Do not rebuild or redo implemented Preview 38 work merely because a new conversation starts.
- Update the coordinator and every participating VM agent. Install/compile the read-only NinjaTrader telemetry using the new desktop shortcut; attach the 1-minute candle indicator only on the chosen source VM. Auto Quantity is off by default.

- Capture/reproduce the original Airtable HTTP 422/442 if it recurs. Actual error details are now preserved; its original cause is not proven fixed.
- Validate TccTelemetry and TccOrderSafety in the installed NinjaTrader runtime and SIM101. Their live runtime is unavailable in this development environment. Auto Quantity remains off by default.
- Pushover is intentionally deferred by the user.
