# MobileBandCheckup

RouterOS scripting suite for MikroTik routers that monitors LTE/NR (5G NSA) band changes and signal quality on a modem interface, logging every meaningful transition to the system log and persisting comparison state across reboots.

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
| `MobileBandChange3.rsc` | `MobileBandChange3` | Main poll loop — runs every 1 minute |
| `mbc3-save.rsc` | `mbc3-save` | Persists globals to NVRAM script `mbc3-state` |
| `mbc3-restore.rsc` | `mbc3-restore` | Loads persisted state on boot (runs once) |
| `mbc3-install.rsc` | _(import only)_ | Bootstrap installer — registers scripts and schedulers |
| `mbc3-setup.rsc` | `mbc3-setup` | Re-registers schedulers only; idempotent, no .rsc files needed |

A sixth script slot, `mbc3-state`, is auto-created by the installer and managed entirely by `mbc3-save`. It stores the serialized global state as RouterOS script source so that `mbc3-restore` can replay it on the next boot.

---

## State persistence design

State is stored inside `/system script source` (NVRAM) rather than flash files. This avoids flash wear and the RouterOS `/file` write API limitations. `mbc3-save` builds the restore script as a string, validates it with start/end markers and size bounds (300–60 000 bytes), writes it to the `mbc3-state` script slot, then reads it back and verifies length and markers. The write is retried up to three times on failure.

Globals persisted across reboots: `mbc3LastPrimary`, `mbc3LastCA`, `mbc3LastCARaw`, `mbc3LastLRsrp`, `mbc3LastLSinr`, `mbc3LastNrActive`, `mbc3PendingLRsrp/Count`, `mbc3PendingLSinr/Count`, and the three runtime-option globals (`mbc3Debug`, `mbc3DebugRaw`, `mbc3HeartbeatEvery`).

`mbc3LogInited` is intentionally **not** restored. The first run after every reboot always emits a fresh `LTE init` snapshot, making log analysis unambiguous.

---

## Key design decisions

**Scheduler race guard.** On boot, `mbc3-restore` and `mbc3-main` both start at `startup`. If `mbc3-main` fires first, it checks whether `mbc3RestoreDone` is set. If not, it runs `mbc3-restore` inline before proceeding, so state is always loaded before the first comparison.

**2-run debounce on signal quality.** RSRP and SINR quality transitions only log when the new label is observed on two consecutive runs. This suppresses log noise from signals hovering near a class boundary.

**CA normalization.** The carrier aggregation band list from the modem can contain duplicates or vary in ordering without a real composition change. `mbc3-save` normalises the list by removing exact duplicates (preserving first-seen order) before comparison, so only genuine set changes produce `ca-composition-change` events. Ordering/representation-only differences produce the lower-severity `ca-raw-change` event.

**Primary change classification.** When the primary cell changes, the script classifies the change as `band-change`, `earfcn-change`, `phy-cellid-change`, or `details-change` (everything else), and includes old/new values for each field in the log line.

**Crash-forensics probe.** Every significant step updates three globals (`mbc3Probe`, `mbc3ProbeDetail`, `mbc3FailProbe`). At the start of each run the previous values are copied to `mbc3LastRunProbe*`. If the script dies mid-run, the next run captures where it was.

---

## Installation

Upload all five `.rsc` files to the router flash, then:

```
/import file-name=mbc3-install.rsc
```

The installer registers the four scripts, creates the `mbc3-state` slot, and adds the two scheduler entries. Source `.rsc` files can be removed from flash after install; everything runs from NVRAM scripts.

To update schedulers later without touching script source:

```
/system script run mbc3-setup
```

### Optional runtime globals

Set before (or after) the first run. These are persisted across reboots once `mbc3-save` runs.

```
:global mbc3HeartbeatEvery
:set mbc3HeartbeatEvery 60     # heartbeat every N runs (1m scheduler → 60 min)

:global mbc3Debug
:set mbc3Debug false           # verbose debug logs

:global mbc3DebugRaw
:set mbc3DebugRaw false        # raw (unformatted) metric lines on every event

:global mbc3QualityMonitor
:set mbc3QualityMonitor true   # set false to silence rsrp/sinr-quality-change events and reduce NVRAM writes
```

---

## Scheduler entries created

| Name | Start | Interval | Action |
|---|---|---|---|
| `mbc3-restore` | startup | 0 (once) | `/system script run mbc3-restore` |
| `mbc3-main` | startup | 1m | `/system script run MobileBandChange3` |
