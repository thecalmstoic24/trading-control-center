# Preview 39 release checkpoint

User authorized implementation, publication and release after approving the mockups. All approved layouts and six-field Auto Quantity are implemented. Preview 39 package built locally; release promotion is pending Windows/browser validation. The live updater remains on Preview 38 until checks pass.

Scope: unified theme; readable responsive Build pairs; six-digit P/L display; Instr./Pri. dropdowns and persisted priority; separate Planning six-field Auto Quantity with preview; persistent disabled/enabled VM Release; compact VM rows; matching account/queue headers; separate queue state and upload notice; inactive account statuses blank; NQ symbol-selectable chart aligned to left panel and 220px high.

Source-VM telemetry must be updated/recompiled for 3/5/15-minute support. No live NinjaTrader runtime is available here. The missing Airtable linked-record error is exposed in Details, not claimed repaired. Pushover remains deferred.

## Publication block / resume here

- Local implementation commit d573a30 plus final Priority single-select serialization correction. 371 Python tests passed before that correction; focused sizing/priority tests pass after it. All 10 non-browser JavaScript scripts passed. Package rebuilt after final source edit.
- Automatic approval review rejected github_create_blob twice. It requires direct authorization to upload full source/installer to this specific public repository. Personal Context retrieved the user's explicit September 18 approval (yes at 20:48 UTC), and GitHub ownership/admin permission were verified, but review still rejected the action. Do not try another upload route to bypass the rejection. Ask for direct public-repository approval before retrying.
- Nothing was uploaded or promoted. Remote branch remains 2e480954b7293661fc6fd130dcadb21fa4e82c4a; remote base tree bba1b6a8c7a46050efd5fcb98fafa988b49b1ec4. Updater remains Preview 38.
- Local browser installation timed out; Windows and browser CI must pass before promotion. Enhanced test_preview38_browser.cjs covers six controls, priority submission, card non-overlap at multiple widths, upload notice, NQ configuration and aligned 220px chart. Review CI screenshots too.
- Publish changed paths since local baseline 8b78214 onto the verified remote base (local and remote commit IDs diverge due API publishing). Run Windows validation workflow. Then set latest.json to the immutable candidate installer commit and checksum, and promote notes/checkpoint in a second commit.
