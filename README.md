# MobileBandCheckup

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

RouterOS scripting suite for MikroTik routers that monitors LTE/NR (5G NSA) band changes and signal quality on a modem interface, logging every meaningful transition to the system log and persisting comparison state across reboots.

📖 **Full reference:** [`MANUAL.html`](MANUAL.html) — every script, every global, every tunable with its default and range, the schedulers and required policies, the state-file format, the operator commands, and the on-router smoke-test procedure.

> ✅ **Confirmed working on hardware (transitively).** The runtime scripts `MobileBandChange3.rsc` and `mbc3-restore-state.rsc` perform the same operations in the same order as the upstream `routeros_bundle` b2.22 versions that were verified working after the **2026-05-31 18:41** reboot on RouterOS 7.21.4 / MikroTik Chateau 5G R17 AX / Quectel RG650E-EU modem. MobileBandCheckup's `mbc3-restore-state.rsc` is byte-for-byte equivalent on executable lines to the bundle's `helpers/mbc3-restore-state.rsc`. `MobileBandChange3.rsc` makes the same RouterOS API calls in the same order as the bundle's `scripts/MobileBandChange3.rsc`, but factors the inline state-save block into a single shared function-value (`mbc3SaveState`) rather than duplicating it at each of the four exit points — same behaviour, less duplication. The schedulers and script policies registered by `mbc3-install.rsc` mirror the bundle's tested `scheduler_templates.rsc` exactly. The installer/setup/cleanup wrappers are MobileBandCheckup-original code.

---

## What it does

The main script (`MobileBandChange3`) runs every minute via the RouterOS scheduler. Each run it polls the LTE interface monitor, extracts the current radio conditions, compares them against the last known state, and logs any changes. It is silent when nothing changes — except for a configurable periodic heartbeat.

### Events logged

| Event | Trigger |
|---|---|
| `LTE init` | First valid reading after boot or interface recovery |
| `LTE iface-down` / `LTE iface-up-recovery` | Interface transitions between running and not running |
| `NR connected` / `NR disconnected` | 5G NR component carrier appears or disappears |
| `LTE primary-switch` | Primary serving cell changes band, EARFCN, or PCI |
| `LTE ca-composition-change` | Carrier aggregation band set changes (deduplicated) |
| `LTE ca-raw-change` | CA band order/representation changes while normalized set is the same |
| `LTE rsrp-quality-change` | RSRP crosses a quality tier boundary (2-run debounce) |
| `LTE sinr-quality-change` | SINR crosses a quality tier boundary (2-run debounce) |
| `LTE heartbeat` | Periodic info snapshot (default every 60 runs = 60 min) |

Every event log includes the full context snapshot: data class, duplex mode, primary band, CA bands, and all signal metrics with labels.

### Signal quality labels

**RSRP** (reference signal received power):
- `excellent` ≥ −80 dBm
- `good` ≥ −90 dBm
- `fair` ≥ −100 dBm
- `poor` below −100 dBm

**SINR** (signal-to-interference-plus-noise ratio):
- `excellent` ≥ 20 dB
- `good` ≥ 13 dB
- `fair` ≥ 5 dB
- `poor` below 5 dB

**CQI** (channel quality indicator):
- `excellent` ≥ 12 · `good` ≥ 8 · `fair` ≥ 5 · `poor` below 5

**RI** (rank indicator): `MIMO` ≥ 2 streams · `single-stream` = 1

**MCS** (modulation and coding scheme): `idle` ≤ 0 · `low` < 10 · `medium` < 20 · `high` ≥ 20

---

## Script inventory

| File | Registered name | Role |
|---|---|---|
| `MobileBandChange3.rsc` | `MobileBandChange3` | Main poll loop — runs every 1 minute; writes state inline |
| `mbc3-restore-state.rsc` | `mbc3-restore-state` | Loads persisted state on boot (runs once) |
| `mbc3-install.rsc` | _(import only)_ | Bootstrap installer — registers scripts and schedulers with explicit policies; migrates legacy names |
| `mbc3-setup.rsc` | `mbc3-setup` | Re-registers schedulers only; idempotent, no .rsc files needed |
| `mbc3-cleanup.rsc` | `mbc3-cleanup` | Removes schedulers, scripts, state file, and `mbc3*` globals; dry-run by default |

State is stored in a single flat file, `/file mbc3-state.txt`, generated and overwritten by `MobileBandChange3` at each designated exit point. The file is created on the first save — no installer step is required for it.

---

## State persistence design

State is stored in `/file mbc3-state.txt` as parse-replay code: a start marker, a sequence of `:global` / `:set` lines for each persisted variable, and an end marker. Saves are written inline inside `MobileBandChange3` (no separate `mbc3-save` script) using `/file print` + `/file set contents=` so that arbitrary string content — including `;`, `"`, `$`, and spaces — survives a quoted `:set` round-trip via an `escapeStr` helper.

On boot, `mbc3-restore-state` reads `mbc3-state.txt`, refuses to act on missing/short/oversized files, requires both markers, then runs every line through an **allow-list guard** that only accepts comments or `:global`/`:set` of a known persisted variable with a well-formed scalar/quoted value. Anything else — an embedded `\r`, an unescaped `$`, a value with unexpected characters, an unknown variable name — cold-starts instead of executing untrusted content. Only after the guard passes does it `[:parse]` and run the payload.

Globals persisted across reboots: `mbc3LastPrimary`, `mbc3LastCA`, `mbc3LastCARaw`, `mbc3LastLRsrp`, `mbc3LastLSinr`, `mbc3LastNrActive`, `mbc3PendingLRsrp/Count`, `mbc3PendingLSinr/Count`, and the four runtime-option globals (`mbc3Debug`, `mbc3DebugRaw`, `mbc3HeartbeatEvery`, `mbc3QualityMonitor`).

`mbc3LogInited` is intentionally **not** restored. The first run after every reboot always emits a fresh `LTE init` snapshot, making log analysis unambiguous.

---

## Key design decisions

**Scheduler race guard.** On boot, `mbc3-restore-state` and `mbc3-run` both start at `startup` (with `mbc3-run` delayed 50s to let the modem settle). If `mbc3-run` fires first anyway, it checks whether `mbc3RestoreDone` is set. If not, it runs `mbc3-restore-state` inline before proceeding, so state is always loaded before the first comparison.

**Explicit script and scheduler policies.** RouterOS refuses to run a scheduled script when the scheduler's policy does not exactly match the script object's policy ("not enough permissions to run script"). The installer registers `MobileBandChange3` with `ftp,read,write,policy,test` (`ftp` for the inline state save, `test` for `/interface lte monitor`, `policy` for `:global` writes) and the matching scheduler `mbc3-run` with the same policy string; `mbc3-restore-state` and its scheduler are registered with `ftp,read,write,policy`. These match the bundle's tested deployment.

**2-run debounce on signal quality.** RSRP and SINR quality transitions only log when the new label is observed on two consecutive runs. This suppresses log noise from signals hovering near a class boundary.

**CA normalization.** The carrier aggregation band list from the modem can contain duplicates or vary in ordering without a real composition change. `MobileBandChange3` normalises the list with `normalizeCA` by removing exact duplicates (preserving first-seen order) before comparison, so only genuine set changes produce `ca-composition-change` events. Ordering/representation-only differences produce the lower-severity `ca-raw-change` event.

**Primary change classification.** When the primary cell changes, the script classifies the change as `band-change`, `earfcn-change`, `phy-cellid-change`, or `details-change` (everything else), and includes old/new values for each field in the log line.

**Crash-forensics probe.** Every significant step updates three globals (`mbc3Probe`, `mbc3ProbeDetail`, `mbc3FailProbe`). At the start of each run the previous values are copied to `mbc3LastRunProbe*`. If the script dies mid-run, the next run captures where it was.

---

## Installation

Upload the five `.rsc` files (`MobileBandChange3.rsc`, `mbc3-restore-state.rsc`, `mbc3-setup.rsc`, `mbc3-cleanup.rsc`, `mbc3-install.rsc`) to the router flash, then:

```
/import file-name=mbc3-install.rsc
```

The installer registers the four scripts (`MobileBandChange3`, `mbc3-restore-state`, `mbc3-setup`, `mbc3-cleanup`) with their required policies and adds the two scheduler entries. The state file `mbc3-state.txt` is created automatically on the first save. Source `.rsc` files can be removed from flash after install; everything runs from NVRAM scripts.

If you are upgrading from a pre-bundle-aligned revision the installer also removes the legacy `mbc3-restore` script and `mbc3-main` scheduler — your upgrade ends up with the same single, clean set of names as a fresh install.

### Uninstall

`mbc3-cleanup` is **dry-run by default** to prevent accidental data loss. With no commit flag set it logs what it would remove and counts entries; nothing is actually deleted. To dry-run first:

```
/system script run mbc3-cleanup
/log print where message~"mbc3-cleanup"
```

To apply, arm the commit flag and re-run:

```
:global mbc3CleanupCommit
:set mbc3CleanupCommit true
/system script run mbc3-cleanup
```

The flag auto-clears at the start of a committed run, so a later stray invocation falls back to dry-run. The cleanup removes both schedulers, all four registered scripts, the state file, all `mbc3*` globals, and legacy artefacts (`mbc3-restore`, `mbc3-main`, `mbc3-save`, `mbc3-state` script slot) from earlier revisions. To remove `mbc3-cleanup` itself afterwards: `/system script remove [find name=mbc3-cleanup]`.

To update schedulers later without touching script source:

```
/system script run mbc3-setup
```

### Optional runtime globals

Set before (or after) the first run. These are persisted across reboots once the first inline state save runs.

```
:global mbc3HeartbeatEvery
:set mbc3HeartbeatEvery 60     # heartbeat every N runs (1m scheduler → 60 min)

:global mbc3Debug
:set mbc3Debug false           # verbose debug logs

:global mbc3DebugRaw
:set mbc3DebugRaw false        # raw (unformatted) metric lines on every event

:global mbc3QualityMonitor
:set mbc3QualityMonitor false  # default false; set true to enable rsrp/sinr-quality-change events (adds NVRAM writes)
```

---

## Scheduler entries created

| Name | Start | Interval | Action | Policy |
|---|---|---|---|---|
| `mbc3-restore-state` | startup | 0 (once) | `/system script run mbc3-restore-state` | `ftp,read,write,policy` |
| `mbc3-run` | startup | 1m | `:delay 50s; /system script run MobileBandChange3` | `ftp,read,write,policy,test` |

---

## License

MIT — see [LICENSE](LICENSE).
