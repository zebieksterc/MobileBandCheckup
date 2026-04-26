# MobileBandCheckup — Change History

Append-only. Never trim or delete entries. Newest first.

---

## 2026-04-26 — mbc3-final-20260425-write-min-v1

- Created `CLAUDE.md` project policies file covering platform constraints, state persistence, naming, write-with-verify, upsert pattern, debounce, probe tracking, stateChanged discipline, log severity, README and HISTORY update rules, and prohibited patterns.
- Created `HISTORY.md` (this file) as the append-only project change log.
- Wrote comprehensive `README.md` description of the full MobileBandChange3 script suite: all five scripts, logged events table, signal quality thresholds (RSRP, SINR, CQI, RI, MCS), state persistence design, key design decisions (scheduler race guard, 2-run debounce, CA normalisation, primary-change classification, crash probe tracking), installation instructions, and scheduler entries table.

## 2026-04-26 — first commit

- Added `MobileBandChange3.rsc` — main LTE/NR monitor poll loop (runs every 1 minute via scheduler).
- Added `mbc3-save.rsc` — persists selected globals to NVRAM (`mbc3-state` script slot) with write-verify and retry.
- Added `mbc3-restore.rsc` — reloads persisted state on boot; sets `mbc3RestoreDone` in all exit paths.
- Added `mbc3-install.rsc` — bootstrap installer; registers scripts and schedulers from uploaded `.rsc` files.
- Added `mbc3-setup.rsc` — idempotent scheduler-only setup; safe to re-run without `.rsc` files present.
