# V15 development status

This branch is a development draft, not the V15 fleet release. The permanent updater remains on V14.

Implemented and checked: all locally discovered NinjaTrader account names remain available even when Airtable is unconfigured, unavailable, or has no matching record. Sim101 remains the default. Airtable matched / unmatched / unknown labels are separate from selection. Prepare rechecks the actual NinjaTrader dropdown, account and quantity. Unmatched accounts do not trigger an Airtable upload. Coordinator, dashboard and PowerShell dispatch tests cover this behavior. Actual NinjaTrader UI discovery still requires Windows testing.

Remaining: replace direct VM-to-VM TLS connections with authenticated outbound connections to a continuously reachable coordinator; enrollment codes, reconnects, routed paired commands and status; HTTPS browser access and sign-in. The host and address have not been selected or provisioned. This draft installer still uses V14's IP/firewall configuration and must not be advertised as removing it.

Deployment contract to implement once the host is identified:
- One stable HTTPS endpoint reachable from all agents and remote browsers.
- One-time, expiring enrollment codes, exchanged for a per-agent credential.
- Outbound agent transport; no inbound command listener or peer-IP list required on trading VMs.
- Agent identity and pair-binding validation for every routed command, with unique command IDs and deadlines.
- No automatic resend of uncertain entries after disconnect; reconcile observations before enabling another entry.
- Local position monitoring retained; bounded disconnect recovery must be tested alongside partial fills, restart and lost acknowledgements.
- Browser authentication, session expiration, CSRF protections and encrypted transport.
- Persistent registry, bindings, operation history and recovery state. Preserve existing registrations through a versioned migration.
- Test entry/close timing through relay before updating the permanent installer manifest.

The user must identify an accessible server or authorize provisioning one before live deployment can be completed. No server was provisioned and no financial activity was performed.
