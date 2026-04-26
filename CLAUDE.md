# MobileBandCheckup — Project Policies

<!-- LAST CHANGE — only this block is updated on each change; all policies below are fixed -->
date: 2026-04-26 19:25 UTC
version: mbc3-final-20260425-write-min-v1
change: Changed mbc3QualityMonitor default to false; quality tracking opt-in rather than opt-out.
<!-- END LAST CHANGE -->

---

## Platform

RouterOS scripting (`.rsc`), MikroTik hardware, `lte1` interface. No local execution — validate by reading. No floating-point; deci-dB values are integers scaled by 10; `formatDeciDb` converts them. RouterOS "arrays" are key→value dicts; iteration uses `:foreach`.

## State persistence

Never write state to `/file`. All persistence goes to `/system script source` (the `mbc3-state` slot). Any new persisted global must be added to both `mbc3-save.rsc` and `mbc3-restore.rsc`.

## Global variable naming

All globals prefixed `mbc3`. Every script that touches a global must declare it with `:global` before use. Locals use `:local`.

## Write-with-verify

Every write to a script slot must: validate content (start marker + end marker + size bounds) before writing; read back and verify length and both markers after writing; retry up to 3 times; log `SAFE` / `MODERATE` / `DISRUPTIVE`-tagged messages on failure.

## Upsert pattern

Never store a find-result ID and pass it to `set`. Always use `set [find name=...]` inline. A stored empty ID applies `set` to all entries.

## Debounce

Signal quality label changes (RSRP, SINR tier) require 2 consecutive matching readings before logging. No quality-sensitive event fires on a single differing sample.

## Probe tracking

Every non-trivial step in the main loop must update `mbc3Probe` and `mbc3ProbeDetail`. Failure paths set `mbc3FailProbe`. New code sections must continue the chain.

## stateChanged discipline

Set `stateChanged true` only for durable comparison-state changes. Volatile counters alone must not trigger a save. Call `mbc3-save` only at the designated exit points — never mid-script.

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

- `/file` writes for state
- `/ping` or network calls from the main loop
- `:delay` in the main loop
- New globals not declared, saved, and restored
- Extra `mbc3-save` calls outside designated exit points
- Stored find-result IDs passed to `set`
