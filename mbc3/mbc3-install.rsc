# mbc3-install
# revision: mbc3-final-20260602-save-helper
#
# Bootstrap installer. Run via:
#   /import file-name=mbc3-install.rsc
#
# NOT via /system script run — this file is not a registered script.
#
# Requires these files to be present on router flash:
#   MobileBandChange3.rsc
#   mbc3-restore-state.rsc
#   mbc3-setup.rsc
#   mbc3-cleanup.rsc
#
# What it does:
#   1. Removes legacy script/scheduler names from prior revisions if present
#      (mbc3-restore script, mbc3-main scheduler).
#   2. Registers all four scripts in /system script with explicit policy.
#   3. Registers scheduler entries with policy matching each script.
#
# Policy is REQUIRED. RouterOS refuses to run a scheduled script when the
# scheduler's policy does not exactly match the script object's policy
# ("not enough permissions to run script"). Per-object policy:
#   MobileBandChange3   : ftp,read,write,policy,test
#       ftp    = inline /file mbc3-state.txt write
#       test   = /interface lte monitor
#       policy = :global var writes
#   mbc3-restore-state  : ftp,read,write,policy
#       ftp    = read state file
#       policy = :global var writes
#   mbc3-setup          : read,write,policy
#   mbc3-cleanup        : ftp,read,write,policy
#       ftp = /file remove of state file
#
# These match the bundle's confirmed-working set (routeros_bundle b2.22,
# 2026-05-31 18:41 reboot, RouterOS 7.21.4, MikroTik Chateau 5G, Quectel
# RG650E-EU). See routeros_bundle/schedulers/scheduler_templates.rsc.
#
# After install, source .rsc files can be removed — not needed at runtime.
# State is stored in /file mbc3-state.txt, written inline by MobileBandChange3
# on every state change and read back by mbc3-restore-state on boot.
# To update schedulers later without touching scripts: /system script run mbc3-setup
# To remove everything: /system script run mbc3-cleanup

:local logPrefix "[mbc3-install] "

# --- Helper: upsert a system script from an uploaded .rsc file ---
#
# Safe pattern: try add first; if it fails (already exists) do set with
# inline [find name=...]. Never pass a stored find result to set — RouterOS
# will apply set to ALL entries when the stored ID is empty or unresolvable.
:local upsertScript do={
    :local name $1
    :local file $2
    :local comment $3
    :local minLen $4
    :local policy $5

    :local fid [/file find name=$file]
    :if ([:len $fid] = 0) do={
        :log error ("[mbc3-install] source file not found: " . $file)
        :return ""
    }

    :local src [/file get $fid contents]
    :local srcLen [:len $src]

    :if ($srcLen < $minLen) do={
        :log error ("[mbc3-install] source file appears truncated: " . $file . " len=" . $srcLen . " expected>=" . $minLen)
        :return ""
    }

    :do {
        /system script add name=$name source=$src comment=$comment policy=$policy
        :log info ("[mbc3-install] script added: " . $name . " len=" . $srcLen . " policy=" . $policy)
    } on-error={
        /system script set [find name=$name] source=$src comment=$comment policy=$policy
        :log info ("[mbc3-install] script updated: " . $name . " len=" . $srcLen . " policy=" . $policy)
    }
}

# --- Helper: upsert a scheduler entry ---
#
# Same safe pattern: try add first, fall back to set [find name=...] inline.
:local upsertScheduler do={
    :local name $1
    :local startTime $2
    :local interval $3
    :local onEvent $4
    :local comment $5
    :local policy $6

    :do {
        /system scheduler add name=$name start-time=$startTime interval=$interval on-event=$onEvent comment=$comment policy=$policy
        :log info ("[mbc3-install] scheduler added: " . $name . " policy=" . $policy)
    } on-error={
        /system scheduler set [find name=$name] start-time=$startTime interval=$interval on-event=$onEvent comment=$comment policy=$policy
        :log info ("[mbc3-install] scheduler updated: " . $name . " policy=" . $policy)
    }
}

# --- Step 0: Remove legacy names from prior revisions ---
# Pre-bundle-aligned revisions used mbc3-restore (script) and mbc3-main
# (scheduler). Remove them here so upgraders end up with a single, clean set
# of names matching the bundle. Tolerates absence.
:if ([:len [/system scheduler find name="mbc3-main"]] > 0) do={
    /system scheduler remove [find name="mbc3-main"]
    :log info ($logPrefix . "legacy scheduler removed: mbc3-main (replaced by mbc3-run)")
}
:if ([:len [/system script find name="mbc3-restore"]] > 0) do={
    /system script remove [find name="mbc3-restore"]
    :log info ($logPrefix . "legacy script removed: mbc3-restore (replaced by mbc3-restore-state)")
}

# --- Step 1: Register scripts ---
$upsertScript "MobileBandChange3" "MobileBandChange3.rsc" "LTE band change monitor - main loop" "20000" "ftp,read,write,policy,test"

$upsertScript "mbc3-restore-state" "mbc3-restore-state.rsc" "LTE band change monitor - restore state on boot" "300" "ftp,read,write,policy"

$upsertScript "mbc3-setup" "mbc3-setup.rsc" "LTE band change monitor - scheduler setup (safe to re-run)" "500" "read,write,policy"

$upsertScript "mbc3-cleanup" "mbc3-cleanup.rsc" "LTE band change monitor - remove scripts, schedulers, state, and globals" "500" "ftp,read,write,policy"

# State is stored in /file mbc3-state.txt. The file is created on the first
# state save by MobileBandChange3 — no install step needed. mbc3-restore-state
# tolerates a missing file (cold start path).

# --- Step 2: Register scheduler entries ---
# Order matters: mbc3-restore-state must run before mbc3-run on boot.
#
# mbc3-restore-state: interval=0 fires once per boot. Kept enabled intentionally
#   — removing it causes a cold start (state loss) on every reboot.
# mbc3-run: fires once at startup then repeats every 1 minute, with a 50s
#   stagger via :delay so it doesn't race the boot. Mirrors the bundle's tested
#   "mbc3-run" scheduler exactly.
$upsertScheduler "mbc3-restore-state" "startup" "0" "/system script run mbc3-restore-state" "LTE band monitor - restore state (runs once per boot)" "ftp,read,write,policy"

$upsertScheduler "mbc3-run" "startup" "1m" ":delay 50s; /system script run MobileBandChange3" "LTE band monitor - main loop (runs every 1 min after a 50s startup stagger)" "ftp,read,write,policy,test"

:log info ($logPrefix . "install complete")

# --- Optional: set runtime globals before first run ---
# Uncomment and adjust as needed:

# :global mbc3HeartbeatEvery
# :set mbc3HeartbeatEvery 60        # heartbeat every N runs (default 60 = 60 min with 1m scheduler)

# :global mbc3Debug
# :set mbc3Debug false              # set true for verbose debug logs

# :global mbc3DebugRaw
# :set mbc3DebugRaw false           # set true for raw metric lines on every event

# :global mbc3QualityMonitor
# :set mbc3QualityMonitor false     # default false; set true to enable rsrp/sinr-quality-change events
