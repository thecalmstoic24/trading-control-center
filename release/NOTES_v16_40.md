# Preview 40 checkpoint

Preview 40 implemented, published and validated. Do not repeat completed work.

## Included
- Approved compact candlestick header, Trading Control Center title, consistent theme.
- Auto Quantity immediately hides Qty/Instrument, preserves ratio and priority; compact five controls, fixed 3x median exclusion for new UI settings; Save/Preview beside title.
- Blank/1/2/3 priority, no Ratio label, four-digit P/L maximum 9999, narrower amount controls and readable account cards.
- Planning saved view removal (local configuration only, keeps at least one); organized column choices; green Buy/up and red Sell/down.
- TradingView removed; Trading Select column removed; status colors including amber Paused; black same-size post-result balance under each P/L.
- Confirmed missing-record result uploads stop retrying, retain local receipts/error details, and do not block other uploads. Other failures retain retry behavior.
- Idle unreserved VM blank account recovery selects first available Chart 1 account with Flat/readback verification. Existing selections and unresolved trade guards retained.
- Telemetry installer keeps its error message visible.

## Validation / release gates
- 374 Python checks and 11 local JavaScript scripts passed.
- Windows agent guards, parser/telemetry build and all seven browser suites passed. Screenshots reviewed.
- Validation: https://github.com/thecalmstoic24/trading-control-center/actions/runs/35455009709
- Validated source and installer: f16eb712343287d834c3738229f67042686e7cac
- Installer SHA256: ab4638bee897167d83fe97c131baa8a4b7c9414c5becd8c09ff5189f48e843cf
- latest.json pins this immutable validated installer.
- Update coordinator and VM agents. No telemetry indicator change; existing Preview 39 telemetry does not need recompiling.
- No real NinjaTrader runtime here: UI automation requires user-machine acceptance; CI covers guards and syntax.

User authorized implementation and public source/installer publication to thecalmstoic24/trading-control-center, then release after validation on 2026-09-19.
