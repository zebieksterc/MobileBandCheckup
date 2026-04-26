# mbc3-save-final-grade
# revision: mbc3-final-20260425-script-store-v3-write-min
# Purpose:
#   Persist selected MobileBandChange3 globals into a RouterOS script named mbc3-state.
# Restore method:
#   /system script run mbc3-restore
# Direct state replay method:
#   /system script run mbc3-state
#
# Design:
#   - Does not use RouterOS /file contents writes.
#   - Stores generated restore code in /system script source.
#   - Auto-creates mbc3-state if missing.
#   - Validates state markers before and after write.
#   - Enforces size bounds to detect empty/truncated/oversized state.
#   - Retries write up to three times.
#   - Does not persist transient runtime diagnostics:
#       mbc3LogInited, mbc3RunCount, mbc3HeartbeatCount,
#       mbc3LastIfaceRunning, mbc3Probe*, mbc3Detail*, mbc3Fail*

:global mbc3Debug
:global mbc3DebugRaw
:global mbc3HeartbeatEvery
:global mbc3LastPrimary
:global mbc3LastCA
:global mbc3LastCARaw
:global mbc3LastLRsrp
:global mbc3LastLSinr
:global mbc3LastNrActive
:global mbc3PendingLRsrp
:global mbc3PendingLRsrpCount
:global mbc3PendingLSinr
:global mbc3PendingLSinrCount

:local tag "[mbc3-save] "
:local stateScript "mbc3-state"
:local markerStart "# MBC3-STATE-V1"
:local markerEnd "# MBC3-STATE-END"
:local minLen 300
:local maxLen 60000
:local nl "\n"
:local q "\""

:local boolStr do={
    :if ([:typeof $1] = "nothing") do={ :return "false" }
    :if ($1 = true) do={ :return "true" }
    :return "false"
}

:local intStr do={
    :if ([:typeof $1] = "nothing") do={ :return $2 }
    :if ([:len [:tostr $1]] = 0) do={ :return $2 }
    :return [:tostr $1]
}

:local escapeStr do={
    :if ([:typeof $1] = "nothing") do={ :return "" }

    :local s [:tostr $1]
    :local out ""
    :local slen [:len $s]

    :if ($slen = 0) do={ :return "" }

    :for i from=0 to=($slen - 1) do={
        :local c [:pick $s $i ($i + 1)]
        :if ($c = "\\") do={
            :set out ($out . "\\\\")
        } else={
            :if ($c = "\"") do={
                :set out ($out . "\\\"")
            } else={
                :set out ($out . $c)
            }
        }
    }

    :return $out
}

:local out ""

# ===== HEADER / MARKERS =====
:set out ($out . $markerStart . $nl)
:set out ($out . "# mbc3-state" . $nl)
:set out ($out . "# generated-by=mbc3-save-final-grade" . $nl)
:set out ($out . "# restore-with=/system script run mbc3-restore" . $nl)
:set out ($out . "# direct-replay=/system script run mbc3-state" . $nl)
:set out ($out . $nl)

# ===== RUNTIME OPTIONS =====
:set out ($out . ":global mbc3Debug" . $nl)
:set out ($out . ":set mbc3Debug " . [$boolStr $mbc3Debug] . $nl)

:set out ($out . ":global mbc3DebugRaw" . $nl)
:set out ($out . ":set mbc3DebugRaw " . [$boolStr $mbc3DebugRaw] . $nl)

:set out ($out . ":global mbc3HeartbeatEvery" . $nl)
:set out ($out . ":set mbc3HeartbeatEvery " . [$intStr $mbc3HeartbeatEvery "60"] . $nl)

# ===== COMPARISON STATE =====
:set out ($out . ":global mbc3LastPrimary" . $nl)
:set out ($out . ":set mbc3LastPrimary " . $q . [$escapeStr $mbc3LastPrimary] . $q . $nl)

:set out ($out . ":global mbc3LastCA" . $nl)
:set out ($out . ":set mbc3LastCA " . $q . [$escapeStr $mbc3LastCA] . $q . $nl)

:set out ($out . ":global mbc3LastCARaw" . $nl)
:set out ($out . ":set mbc3LastCARaw " . $q . [$escapeStr $mbc3LastCARaw] . $q . $nl)

:set out ($out . ":global mbc3LastLRsrp" . $nl)
:set out ($out . ":set mbc3LastLRsrp " . $q . [$escapeStr $mbc3LastLRsrp] . $q . $nl)

:set out ($out . ":global mbc3LastLSinr" . $nl)
:set out ($out . ":set mbc3LastLSinr " . $q . [$escapeStr $mbc3LastLSinr] . $q . $nl)

:set out ($out . ":global mbc3LastNrActive" . $nl)
:set out ($out . ":set mbc3LastNrActive " . [$boolStr $mbc3LastNrActive] . $nl)

# ===== DEBOUNCE STATE =====
:set out ($out . ":global mbc3PendingLRsrp" . $nl)
:set out ($out . ":set mbc3PendingLRsrp " . $q . [$escapeStr $mbc3PendingLRsrp] . $q . $nl)

:set out ($out . ":global mbc3PendingLRsrpCount" . $nl)
:set out ($out . ":set mbc3PendingLRsrpCount " . [$intStr $mbc3PendingLRsrpCount "0"] . $nl)

:set out ($out . ":global mbc3PendingLSinr" . $nl)
:set out ($out . ":set mbc3PendingLSinr " . $q . [$escapeStr $mbc3PendingLSinr] . $q . $nl)

:set out ($out . ":global mbc3PendingLSinrCount" . $nl)
:set out ($out . ":set mbc3PendingLSinrCount " . [$intStr $mbc3PendingLSinrCount "0"] . $nl)

:set out ($out . $nl)
:set out ($out . ":log info \"[mbc3-state] restored persisted MobileBandChange3 state\"" . $nl)
:set out ($out . $markerEnd . $nl)

:local outLen [:len $out]

# ===== PRE-WRITE VALIDATION =====
:if ($outLen < $minLen) do={
    :log warning ($tag . "SAFE refuse save: generated state too short outLen=" . $outLen)
    :return
}

:if ($outLen > $maxLen) do={
    :log error ($tag . "DISRUPTIVE refuse save: generated state too large outLen=" . $outLen)
    :return
}

:if ([:find $out $markerStart] = nil) do={
    :log error ($tag . "DISRUPTIVE refuse save: start marker missing")
    :return
}

:if ([:find $out $markerEnd] = nil) do={
    :log error ($tag . "DISRUPTIVE refuse save: end marker missing")
    :return
}

:if ([:typeof $mbc3Debug] != "nothing") do={
    :if ($mbc3Debug = true) do={
        :log debug ($tag . "save start target=" . $stateScript . " outLen=" . $outLen)
    }
}

# ===== TARGET CREATE / WRITE / VERIFY =====
:do {
    :local sid [/system script find where name=$stateScript]

    :if ([:len $sid] = 0) do={
        :log warning ($tag . "MODERATE state script missing, creating " . $stateScript)
        /system script add name=$stateScript source="# mbc3-state placeholder"
        :set sid [/system script find where name=$stateScript]
    }

    :if ([:len $sid] = 0) do={
        :log error ($tag . "DISRUPTIVE failed to create " . $stateScript)
        :return
    }

    :local ok false
    :local lastErr "none"

    :for attempt from=1 to=3 do={
        :if ($ok = false) do={
            :do {
                /system script set $sid source=$out
                :local rb [/system script get $sid source]
                :local rbLen [:len $rb]

                :if ($rbLen != $outLen) do={
                    :set lastErr ("length mismatch outLen=" . $outLen . " readBackLen=" . $rbLen)
                } else={
                    :if ([:find $rb $markerStart] = nil) do={
                        :set lastErr "start marker missing after write"
                    } else={
                        :if ([:find $rb $markerEnd] = nil) do={
                            :set lastErr "end marker missing after write"
                        } else={
                            :set ok true
                        }
                    }
                }
            } on-error={
                :set lastErr ("write exception attempt=" . $attempt)
            }

            :if ($ok = false) do={
                :log warning ($tag . "write verify failed attempt=" . $attempt . " reason=" . $lastErr)
                :delay 1s
            }
        }
    }

    :if ($ok = false) do={
        :log error ($tag . "DISRUPTIVE failed to save " . $stateScript . " after retries reason=" . $lastErr)
        :return
    }

    :if ([:typeof $mbc3Debug] != "nothing") do={
        :if ($mbc3Debug = true) do={
            :log debug ($tag . "state saved ok target=" . $stateScript . " outLen=" . $outLen)
        }
    }
} on-error={
    :log error ($tag . "DISRUPTIVE unhandled save failure target=" . $stateScript . " outLen=" . $outLen)
}
