# mbc3-install
# revision: mbc3-final-20260531-file-state+restore-guard
#
# Bootstrap installer. Run via:
#   /import file-name=mbc3-install.rsc
#
# NOT via /system script run — this file is not a registered script.
#
# Requires these files to be present on router flash:
#   MobileBandChange3.rsc
#   mbc3-restore.rsc
#   mbc3-setup.rsc
#
# What it does:
#   1. Registers all three scripts in /system script
#   2. Registers scheduler entries
#
# After install, source .rsc files can be removed — not needed at runtime.
# State is stored in /file mbc3-state.txt, written inline by MobileBandChange3
# on every state change and read back by mbc3-restore on boot.
# To update schedulers later without touching scripts: /system script run mbc3-setup

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
        /system script add name=$name source=$src comment=$comment
        :log info ("[mbc3-install] script added: " . $name . " len=" . $srcLen)
    } on-error={
        /system script set [find name=$name] source=$src comment=$comment
        :log info ("[mbc3-install] script updated: " . $name . " len=" . $srcLen)
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

    :do {
        /system scheduler add name=$name start-time=$startTime interval=$interval on-event=$onEvent comment=$comment
        :log info ("[mbc3-install] scheduler added: " . $name)
    } on-error={
        /system scheduler set [find name=$name] start-time=$startTime interval=$interval on-event=$onEvent comment=$comment
        :log info ("[mbc3-install] scheduler updated: " . $name)
    }
}

# --- Step 1: Register scripts ---
$upsertScript "MobileBandChange3" "MobileBandChange3.rsc" "LTE band change monitor - main loop" "20000"

$upsertScript "mbc3-restore" "mbc3-restore.rsc" "LTE band change monitor - restore state on boot" "300"

$upsertScript "mbc3-setup" "mbc3-setup.rsc" "LTE band change monitor - scheduler setup (safe to re-run)" "500"

# State is stored in /file mbc3-state.txt. The file is created on the first
# state save by MobileBandChange3 — no install step needed. mbc3-restore
# tolerates a missing file (cold start path).

# --- Step 2: Register scheduler entries ---
# Order matters: mbc3-restore must appear before mbc3-main so it runs first on boot.
#
# mbc3-restore: interval=0 fires once per boot. Kept enabled intentionally —
#   removing it causes a cold start (state loss) on every reboot.
# mbc3-main: fires once at startup then repeats every 1 minute.
$upsertScheduler "mbc3-restore" "startup" "0" "/system script run mbc3-restore" "LTE band monitor - restore state (runs once per boot)"

$upsertScheduler "mbc3-main" "startup" "1m" "/system script run MobileBandChange3" "LTE band monitor - main loop (runs every 1 min)"

:log info ($logPrefix . "install complete")

# --- Optional: set runtime globals before first run ---
# Uncomment and adjust as needed:

# :global mbc3HeartbeatEvery
# :set mbc3HeartbeatEvery 60        # heartbeat every N runs (default 60 = 60 min with 1m scheduler)

# :global mbc3Debug
# :set mbc3Debug false              # set true for verbose debug logs

# :global mbc3DebugRaw
# :set mbc3DebugRaw false           # set true for raw metric lines on every event
