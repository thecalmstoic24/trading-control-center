# V16 Preview 30.1 — Suggest Pairs loading fix

Update the Control Center only. VM-agent files and trade execution are unchanged.

Preview 30 included the beta suggestion script in its installer and page, but omitted its HTTP route. The browser received a 404 for suggestions.js and reported "PairSuggestions is not defined", preventing suggested cards from appearing. This hotfix adds that missing static route.

Existing Planning data and browser drafts are preserved. After updating, reopen the dashboard and use Planning → Suggest pairs. Review and confirm each suggested card individually.

The regression test now loads every dashboard script through the production HTTP handler. The suggestion browser test also uses that handler for static files instead of serving them directly from disk. The new HTTP test reproduced the missing script before the fix.

Validation: all 231 Python tests passed. Windows run 35185039079 passed, including the production HTTP asset test and suggestion browser workflow. All 28 packaged files match source; only coordinator/server.py and the installer version differ from Preview 30. No live orders were submitted during testing.
