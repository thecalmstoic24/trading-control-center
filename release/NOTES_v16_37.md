# Preview 37 — New Non-consistency

Update the Control Center computer only. VM agents are unchanged.

## Included

- Adds a separate **New Non-consistency** strategy to Planning. Existing Test Non-consitency behavior is preserved.
- Eligible accounts use the exact Airtable fields: RealStage = Funded, NoConsistency = 1, and RealCurrentBalance from $48,700 through $50,300 inclusive. CurrentBalance and stage are not substitutes. Missing/ambiguous fields, duplicate IDs, nonpositive RealDrawdown, and already-used accounts are reported as skipped.
- Produces the maximum possible count of different-firm pairs. Chooses the two largest remaining firm pools to avoid stranding pairable accounts, prefers closest rounded drawdowns within those pools, and balances left/right placement with randomized ties. Drawdown similarity is a local preference, not a claim of a globally minimum-cost matching.
- Presets 2 NQ per side, 1:1, Currency. Each side’s loss equals its own RealDrawdown rounded up to the next $10; each side’s profit equals the opposing loss. Rounding can exceed raw drawdown by less than $10, before fees/slippage. The strategy details disclose this.
- Suggestions create editable drafts only. Confirmation and Start Queue remain explicit. The coordinator validates the funded strategy at confirmation and rechecks current Airtable fields when resolving VMs before preparation.
- Session history and Start Trading Day behavior from Preview 36 remain included.

## Still pending

Auto Quantity Beta, its quantity/instrument field hiding, editable-ratio automatic sizing, and the embedded TradingView chart are not included in this release. The recovered conversation did not resolve an accessible live candle-data source. Do not treat an embedded TradingView chart as a candle API. No substitute feed or manual range workflow was silently enabled.

## Validation

- Exhaustive maximum-pair-count checks across 512 three-firm pool shapes.
- Eligibility boundaries, exact-field use, duplicates, exclusions, rounding, randomized sides, and amount validation.
- Queue integration: changed Airtable eligibility blocks preparation and resumes after corrected data.
- Existing queue and evaluation-strategy regression tests.
- Browser and Windows validation run through the repository workflow before the release manifest is advanced.
