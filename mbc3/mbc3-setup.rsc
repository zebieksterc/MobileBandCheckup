# mbc3-setup
# revision: mbc3-final-20260425-write-min-v1
#
# Registers or updates scheduler entries only. Does NOT touch script source.
# Safe to run at any time — idempotent, no source .rsc files required.
#
# Run via:
#   /system script run mbc3-setup    (after install has registered it)
#   /import file-name=mbc3-setup.rsc (before install, or as standalone)
#
# To register or update scripts from .rsc source files, use mbc3-install.rsc.

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

    :do {
        /system scheduler add name=$name start-time=$startTime interval=$interval on-event=$onEvent comment=$comment
        :log info ("[mbc3-setup] scheduler added: " . $name)
    } on-error={
        /system scheduler set [find name=$name] start-time=$startTime interval=$interval on-event=$onEvent comment=$comment
        :log info ("[mbc3-setup] scheduler updated: " . $name)
    }
}

# --- Register scheduler entries ---
# Order matters: mbc3-restore must appear before mbc3-main so it runs first on boot.
#
# mbc3-restore: interval=0 fires once per boot. Kept enabled intentionally —
#   removing it causes a cold start (state loss) on every reboot.
# mbc3-main: fires once at startup then repeats every 1 minute.
$upsertScheduler "mbc3-restore" "startup" "0" "/system script run mbc3-restore" "LTE band monitor - restore state (runs once per boot)"

$upsertScheduler "mbc3-main" "startup" "1m" "/system script run MobileBandChange3" "LTE band monitor - main loop (runs every 1 min)"

:log info ($logPrefix . "setup complete")

# --- Optional: set runtime globals before first run ---
# Uncomment and adjust as needed:

# :global mbc3HeartbeatEvery
# :set mbc3HeartbeatEvery 60        # heartbeat every N runs (default 60 = 60 min with 1m scheduler)

# :global mbc3Debug
# :set mbc3Debug false              # set true for verbose debug logs

# :global mbc3DebugRaw
# :set mbc3DebugRaw false           # set true for raw metric lines on every event
