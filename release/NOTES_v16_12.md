# Trading Control Center 16.0-preview.12

Coordinator-only Planning update. Run the usual Install or Update shortcut on the Control Center computer after current trades finish. VM agents are unchanged.

Resize Airtable account columns by dragging the right edge of a column header. Column title dragging still reorders columns; edge dragging changes width without sorting or reordering. Saved widths follow their column through reordering, hiding and refresh. Save View retains widths together with existing layout preferences in the same browser. A focused resize handle also supports keyboard left/right adjustment.

Empty account slots now have a + Add selected account button. Select exactly one account in the Airtable table, then click the button or the empty box to fill that specific slot. No extra draft is created and no occupied slot is replaced. No selection or multiple selections show a helpful message. Same-fund, quantity and VM-matching checks remain in effect. The original Add to Left/Right controls still support batch planning.

Validation: browser checks for column resize/save/reload, column reorder, row order, visibility, exact-slot addition through both the button and box, no-selection feedback, draft persistence and existing restrictions. Packaged isolated startup checked; agent payloads unchanged. No live trades placed.
