# V16 preview 2

Release these VMs now accepts both agents reporting fresh Flat and idle, regardless of saved account/quantity settings or an old coordinator unresolved flag. Each agent re-reads the chart position before clearing its peer binding; pending execution, closing, verification and desktop-worker operations still block release. Both unbind replies and fresh post-unbind observations are required. Unbind failures retain reservations.

Removed the working-orders checkbox and the corresponding manual-confirmation API requirement. Prepare & Verify runs directly; selected-account membership, quantity validity and entry readback checks remain. Close/Flat recovery no longer compares the next-order quantity or saved account selection.

This uses the current Chart Trader position observation. It does not scan all accounts/instruments in the NinjaTrader Positions tab and does not automatically detect or cancel working orders.

Update coordinator and agents through the permanent updater after closing positions/orders and stopping the old programs. Validate release on a flat pair before further execution. 83 Python tests, dashboard regression checks, PowerShell syntax and actual bridge-dispatch tests passed; real Windows/NinjaTrader testing remains required.
