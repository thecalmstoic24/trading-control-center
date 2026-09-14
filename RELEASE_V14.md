# Trading Control Center — V14 preview

V14 adds account selection and independent whole-number quantities (1–1000) to each side of a pair. Sim101 and quantity 1 are defaults. Other accounts require a recent exact ID match between the local NinjaTrader dropdown and Airtable's Accounts table, scoped to the VM's Master Account. Availability in a dropdown does not establish broker permission to execute.

## Install
Use the existing permanent updater on the control computer and every VM that will participate. Close the old software only after all accounts are flat with no working orders. V14 requires V14 agents. Previous versioned releases remain available for rollback. Existing registrations and pair membership are retained.

On each VM, scroll to Browser control. Set **Master Account** to the corresponding Airtable group (for example MFF-LOCDAO), then Save Master Account. Letter case and punctuation are normalized for grouping; ambiguous normalized groups are rejected. The account IDs themselves match exactly, and duplicate Airtable IDs are excluded. Click **Airtable Setup** if this Windows user has no saved login from the original exporter. Token entry is hidden, and credentials remain encrypted with Windows DPAPI. Never place tokens in GitHub or connection codes.

In the browser, create/view a pair and click **Refresh accounts**. Select each account and quantity, check working orders on both selected accounts, and Prepare & Verify. Non-Sim101 lists expire after five minutes; refresh again when requested. NinjaTrader membership is re-read on every preparation. Account and quantity readbacks must match the explicit selections before entry. Changing inputs invalidates preparation. Selected targets survive agent restarts to avoid silently switching an active account to Sim101.

## Post-trade sync
After both positions have been observed open and then verified flat, the coordinator requests one export on each VM. Export uses the existing Accounts-window automation and its saved layout, and maps Net liquidation → CurrentBalance, Realized PnL → Realized PnL, Trailing max drawdown → Trailing max drawdown. Sim101 rows are skipped, as in the original exporter.

The agent suspends its desktop scans during export and blocks new preparation while the worker runs. Upload failures retain the CSV and retry every 30 seconds while idle; successful uploads are deduplicated by trade ID. A pending sync blocks the next preparation to prevent an older snapshot overwriting a newer outcome. Use **Retry Airtable Sync** for an immediate retry. Existing authenticated TLS status serving remains responsive while the worker runs. This preview holds the VM unavailable through the upload as well as the export.

The exporter currently retains the original fixed Accounts-window layout (954,6,964,1148). It checks the window identity, coordinates and fresh CSV before uploading. Different VM display layouts may require a follow-up adjustment. An export or upload worker has a 120-second deadline. Live Windows/NinjaTrader behavior has not been tested in the build environment.

## Validation
Coordinator tests cover separate account/quantity routing, readback mismatch rejection, quantity validation, independent pairs, close recovery and authentication. PowerShell syntax, gateway TLS and bridge isolation checks pass. Dashboard tests cover switching pairs and draft isolation. Initial Windows validation should use Sim101, quantity 1, followed by quantity 2 and close verification before testing another account. No trades or Airtable writes were performed during the build.
