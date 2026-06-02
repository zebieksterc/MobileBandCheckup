# mbc3-setup
# revision: mbc3-final-20260602-p0003-inline-helpers
#
# Registers or updates scheduler entries only. Does NOT touch script source.
# Safe to run at any time — idempotent, no source .rsc files required.
#
# Run via:
#   /system script run mbc3-setup    (after install has registered it)
#   /import file-name=mbc3-setup.rsc (before install, or as standalone)
#
# To register or update scripts from .rsc source files, use mbc3-install.rsc.
#
# Schedulers and policies mirror the routeros_bundle b2.22 tested deployment
# (RouterOS 7.21.4, MikroTik Chateau 5G, confirmed 2026-05-31 18:41).

:local logPrefix "[mbc3-setup] "

# --- Helper: upsert a scheduler entry ---
#
# Safe pattern: try add first; if it fails (already exists) do set with
# inline [find name=...]. Never pass a stored find result to set — RouterOS
# will apply set to ALL entries when the stored ID is empty or unresolvable.
:local upsertScheduler do={
    :local name $1
    :local startTime $2
    :local interval $3
    :local onEvent $4
    :local comment $5
    :local policy $6

    :do {
        /system scheduler add name=$name start-time=$startTime interval=$interval on-event=$onEvent comment=$comment policy=$policy
        :log info ("[mbc3-setup] scheduler added: " . $name . " policy=" . $policy)
    } on-error={
        /system scheduler set [find name=$name] start-time=$startTime interval=$interval on-event=$onEvent comment=$comment policy=$policy
        :log info ("[mbc3-setup] scheduler updated: " . $name . " policy=" . $policy)
    }
}

# --- Legacy scheduler removal (migration from pre-bundle-aligned revisions) ---
:if ([:len [/system scheduler find name="mbc3-main"]] > 0) do={
    /system scheduler remove [find name="mbc3-main"]
    :log info ($logPrefix . "legacy scheduler removed: mbc3-main (replaced by mbc3-run)")
}
:if ([:len [/system scheduler find name="mbc3-restore"]] > 0) do={
    /system scheduler remove [find name="mbc3-restore"]
    :log info ($logPrefix . "legacy scheduler removed: mbc3-restore (replaced by mbc3-restore-state)")
}

# --- Register scheduler entries ---
# Scheduler policy MUST be identical to the script object it runs, or RouterOS
# refuses with "not enough permissions to run script".
$upsertScheduler "mbc3-restore-state" "startup" "0" "/system script run mbc3-restore-state" "LTE band monitor - restore state (runs once per boot)" "ftp,read,write,policy"

$upsertScheduler "mbc3-run" "startup" "1m" ":delay 50s; /system script run MobileBandChange3" "LTE band monitor - main loop (runs every 1 min after a 50s startup stagger)" "ftp,read,write,policy,test"

:log info ($logPrefix . "setup complete")

# --- Optional: set runtime globals before first run ---
# Uncomment and adjust as needed:

# :global mbc3HeartbeatEvery
# :set mbc3HeartbeatEvery 60        # heartbeat every N runs (default 60 = 60 min with 1m scheduler)

# :global mbc3Debug
# :set mbc3Debug false              # set true for verbose debug logs

# :global mbc3DebugRaw
# :set mbc3DebugRaw false           # set true for raw metric lines on every event
