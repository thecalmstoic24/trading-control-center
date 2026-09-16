# Preview 26.1 — optional Locate Edit button

Update only the affected VM agent. Preview 26 Control Center and other working VM agents can stay installed. The agent title shows 16.0-preview.26.1 while retaining the compatible Preview 26 protocol.

1. With accounts flat and no working orders, close the old agent and run the permanent updater. Choose Named VM – NinjaTrader agent and retain the existing VM name.
2. Open Chart 1 with an ATM template selected. If automatic calibration cannot find Edit, close any open strategy parameters dialog and click **Locate Edit button**, beside **Calibrate Chart 1**.
3. You have five seconds to move your mouse to the center of Edit. Do not click. The countdown remains visible in the agent; the button can cancel it.
4. The agent captures the location, opens strategy parameters, and closes the dialog using Cancel without changing its parameters. It saves the location only after successful verification. Wait for **Edit verified and saved for this VM. Chart 1 calibrated.**
5. Retry preparation from the Control Center after calibration succeeds.

The location is stored only in this Windows user's local agent-data directory. Automatic calibration remains the default on every startup/manual calibration. If automatic detection fails, it may use that VM's saved location when the chart size, DPI and ATM selector geometry still match. Repeated preparations reuse the location; no five-second countdown or calibration scan runs per trade. Moved charts require explicit calibration; changed size, scaling, or selector layout requires locating Edit again. No location is copied to other VMs.

The countdown reserves the agent desktop and rejects competing commands. Capture requires the displayed chart to remain Flat, the pointer to be in the ATM selector's right-hand region, and Chart 1 to own the click location. A missing dialog, invalid location, covered window, or changed layout prevents saving. Trade account, quantity, and position checks remain unchanged.

Validation: 193 Python regression tests passed; both installer wrappers and their embedded files/checksums were verified. A PowerShell regression harness covers geometry, per-VM saved settings, invalid JSON, the countdown, cancellation and busy rejection. PowerShell and Windows/NinjaTrader are unavailable in this build environment, so that harness and the live mouse/dialog behavior were not executed here. The affected VM must confirm the verification message above. No live trades were tested.
