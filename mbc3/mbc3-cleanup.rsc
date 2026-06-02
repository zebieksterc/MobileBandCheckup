# mbc3-cleanup
# revision: mbc3-final-20260602-save-helper-revert
#
# Removes everything mbc3-install.rsc installs. Symmetric to mbc3-install.
#
# DRY-RUN BY DEFAULT — matches the routeros_bundle bundle-reset-state pattern.
# With no commit flag set it logs what it WOULD remove and counts entries;
# nothing is actually deleted. To apply, arm the commit flag first:
#
#     :global mbc3CleanupCommit; :set mbc3CleanupCommit true
#     /system script run mbc3-cleanup
#
# The flag is auto-cleared at the start of a committed run so a stray re-run
# falls back to dry-run instead of silently wiping again.
#
# Order matters on commit:
#   1. Remove schedulers first so neither mbc3-restore-state nor mbc3-run can
#      fire between us deleting their script bodies and finishing.
#   2. Remove scripts.
#   3. Remove the state file /file mbc3-state.txt.
#   4. Remove legacy artefacts (mbc3-restore script, mbc3-main scheduler,
#      mbc3-save script, mbc3-state script slot) from earlier revisions so
#      upgraders end up identical to fresh installs.
#   5. Clear every mbc3* global from /system script environment.
#
# To remove this script itself afterwards:
#   /system script remove [find name=mbc3-cleanup]

:global mbc3CleanupCommit

:local logPrefix "[mbc3-cleanup] "

:local commit false
:if (([:typeof $mbc3CleanupCommit] = "bool") and ($mbc3CleanupCommit = true)) do={
    :set commit true
}
# Disarm-first: clear the commit flag NOW, before any destructive op, so a
# mid-run abort cannot leave it armed for an accidental re-commit.
:if ($commit = true) do={ :set mbc3CleanupCommit false }

:if ($commit = true) do={
    :log warning ($logPrefix . "COMMIT mode: changes WILL be applied")
} else={
    :log warning ($logPrefix . "DRY-RUN: no changes. Set mbc3CleanupCommit=true then re-run to apply")
}

:local schedCount 0
:local scriptCount 0
:local fileCount 0
:local globalCount 0

# --- Helper: remove a scheduler entry by name ---
:local removeScheduler do={
    :local name $1
    :local commit $2
    :local ids [/system scheduler find where name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] scheduler absent: " . $name)
        :return 0
    }
    :if ($commit = true) do={
        :do {
            /system scheduler remove [find name=$name]
            :log info ("[mbc3-cleanup] scheduler removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] scheduler remove failed: " . $name)
            :return 0
        }
    } else={
        :log info ("[mbc3-cleanup] DRY-RUN would remove scheduler: " . $name)
    }
    :return 1
}

# --- Helper: remove a system script by name ---
:local removeScript do={
    :local name $1
    :local commit $2
    :local ids [/system script find where name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] script absent: " . $name)
        :return 0
    }
    :if ($commit = true) do={
        :do {
            /system script remove [find name=$name]
            :log info ("[mbc3-cleanup] script removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] script remove failed: " . $name)
            :return 0
        }
    } else={
        :log info ("[mbc3-cleanup] DRY-RUN would remove script: " . $name)
    }
    :return 1
}

# --- Helper: remove a file by name ---
:local removeFile do={
    :local name $1
    :local commit $2
    :local ids [/file find name=$name]
    :if ([:len $ids] = 0) do={
        :log info ("[mbc3-cleanup] file absent: " . $name)
        :return 0
    }
    :if ($commit = true) do={
        :do {
            /file remove [find name=$name]
            :log info ("[mbc3-cleanup] file removed: " . $name)
        } on-error={
            :log warning ("[mbc3-cleanup] file remove failed: " . $name)
            :return 0
        }
    } else={
        :log info ("[mbc3-cleanup] DRY-RUN would remove file: " . $name)
    }
    :return 1
}

# --- Step 1: Remove schedulers (current + legacy names) ---
:set schedCount ($schedCount + [$removeScheduler "mbc3-run" $commit])
:set schedCount ($schedCount + [$removeScheduler "mbc3-restore-state" $commit])
:set schedCount ($schedCount + [$removeScheduler "mbc3-main" $commit])
:set schedCount ($schedCount + [$removeScheduler "mbc3-restore" $commit])

# --- Step 2: Remove scripts (current + legacy names) ---
:set scriptCount ($scriptCount + [$removeScript "MobileBandChange3" $commit])
:set scriptCount ($scriptCount + [$removeScript "mbc3-restore-state" $commit])
:set scriptCount ($scriptCount + [$removeScript "mbc3-setup" $commit])
:set scriptCount ($scriptCount + [$removeScript "mbc3-restore" $commit])
:set scriptCount ($scriptCount + [$removeScript "mbc3-save" $commit])
:set scriptCount ($scriptCount + [$removeScript "mbc3-state" $commit])

# --- Step 3: Remove the state file ---
:set fileCount ($fileCount + [$removeFile "mbc3-state.txt" $commit])

# --- Step 4: Clear all mbc3* globals from the environment ---
# Removing from /system script environment is what unsets in-place — :set var
# without a value would only blank, not free the slot. The "name~\"^mbc3\""
# match catches runtime options, comparison state, debounce counters, probe
# trackers, restore-done, and the cleanup commit flag in one sweep.
:local envIds [/system script environment find where name~"^mbc3"]
:if ([:len $envIds] = 0) do={
    :log info ($logPrefix . "globals absent: none with mbc3* prefix")
} else={
    :set globalCount [:len $envIds]
    :if ($commit = true) do={
        :do {
            /system script environment remove [find where name~"^mbc3"]
            :log info ($logPrefix . "globals cleared: " . $globalCount . " mbc3* entries")
        } on-error={
            :log warning ($logPrefix . "globals clear failed (some may remain until reboot)")
        }
    } else={
        :log info ($logPrefix . "DRY-RUN would clear " . $globalCount . " global(s) with mbc3* prefix")
    }
}

:local summary ("schedulers=" . $schedCount . " scripts=" . $scriptCount . " files=" . $fileCount . " globals=" . $globalCount)
:if ($commit = true) do={
    :log warning ($logPrefix . "COMMIT done: removed " . $summary . "; commit flag cleared")
} else={
    :log warning ($logPrefix . "DRY-RUN done: would remove " . $summary . ". Set mbc3CleanupCommit=true then re-run to apply")
}
