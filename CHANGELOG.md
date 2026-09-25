# Changelog

## 1.0.1

- Fixed pet deaths marking their owners dead and granting false resurrection grace.
- Excluded time before an observed resurrection or reconnection from subsequent eligibility totals.
- Saved measurement limits with each session; setting changes apply to the next session or reset.
- Marked unknown limits in older records instead of displaying current defaults as historical settings.
- Included the current pack consistently in live report and export totals.
- Finalized the observed part of an open pack on logout/reload before saving.
- Added per-pack duration and player statistics, with a 200-pack detail limit per session.
- Added CSV export with raw seconds, limits and warning fields.
- Added clickable column sorting and saved window position and sort preferences.
- Corrected idle interval timestamps when the last combat evidence predates the current tick.
- Added Lua 5.1 regression checks for combat, persistence, exports and UI callbacks.

## 1.0.0

- First public release: automatic trash activity tracking, boss exclusion, history,
  configurable inactivity limits, player interval details and text export.
