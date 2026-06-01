# MobileBandCheckup — Project Policies

<!-- LAST CHANGE — only this block is updated on each change; all policies below are fixed -->
date: 2026-06-01 00:00 UTC
version: mbc3-final-20260531-file-state+restore-guard
change: Backported file-based state persistence and earlier restore-guard placement from routeros_bundle. State now lives in /file mbc3-state.txt; mbc3-save.rsc removed (saves are inline in MobileBandChange3); mbc3-restore reads via [:parse] under an allow-list guard.
<!-- END LAST CHANGE -->

---

## Platform

RouterOS scripting (`.rsc`), MikroTik hardware, `lte1` interface. No local execution — validate by reading. No floating-point; deci-dB values are integers scaled by 10; `formatDeciDb` converts them. RouterOS "arrays" are key→value dicts; iteration uses `:foreach`.

## State persistence

State is stored in `/file mbc3-state.txt` as parse-replay code (markers + `:global`/`:set` lines). Saves are written inline by `MobileBandChange3` at designated exit points using `/file print` + `/file set contents=`. Restore (`mbc3-restore`) reads the file, validates start/end markers and size bounds, runs every line through an allow-list guard that only permits comments and `:global`/`:set` of known state variables with well-formed scalar/quoted values, and then `[:parse]`s and executes the payload. Any new persisted global must be added to both the `mbc3BuildState` helper inside `MobileBandChange3.rsc` and the allow-list in `mbc3-restore.rsc`. Do not write state anywhere other than `mbc3-state.txt`.

## Global variable naming

All globals prefixed `mbc3`. Every script that touches a global must declare it with `:global` before use. Locals use `:local`.

## Write-with-verify

Every state save must: build the payload with start/end markers; remove the existing `mbc3-state.txt`; `/file print file=` to create it, then `/file set contents=` with the payload; read back and verify the end marker is present. Failures log a warning and the next save retries from scratch — never leave a partial file in place.

## Upsert pattern

Never store a find-result ID and pass it to `set`. Always use `set [find name=...]` inline. A stored empty ID applies `set` to all entries.

## Debounce

Signal quality label changes (RSRP, SINR tier) require 2 consecutive matching readings before logging. No quality-sensitive event fires on a single differing sample.

## Probe tracking

Every non-trivial step in the main loop must update `mbc3Probe` and `mbc3ProbeDetail`. Failure paths set `mbc3FailProbe`. New code sections must continue the chain.

## stateChanged discipline

Set `stateChanged true` only for durable comparison-state changes. Volatile counters alone must not trigger a save. The inline `mbc3-state.txt` write only fires at the designated exit points (iface-down, monitor-invalid, init, end-of-script) — never mid-script.

## Log severity

- `warning` — state transition events (primary, CA, NR, quality, iface)
- `info` — heartbeat, install/restore confirmations
- `debug` — raw metrics and internal comparisons, gated by `$debug` / `$debugRaw`
- `error` — unrecoverable save/restore failures

## README policy

Update `README.md` whenever script behaviour, structure, events logged, thresholds, or install procedure changes. The README must always reflect the current state of the code.

## HISTORY policy

Update `HISTORY.md` on every change. The file is **append-only** — never trim, reorder, or delete existing entries. Each entry must include the date and time (`YYYY-MM-DD HH:MM UTC`), the version tag, and a plain-language description of what changed. Newest entries go at the top.

## Git policy

**Before every commit**, in this order:
1. Update `README.md` if behaviour, structure, or install procedure changed.
2. Prepend a new entry to `HISTORY.md` with `YYYY-MM-DD HH:MM UTC`, the version tag, and a description of what changed.
3. Update the `<!-- LAST CHANGE -->` block in `CLAUDE.md` with the same date/time, version, and a one-line summary.
4. Stage all changed files together and commit in a single commit.

**Commit message format:**
```
<short imperative summary under 72 chars>

<bullet list of what changed and why, if not obvious>
```

**Branching:** develop on feature branches; never commit directly to `main`.

**Prohibited git operations:** `--force` push, `--no-verify`, amending published commits, `reset --hard` without explicit instruction.

## Prohibited patterns

- State writes to anywhere other than `/file mbc3-state.txt`
- `/ping` or network calls from the main loop
- `:delay` in the main loop, except the single 200ms settle after `/file print` in the state-save block
- New globals not declared, included in `mbc3BuildState`, and listed in `mbc3-restore`'s allow-list
- Extra inline state-save blocks outside the designated exit points
- Stored find-result IDs passed to `set`
