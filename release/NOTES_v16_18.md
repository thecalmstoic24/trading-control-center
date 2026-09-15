# 16.0-preview.18

- Refresh both queued agents’ NinjaTrader/Airtable account lists before starting exports and preparation.
- Require a matching completion ID from both successful refreshes, fresh idle Flat status, and the selected accounts in the newly returned lists. Cached lists cannot authorize preparation.
- Run eligible queued pairs concurrently on independent VMs/accounts. Occupied pairs stay waiting while later eligible pairs proceed; Pause prevents new starts while open pairs continue monitoring.
- Keep status cells compact with only the status label; show explanations in Activity.
- Time out without entry if refresh does not complete; retain the error for review while other eligible pairs can continue.

Update the Control Center and both agents used by queued pairs to Preview 18. Older agents remain compatible for existing manual workflows but cannot start this verified queue flow. Finish trades before updating. Existing Error rows are not automatically retried: review and resolve them, then add corrected pairs.

Early-close behavior is unchanged pending live diagnostic evidence.
