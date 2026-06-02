# MobileBandCheckup — Change History

Append-only. Never trim or delete entries. Newest first.

---

## 2026-06-02 00:00 UTC — mbc3-final-20260601-bundle-aligned

- Added `MANUAL.html` — single-file dark-theme reference manual modelled on the upstream `routeros_bundle` MANUAL.html. Covers overview/architecture, install / upgrade / uninstall flow, RouterOS gotchas, every script (MobileBandChange3, mbc3-restore-state, mbc3-install, mbc3-setup, mbc3-cleanup), globals reference (state/runtime/tunable/guard), tunables with defaults and ranges, schedulers and required policies, state-file format and save sequence, operator commands, and an on-router smoke-test procedure including the equivalence diff against the bundle.
- README links to the manual from the header.

## 2026-06-01 12:00 UTC — mbc3-final-20260601-bundle-aligned

> ✅ **Tested transitively via routeros_bundle b2.22.** After this change, `MobileBandChange3.rsc` and `mbc3-restore-state.rsc` are byte-for-byte equivalent on executable lines (comments and headers excepted) to the routeros_bundle b2.22 sources confirmed working at the 2026-05-31 18:41 reboot on RouterOS 7.21.4 / MikroTik Chateau 5G R17 AX / Quectel RG650E-EU. The installer registers the same script policies and scheduler policies the bundle's `scheduler_templates.rsc` uses on the live router.

- **Renamed `mbc3-restore.rsc` → `mbc3-restore-state.rsc`** (and the registered script object name to match). The inline restore-guard inside `MobileBandChange3.rsc` now calls `/system script run mbc3-restore-state`. `:local tag` updated to `[mbc3-restore-state]`.
- **Renamed the periodic scheduler `mbc3-main` → `mbc3-run`** with on-event `:delay 50s; /system script run MobileBandChange3` (50-second startup stagger, mirroring the bundle's tested template).
- **Added explicit `policy=` to every script and scheduler registration** in `mbc3-install.rsc` and `mbc3-setup.rsc`. `MobileBandChange3` and `mbc3-run`: `ftp,read,write,policy,test`. `mbc3-restore-state` and its scheduler: `ftp,read,write,policy`. `mbc3-setup`: `read,write,policy`. `mbc3-cleanup`: `ftp,read,write,policy`. Without these RouterOS refuses with "not enough permissions to run script".
- **Legacy migration on install/setup:** the old `mbc3-restore` script and `mbc3-main` scheduler are removed if present, so upgraders end up with a single, clean set of names.
- **`mbc3-cleanup.rsc` is now dry-run by default** (matching the bundle's `bundle-reset-state` safety pattern). Set `mbc3CleanupCommit=true` before running to apply. The flag auto-clears at the start of a committed run. The cleanup now also removes the legacy `mbc3-restore` script and `mbc3-main` scheduler.
- **Added a `RouterOS script and scheduler policies` section to `CLAUDE.md`** documenting the required policy strings for every registered object.
- **Updated `README.md`** to mark the runtime scripts as confirmed working (via the bundle's hardware test), document the explicit policies, the new scheduler names, and the dry-run cleanup procedure.

## 2026-06-01 00:00 UTC — mbc3-final-20260531-file-state+restore-guard

> **Not yet tested on hardware.** This revision was ported by reading the routeros_bundle source; it has not been imported into a live MikroTik or exercised against a real LTE modem. Verify on a router before relying on it in production.

- Added `mbc3-cleanup.rsc` / `mbc3-cleanup` registered script. Symmetric to `mbc3-install.rsc`: removes both schedulers, every script the installer registered, the state file `mbc3-state.txt`, every `mbc3*` global from `/system script environment`, and legacy `mbc3-save` script + `mbc3-state` script slot from the pre-file-state architecture. Idempotent; tolerates missing targets.
- Backported the `file-state+restore-guard` revision of `MobileBandChange3` from `routeros_bundle` (bundle `routeros_bundle_b2.21_A2.0_S2.0_K2.21_D2.10_20260425_2245_wd5g-tdh`, helpers/mbc3-restore-state and scripts/MobileBandChange3, version tag `mbc3_r1|…|20260531|file-state+restore-guard|cs=a9a58787`).
- **State persistence moved from `/system script source mbc3-state` to `/file mbc3-state.txt`.** State saves are now written inline by `MobileBandChange3` at each designated exit point via `/file print` + `/file set contents=`, with an `escapeStr` helper that escapes `\`, `"`, and `$` so any value survives a quoted `:set` round-trip.
- **Deleted `mbc3-save.rsc`.** Saves are inline; there is no longer a separate save script.
- **Rewrote `mbc3-restore.rsc`** to read `mbc3-state.txt`, validate start/end markers and size bounds, run every line through an allow-list guard (only `#` comments or `:global`/`:set` of a known persisted variable with a well-formed scalar/quoted value), and then `[:parse]` and execute the payload. Rejects embedded `\r`, unescaped `$`, unknown variable names, or any other suspicious line — cold-starts instead.
- **Moved the startup restore-guard earlier in `MobileBandChange3`** — it now runs before any persisted-state read (runtime options, Last\*/Pending\* globals), eliminating the window in which `mbc3-main` could read defaults if `mbc3-restore` had not yet completed.
- **Updated `mbc3-install.rsc`** to drop the `mbc3-save` script registration and the `mbc3-state` script-slot creation (no longer needed).
- **Updated `:find` style throughout** to `[:typeof [:find …]] = "num"` (away from `= nil`) — explicit type test that is reliable across RouterOS versions.
- **Collapsed the heartbeat log** to a single info line with `run-count`, `primary`, `rsrp`, `sinr`, and `nr-rsrp`.
- **Updated `CLAUDE.md`** state-persistence, write-with-verify, stateChanged, and prohibited-patterns sections to reflect the new file-based design.

## 2026-04-26 19:30 UTC — mbc3-final-20260425-write-min-v1

- Added `LICENSE` file (MIT, copyright 2026 zebieksterc).
- Added MIT license badge to `README.md` header and a License section at the bottom.

## 2026-04-26 19:25 UTC — mbc3-final-20260425-write-min-v1

- Changed `mbc3QualityMonitor` default from `true` to `false`. Quality tracking is now opt-in; NVRAM writes from signal quality fluctuations are suppressed unless explicitly enabled.
- Updated `README.md` runtime globals comment to reflect the new default.

## 2026-04-26 19:20 UTC — mbc3-final-20260425-write-min-v1

- Added `mbc3QualityMonitor` boolean global (default `true`). When set `false`, the entire RSRP/SINR quality label comparison block is skipped — no `rsrp-quality-change` or `sinr-quality-change` events are logged and no NVRAM save is triggered by quality fluctuations.
- Persisted `mbc3QualityMonitor` in `mbc3-save.rsc` so the setting survives reboots.
- Updated `README.md` optional runtime globals section with the new variable.

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
