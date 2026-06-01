# mbc3-cleanup
# revision: mbc3-final-20260531-file-state+restore-guard
#
# NOT YET TESTED ON HARDWARE. Authored from spec; verify on a live router
# before relying on it. Read the script before running on a production box.
#
# Removes everything mbc3-install.rsc installs. Safe to run at any time —
# idempotent, every step tolerates already-missing targets.
#
# Run via:
#   /import file-name=mbc3-cleanup.rsc           (before install, or as standalone)
#   /system script run mbc3-cleanup              (after install has registered it)
#
# Order matters:
#   1. Remove schedulers first so neither mbc3-restore nor mbc3-main can fire
#      between us deleting their script bodies and finishing.
#   2. Remove scripts.
#   3. Remove the state file.
#   4. Also remove legacy artefacts from the pre-file-state architecture
#      (mbc3-save script, mbc3-state script slot) so upgraders end up clean.
#   5. Clear every mbc3* global from /system script environment so a re-install
#      starts from a true clean slate (without needing a reboot).

:local logPrefix "[mbc3-cleanup] "

# --- Helper: remove a scheduler entry by name ---
:local removeScheduler do={
    :local name $1
    :local ids [/system scheduler find where name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] scheduler absent: " . $name)
    } else={
        :do {
            /system scheduler remove [find name=$name]
            :log info ("[mbc3-cleanup] scheduler removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] scheduler remove failed: " . $name)
        }
    }
}

# --- Helper: remove a system script by name ---
:local removeScript do={
    :local name $1
    :local ids [/system script find where name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] script absent: " . $name)
    } else={
        :do {
            /system script remove [find name=$name]
            :log info ("[mbc3-cleanup] script removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] script remove failed: " . $name)
        }
    }
}

# --- Helper: remove a file by name ---
:local removeFile do={
    :local name $1
    :local ids [/file find name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] file absent: " . $name)
    } else={
        :do {
            /file remove [find name=$name]
            :log info ("[mbc3-cleanup] file removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] file remove failed: " . $name)
        }
    }
}

# --- Step 1: Remove schedulers ---
$removeScheduler "mbc3-main"
$removeScheduler "mbc3-restore"

# --- Step 2: Remove scripts (current architecture) ---
$removeScript "MobileBandChange3"
$removeScript "mbc3-restore"
$removeScript "mbc3-setup"

# --- Step 3: Remove the state file ---
$removeFile "mbc3-state.txt"

# --- Step 4: Legacy cleanup (pre-file-state architecture) ---
# Old architecture stored state in /system script source mbc3-state and used a
# separate mbc3-save script. Both are gone in the current revision; remove them
# if present so upgraders end up with the same clean state as fresh installs.
$removeScript "mbc3-save"
$removeScript "mbc3-state"

# --- Step 5: Clear all mbc3* globals from the environment ---
# /system script environment holds every :global ever set this boot. Removing
# entries here is what unsets them in-place — :set var without a value would
# only blank them, not free the slot. The find expression "name~\"^mbc3\""
# matches every name beginning with mbc3 so we catch runtime options,
# comparison state, debounce counters, probe trackers, restore-done, etc., in
# one sweep without having to enumerate them.
:local envIds [/system script environment find where name~"^mbc3"]
:if ([:len $envIds] = 0) do={
    :log info ($logPrefix . "globals absent: none with mbc3* prefix")
} else={
    :do {
        /system script environment remove [find where name~"^mbc3"]
        :log info ($logPrefix . "globals cleared: " . [:len $envIds] . " mbc3* entries")
    } on-error={
        :log warning ($logPrefix . "globals clear failed (some may remain until reboot)")
    }
}

:log info ($logPrefix . "cleanup complete")

# To remove this script itself afterwards (if you imported the .rsc and let
# mbc3-install register it), run:
#   /system script remove [find name=mbc3-cleanup]
