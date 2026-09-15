# 16.0-preview.20

- Calibrate Chart 1 once at Trading Agent startup, or manually through Calibrate Chart 1. Calibration requires the agent idle and the displayed chart Flat.
- Cache the chart window handle and bounds. Preparation and position reads no longer rediscover the chart; preparation and button arming no longer automatically restore/resize it. Clicks still verify live controls and focus.
- Report Calibration required when the cached chart is unavailable or moved.
- Retry preparation retains the same queued Pair ID and settings, releases its idle old reservation, then repeats verification. It is unavailable once an entry has been requested, or while an operation is running.

Update the Control Center and participating agents. Keep Chart 1 open and Flat at startup; if calibration cannot complete, use the manual button. Finish trades before updating. Windows desktop calibration requires live VM verification; automated tests cover generated code and queue retry boundaries.

Planning caching and broader CSV performance work remain pending; this release focuses on chart calibration and preparation retry.
