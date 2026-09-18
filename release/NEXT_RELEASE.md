# Remaining work after Preview 37

Auto Quantity Beta remains pending a usable live candle-data source. Keep it separate and off by default. The requested calculation uses completed 1-minute candle high-low ranges including wicks, configurable bar count and distance multiplier, the left-side dollar profit target, and NQ/MNQ quantities preserving the pair ratio. When enabled, hide quantity/instrument fields on pair cards and retain the ratio. Freeze sizing before preparation and reject unavailable/stale data. The user also requested a TradingView chart at the bottom of Trading; an embedded chart alone does not provide candle data to the coordinator.

Preview 37 implements New Non-consistency. Session history was already released in Preview 36. The separate reported Airtable HTTP 422 issue remains outside these changes.
