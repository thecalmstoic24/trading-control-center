# Preview 24.1: Airtable connection hotfix

Update the affected VM agents only. Existing Preview 24 Control Center is compatible and does not need updating. The agent keeps the Preview 24 protocol identifier for compatibility.

- Airtable requests fall back to Windows curl when PowerShell fails without an HTTP response. HTTP authorization failures remain failures.
- A successful fallback is remembered on that VM for subsequent setup, account discovery and sync requests.
- Tokens are passed to curl through standard input, not process arguments or temporary files. HTTPS certificate verification stays enabled.
- The installer displays its complete version. The corrected permanent updater adds a second GitHub route and bounded retries.
- Contract-month settings are still pending for Preview 25.
