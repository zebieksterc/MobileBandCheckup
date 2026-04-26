# MobileBandCheckup — Change History

Append-only. Never trim or delete entries. Newest first.

---

## 2026-04-26 19:10 UTC — mbc3-final-20260425-write-min-v1

- Added Git policy section to `CLAUDE.md` covering pre-commit checklist (README, HISTORY, LAST CHANGE block update order), commit message format, branching rule, and prohibited git operations.

## 2026-04-26 19:00 UTC — mbc3-final-20260425-write-min-v1

- Added time (`HH:MM UTC`) to `HISTORY.md` entry headers and to the `CLAUDE.md` LAST CHANGE block for precision.
- Updated HISTORY policy in `CLAUDE.md` to require `YYYY-MM-DD HH:MM UTC` format.
- Backdated existing entries below with approximate times.

## 2026-04-26 18:30 UTC — mbc3-final-20260425-write-min-v1

- Created `CLAUDE.md` project policies file covering platform constraints, state persistence, naming, write-with-verify, upsert pattern, debounce, probe tracking, stateChanged discipline, log severity, README and HISTORY update rules, and prohibited patterns.
- Created `HISTORY.md` (this file) as the append-only project change log.

## 2026-04-26 17:45 UTC — mbc3-final-20260425-write-min-v1

- Wrote comprehensive `README.md` description of the full MobileBandChange3 script suite: all five scripts, logged events table, signal quality thresholds (RSRP, SINR, CQI, RI, MCS), state persistence design, key design decisions (scheduler race guard, 2-run debounce, CA normalisation, primary-change classification, crash probe tracking), installation instructions, and scheduler entries table.

## 2026-04-26 — first commit

- Added `MobileBandChange3.rsc` — main LTE/NR monitor poll loop (runs every 1 minute via scheduler).
- Added `mbc3-save.rsc` — persists selected globals to NVRAM (`mbc3-state` script slot) with write-verify and retry.
- Added `mbc3-restore.rsc` — reloads persisted state on boot; sets `mbc3RestoreDone` in all exit paths.
- Added `mbc3-install.rsc` — bootstrap installer; registers scripts and schedulers from uploaded `.rsc` files.
- Added `mbc3-setup.rsc` — idempotent scheduler-only setup; safe to re-run without `.rsc` files present.
