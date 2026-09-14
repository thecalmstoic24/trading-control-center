# Trading Control Center 16.0-preview.7

Planning now includes an explicitly started, sequential pair queue and historical results in the Airtable Pair table.

## Update

With existing trades closed and agents idle, run the usual Install or Update shortcut on the coordinator and each VM you want to use with the queue. Updated agents provide export receipts; older agents still support manual trading but cannot execute queued pairs.

In Planning → Airtable setup, the saved token needs `data.records:read` and `data.records:write` on the Trading base. Tokens remain encrypted on their own computers. No token is included in this release. Use one coordinator for queue execution and Pair ID allocation.

## Use

1. Open Planning → Plan a pair. Choose two VMs, their discovered accounts, quantities, instrument and direction. Sim101 is the default; instrument defaults to NQ SEP26. Currency stop/target fields start at zero and require positive amounts before adding a pair. Right amounts mirror the left.
2. Add as many plans as needed, including repeated VMs/accounts in later pairs. Each gets PAIR-0001, PAIR-0002, etc. IDs grow beyond four digits when necessary; they never wrap.
3. Reorder waiting items with arrows or Remove them. Click Start Queue when ready. It processes the first waiting pair; it does not skip an unavailable pair.
4. The coordinator checks fresh idle Flat status, discovers whether the selected account remains in the agent list, exports starting balances/Realized PnL, then uses the existing Prepare/Verify and paired-entry protocol.
5. After closure, agents export their Accounts window and confirm writes to Airtable. The coordinator matches export receipts to this execution, saves after-balances and PnL changes in Pair, then releases the VMs and processes the next item.

Pause prevents new entries while monitoring and result collection continue. Closing the browser does not pause the coordinator. Restarting the coordinator always pauses the queue and marks interrupted items for review; it never replays entry. Close Pair and Close All also pause the queue. Manual trading stays available on other VMs; VMs/accounts already assigned to a pair wait until released.

## Results and recovery

Pair records include master names, account IDs, current balance snapshots, direction, instrument, quantities, currency amounts, status and timestamps. PnL is after minus before **Realized PnL**, shown green when positive and red when negative. Historical snapshots are not replaced by later account balances. The private execution UUID prevents duplicate records when sync is retried; Pair ID is the short visible label.

Sim101 can be used to test the queue. Its receipt is read from NinjaTrader, but the exporter does not create or update a Sim101 record in the Accounts table.

A lost entry response is never retried. An interrupted queue retains the pair for review. Use View trade and Close Pair as needed. Retry result sync retries record/result synchronization only. Resolve after closing removes an interrupted item only after both VMs are freshly verified Flat. It does not invent missing results.

The calculation assumes no outside trade changes the same account's Realized PnL between snapshots. A UTC date boundary requires review because PnL can reset; this is not a per-fill trade ledger. NinjaTrader desktops must remain interactive for export and trade automation.

## Validation

Automated coordinator/queue tests and browser tests use simulated agents and mocked Airtable responses. PowerShell syntax and receipt serialization are checked. Live NinjaTrader execution and Windows desktop export have not been tested in this workspace. Start with a Sim101 pair on the updated VMs before using the queue for actual accounts.
