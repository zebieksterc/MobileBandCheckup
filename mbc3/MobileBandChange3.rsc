# MobileBandChange3
# revision: mbc3-final-20260602-p0003-inline-helpers
# scripts: MobileBandChange3.rsc  mbc3-restore-state.rsc
# scheduler: mbc3-restore-state (startup, once), mbc3-run (startup, 1m interval, :delay 50s)

:global mbc3LastPrimary
:global mbc3LastCA
:global mbc3LastCARaw
:global mbc3LogInited
:global mbc3Debug
:global mbc3DebugRaw
:global mbc3RunCount
:global mbc3HeartbeatEvery
:global mbc3HeartbeatCount
:global mbc3LastIfaceRunning
:global mbc3LastLRsrp
:global mbc3LastLSinr
:global mbc3LastNrActive
:global mbc3PendingLRsrp
:global mbc3PendingLRsrpCount
:global mbc3PendingLSinr
:global mbc3PendingLSinrCount
:global mbc3QualityMonitor

:global mbc3Probe
:global mbc3ProbeDetail
:global mbc3FailProbe

# Last-run snapshot — written at the start of each run before probe is reset.
# Survives a mid-run crash: if the script dies at "monitor-read", the next
# run snapshots that and you can query mbc3LastRunProbe to see where it failed.
:global mbc3LastRunProbe
:global mbc3LastRunProbeDetail
:global mbc3LastRunFailProbe

# Set by mbc3-restore-state on every boot. Checked here to guard against the
# scheduler race where mbc3-run fires before mbc3-restore-state has completed.
:global mbc3RestoreDone

:local iface "lte1"
:local logPrefix "[MobileBandChange3] "

# stateChanged drives the save decision.
# Set to true only for durable state commits that must survive reboot.
# Volatile debounce counters may change without forcing an immediate save.
# Save fires once at each exit point and at end of script.
:local stateChanged false

# -----------------------------
# Startup restore guard
# If mbc3-restore-state has not yet run this boot (mbc3RestoreDone is "nothing"),
# run it inline BEFORE reading any persisted state below (options + Last*/Pending*
# globals). Eliminates the scheduler race where mbc3-run fires before
# mbc3-restore-state; without this, the first post-boot run would read defaults
# instead of restored settings. Safe to call multiple times — mbc3-restore-state
# is idempotent. mbc3RestoreDone is not persisted; it clears on every reboot so
# this guard fires exactly once per boot on the first mbc3-run that wins the
# race.
# -----------------------------
:if ([:typeof $mbc3RestoreDone] = "nothing") do={
    /system script run mbc3-restore-state
}

# -----------------------------
# Runtime options from globals
# -----------------------------
:local debug false
:local debugRaw false
:local heartbeatEvery 60
:local qualityMonitor false

:if ([:typeof $mbc3Debug] != "nothing") do={ :set debug $mbc3Debug }
:if ([:typeof $mbc3DebugRaw] != "nothing") do={ :set debugRaw $mbc3DebugRaw }
:if ([:typeof $mbc3HeartbeatEvery] != "nothing") do={ :set heartbeatEvery $mbc3HeartbeatEvery }
:if ($heartbeatEvery < 1) do={ :set heartbeatEvery 60 }
:if ([:typeof $mbc3QualityMonitor] != "nothing") do={ :set qualityMonitor $mbc3QualityMonitor }

# -----------------------------
# Probe snapshot + init
# Snapshot the previous run's final probe state before overwriting.
# If the previous run crashed mid-flight, mbc3LastRunProbe tells you where.
# -----------------------------
:if ([:typeof $mbc3Probe] != "nothing") do={ :set mbc3LastRunProbe $mbc3Probe }
:if ([:typeof $mbc3ProbeDetail] != "nothing") do={ :set mbc3LastRunProbeDetail $mbc3ProbeDetail }
:if ([:typeof $mbc3FailProbe] != "nothing") do={ :set mbc3LastRunFailProbe $mbc3FailProbe }

:set mbc3Probe "start"
:set mbc3ProbeDetail "begin"
:set mbc3FailProbe "none"

# -----------------------------
# Helpers
# -----------------------------
:local joinArray do={
    :local arr $1
    :local sep $2
    :local out ""

    :if ([:typeof $arr] = "nothing") do={ :return "" }

    :if ([:typeof $arr] != "array") do={
        :return [:tostr $arr]
    }

    :foreach v in=$arr do={
        :local s [:tostr $v]
        :if ($s != "") do={
            :if ($out = "") do={
                :set out $s
            } else={
                :set out ($out . $sep . $s)
            }
        }
    }

    :return $out
}

:local getVal do={
    :local obj $1
    :local key $2
    :local def $3
    :local v ($obj->$key)

    :if ([:typeof $v] = "nothing") do={ :return $def }

    :if ([:typeof $v] = "array") do={
        :local j [$joinArray $v " | "]
        :if ($j = "") do={ :return $def }
        :return $j
    }

    :local s [:tostr $v]
    :if ($s = "") do={ :return $def }

    :return $s
}

:local formatDeciDb do={
    :local raw [:tostr $1]

    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }

    :local neg false
    :if ([:pick $raw 0 1] = "-") do={
        :set neg true
        :set raw [:pick $raw 1 [:len $raw]]
    }

    :if ($raw = "") do={ :return "-" }
    :if ([:len $raw] = 1) do={ :set raw ("0" . $raw) }

    :local whole [:pick $raw 0 ([:len $raw] - 1)]
    :local frac [:pick $raw ([:len $raw] - 1) [:len $raw]]

    :if ($whole = "") do={ :set whole "0" }

    :if ($neg = true) do={
        :return ("-" . $whole . "." . $frac)
    }

    :return ($whole . "." . $frac)
}

# Normalize CA only for comparison.
# Removes exact duplicates, preserves first-seen order.
:local normalizeCA do={
    :local input $1
    :local out ""
    :local used "|"

    :if ([:typeof $input] = "nothing") do={ :return "" }

    :if ([:typeof $input] = "array") do={
        :foreach item in=$input do={
            :local s [:tostr $item]
            :if ($s != "") do={
                :local marker ("|" . $s . "|")
                :if ([:typeof [:find $used $marker]] != "num") do={
                    :set used ($used . $s . "|")
                    :if ($out = "") do={
                        :set out $s
                    } else={
                        :set out ($out . " ; " . $s)
                    }
                }
            }
        }
        :return $out
    }

    :local s [:tostr $input]
    :if ($s = "") do={ :return "" }
    :return $s
}

:local extractAfterToken do={
    :local text [:tostr $1]
    :local token [:tostr $2]

    :local p [:find $text $token]
    :if ([:typeof $p] != "num") do={ :return "" }

    :local start ($p + [:len $token])
    :return [:pick $text $start [:len $text]]
}

:local extractBetweenTokens do={
    :local text [:tostr $1]
    :local startToken [:tostr $2]
    :local endToken [:tostr $3]

    :local p1 [:find $text $startToken]
    :if ([:typeof $p1] != "num") do={ :return "" }

    :local start ($p1 + [:len $startToken])
    :local tail [:pick $text $start [:len $text]]

    :local p2 [:find $tail $endToken]
    :if ([:typeof $p2] != "num") do={ :return $tail }

    :return [:pick $tail 0 $p2]
}

:local extractLeadingDigits do={
    :local text [:tostr $1]
    :local val ""

    :for i from=0 to=([:len $text] - 1) do={
        :local c [:pick $text $i ($i + 1)]
        :if ([:typeof [:find "0123456789" $c]] = "num") do={
            :set val ($val . $c)
        } else={
            :if ($val != "") do={ :break }
        }
    }

    :return $val
}

:local rsrpLabel do={
    :local raw [:tostr $1]
    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }
    :local v [:tonum $raw]
    :if ($v >= -80) do={ :return "excellent" }
    :if ($v >= -90) do={ :return "good" }
    :if ($v >= -100) do={ :return "fair" }
    :return "poor"
}

:local sinrLabel do={
    :local raw [:tostr $1]
    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }
    :local v [:tonum $raw]
    :if ($v >= 20) do={ :return "excellent" }
    :if ($v >= 13) do={ :return "good" }
    :if ($v >= 5) do={ :return "fair" }
    :return "poor"
}

:local cqiLabel do={
    :local raw [:tostr $1]
    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }
    :local v [:tonum $raw]
    :if ($v >= 12) do={ :return "excellent" }
    :if ($v >= 8) do={ :return "good" }
    :if ($v >= 5) do={ :return "fair" }
    :return "poor"
}

:local riLabel do={
    :local raw [:tostr $1]
    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }
    :local v [:tonum $raw]
    :if ($v >= 2) do={ :return "MIMO" }
    :if ($v = 1) do={ :return "single-stream" }
    :return "unknown"
}

:local mcsLabel do={
    :local raw [:tostr $1]
    :if ($raw = "") do={ :return "-" }
    :if ($raw = "-") do={ :return "-" }
    :local v [:tonum $raw]
    :if ($v <= 0) do={ :return "idle" }
    :if ($v < 10) do={ :return "low" }
    :if ($v < 20) do={ :return "medium" }
    :return "high"
}

# -----------------------------
# State persistence (inline, file-based — matches wd5gT/tdhT)
# Save writes mbc3-state.txt as parse-replay code (markers + :global/:set);
# mbc3-restore-state reads it back via [:parse] under an allow-list guard.
# Values are quoted+escaped so any content (";", quotes, spaces, $) survives.
# No external mbc3-save script.
#
# The three helpers (boolStr / intStr / escapeStr) live INSIDE the
# mbc3BuildState do={…} block. RouterOS function-value scoping does not expose
# `:local` definitions across a sibling `:local do={…}` boundary, so a helper
# declared at script-top would silently return nothing here — empirically
# observed before P-0003: every persisted `:set` for a bool/int variable came
# out with no value at all (escapeStr lines only looked populated because of
# the `$q . [...] . $q` literal-quote wrapper). Same precedent as tdhT.rsc
# (inline esc) and the two inline esc copies in wd5gT.rsc:
# "No cross-:do{} shared function in RouterOS -- change one, change all four."
# -----------------------------
:local mbc3BuildState do={
    :global mbc3Debug
    :global mbc3DebugRaw
    :global mbc3HeartbeatEvery
    :global mbc3QualityMonitor
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
    # escapeStr: escape \ " $ so a value survives a quoted :set re-parsed on
    # restore. Covered by mbc3-restore-state's allow-list guard which rejects
    # any unescaped $ in a saved value.
    :local escapeStr do={
        :if ([:typeof $1] = "nothing") do={ :return "" }
        :local s [:tostr $1]
        :local out ""
        :local slen [:len $s]
        :if ($slen = 0) do={ :return "" }
        :for i from=0 to=($slen - 1) do={
            :local c [:pick $s $i ($i + 1)]
            :if ($c = "\\") do={ :set out ($out . "\\\\") } else={
                :if ($c = "\"") do={ :set out ($out . "\\\"") } else={
                    :if ($c = "\$") do={ :set out ($out . "\\\$") } else={ :set out ($out . $c) }
                }
            }
        }
        :return $out
    }
    :local q "\""
    :return ("# MBC3-STATE-V1\n" . \
        ":global mbc3Debug\n:set mbc3Debug " . [$boolStr $mbc3Debug] . "\n" . \
        ":global mbc3DebugRaw\n:set mbc3DebugRaw " . [$boolStr $mbc3DebugRaw] . "\n" . \
        ":global mbc3HeartbeatEvery\n:set mbc3HeartbeatEvery " . [$intStr $mbc3HeartbeatEvery "60"] . "\n" . \
        ":global mbc3QualityMonitor\n:set mbc3QualityMonitor " . [$boolStr $mbc3QualityMonitor] . "\n" . \
        ":global mbc3LastPrimary\n:set mbc3LastPrimary " . $q . [$escapeStr $mbc3LastPrimary] . $q . "\n" . \
        ":global mbc3LastCA\n:set mbc3LastCA " . $q . [$escapeStr $mbc3LastCA] . $q . "\n" . \
        ":global mbc3LastCARaw\n:set mbc3LastCARaw " . $q . [$escapeStr $mbc3LastCARaw] . $q . "\n" . \
        ":global mbc3LastLRsrp\n:set mbc3LastLRsrp " . $q . [$escapeStr $mbc3LastLRsrp] . $q . "\n" . \
        ":global mbc3LastLSinr\n:set mbc3LastLSinr " . $q . [$escapeStr $mbc3LastLSinr] . $q . "\n" . \
        ":global mbc3LastNrActive\n:set mbc3LastNrActive " . [$boolStr $mbc3LastNrActive] . "\n" . \
        ":global mbc3PendingLRsrp\n:set mbc3PendingLRsrp " . $q . [$escapeStr $mbc3PendingLRsrp] . $q . "\n" . \
        ":global mbc3PendingLRsrpCount\n:set mbc3PendingLRsrpCount " . [$intStr $mbc3PendingLRsrpCount "0"] . "\n" . \
        ":global mbc3PendingLSinr\n:set mbc3PendingLSinr " . $q . [$escapeStr $mbc3PendingLSinr] . $q . "\n" . \
        ":global mbc3PendingLSinrCount\n:set mbc3PendingLSinrCount " . [$intStr $mbc3PendingLSinrCount "0"] . "\n" . \
        "# MBC3-STATE-END\n")
}

# -----------------------------
# Early state init
# Keeps counters and heartbeat alive even when interface is down.
# -----------------------------
:set mbc3Probe "early-state-init"
:set mbc3ProbeDetail "counters-and-iface-state"

:if ([:typeof $mbc3RunCount] = "nothing") do={ :set mbc3RunCount 0 }
:set mbc3RunCount ($mbc3RunCount + 1)

:if ([:typeof $mbc3HeartbeatCount] = "nothing") do={ :set mbc3HeartbeatCount 0 }
:if ([:typeof $mbc3LastIfaceRunning] = "nothing") do={ :set mbc3LastIfaceRunning true }
:if ([:typeof $mbc3LogInited] = "nothing") do={ :set mbc3LogInited false }

# -----------------------------
# Interface check
# -----------------------------
:set mbc3Probe "iface-check"
:set mbc3ProbeDetail "running-test"

:local ifaceRunning [/interface get $iface running]

:if ($ifaceRunning = false) do={
    :if ($mbc3LastIfaceRunning != false) do={
        :log warning ($logPrefix . "LTE iface-down interface=" . $iface . " running=false run-count=" . $mbc3RunCount)
        :set mbc3LastIfaceRunning false
        # Full state reset so recovery produces a clean init snapshot.
        :set mbc3LogInited false
        :set mbc3LastPrimary ""
        :set mbc3LastCA ""
        :set mbc3LastCARaw ""
        :set mbc3LastLRsrp ""
        :set mbc3LastLSinr ""
        :set mbc3LastNrActive false
        :set mbc3PendingLRsrp ""
        :set mbc3PendingLRsrpCount 0
        :set mbc3PendingLSinr ""
        :set mbc3PendingLSinrCount 0
        :set stateChanged true
    }
    :set mbc3FailProbe "iface-down"
    :set mbc3ProbeDetail "iface-not-running"
    :if ($debug = true) do={ :log debug ($logPrefix . "LTE iface not running - skipping poll") }
    :if ($stateChanged = true) do={
        :do {
            :local sf "mbc3-state.txt"
            :local pl [$mbc3BuildState]
            :if ([:len [/file find name=$sf]] > 0) do={ /file remove [find name=$sf] }
            /file print file=$sf
            :delay 200ms
            :local ff [/file find name=$sf]
            :if ([:len $ff] > 0) do={
                /file set $ff contents=$pl
                :if ([:typeof [:find [/file get $ff contents] "# MBC3-STATE-END"]] = "num") do={
                    :log info ($logPrefix . "state saved -> " . $sf)
                } else={
                    :log warning ($logPrefix . "state save: end marker missing after write")
                }
            } else={
                :log warning ($logPrefix . "state save: file not visible after 200ms")
            }
        } on-error={
            :log warning ($logPrefix . "inline state save failed")
        }
    }
    :return ""
}

:if ($mbc3LastIfaceRunning = false) do={
    :log warning ($logPrefix . "LTE iface-up-recovery interface=" . $iface . " running=true run-count=" . $mbc3RunCount)
}
:set mbc3LastIfaceRunning true

# -----------------------------
# Monitor read
# -----------------------------
:set mbc3Probe "monitor-read"
:set mbc3ProbeDetail "read-once"

:local mon [/interface lte monitor $iface once as-value]
:if ([:len $mon] = 0) do={
    :set mbc3FailProbe "monitor-empty"
    :set mbc3ProbeDetail "no-data-returned"
    :log warning ($logPrefix . "LTE monitor-empty interface=" . $iface . " running=true run-count=" . $mbc3RunCount . " detail=no-data-returned")
    # Nothing changed — no save needed.
    :return ""
}

:set mbc3ProbeDetail "monitor-ok"
:if ($debug = true) do={ :log debug ($logPrefix . "LTE monitor poll ok") }

# -----------------------------
# Raw values
# -----------------------------
:set mbc3Probe "raw-read"
:set mbc3ProbeDetail "extract-values"

:local rawDataClass [$getVal $mon "data-class" ""]
:if ($rawDataClass = "") do={
    :set rawDataClass [$getVal $mon "access-technology" "Unknown"]
}

:local rawDuplex [$getVal $mon "duplex-mode" "-"]
:local rawPrimary [$getVal $mon "primary-band" ""]

:local rawCAInput ($mon->"ca-band")
:local rawCAJoined ""
:if ([:typeof $rawCAInput] = "nothing") do={
    :set rawCAJoined ""
} else={
    :set rawCAJoined [$joinArray $rawCAInput " ; "]
}

:local rawRssi [$getVal $mon "rssi" "-"]
:local rawRsrp [$getVal $mon "rsrp" "-"]
:local rawSinr [$getVal $mon "sinr" "-"]
:local rawRsrq [$getVal $mon "rsrq" "-"]
:local rawCqi [$getVal $mon "cqi" "-"]
:local rawRi [$getVal $mon "ri" "-"]
:local rawMcs [$getVal $mon "mcs" "-"]

:local rawNrRsrp [$getVal $mon "nr-rsrp" "-"]
:local rawNrSinr [$getVal $mon "nr-sinr" "-"]
:local rawNrRsrq [$getVal $mon "nr-rsrq" "-"]

# -----------------------------
# Monitor validity guard
# RouterOS LTE monitor can return partial/empty values during modem startup.
# Do not update comparison state until the primary serving cell is available.
# -----------------------------
:set mbc3Probe "monitor-validate"
:set mbc3ProbeDetail "field-check"

:local primaryMissing false
:if ($rawPrimary = "") do={ :set primaryMissing true }
:if ($rawPrimary = "None") do={ :set primaryMissing true }
:if ($primaryMissing = true) do={
    :local missingFields "primary-band,"
    :if ($rawRsrp = "-") do={ :set missingFields ($missingFields . "rsrp,") }
    :if ($rawSinr = "-") do={ :set missingFields ($missingFields . "sinr,") }
    :if ($rawRsrq = "-") do={ :set missingFields ($missingFields . "rsrq,") }

    :set mbc3FailProbe "monitor-invalid"
    :set mbc3ProbeDetail ("missing-fields=" . $missingFields)

    :if ($mbc3LogInited != false) do={
        :set mbc3LogInited false
        :set stateChanged true
    }

    :log warning ($logPrefix . "LTE monitor-invalid interface=" . $iface . " run-count=" . $mbc3RunCount . " fields=" . $missingFields . " action=skip-state-update")
    :if ($stateChanged = true) do={
        :do {
            :local sf "mbc3-state.txt"
            :local pl [$mbc3BuildState]
            :if ([:len [/file find name=$sf]] > 0) do={ /file remove [find name=$sf] }
            /file print file=$sf
            :delay 200ms
            :local ff [/file find name=$sf]
            :if ([:len $ff] > 0) do={
                /file set $ff contents=$pl
                :if ([:typeof [:find [/file get $ff contents] "# MBC3-STATE-END"]] = "num") do={
                    :log info ($logPrefix . "state saved -> " . $sf)
                } else={
                    :log warning ($logPrefix . "state save: end marker missing after write")
                }
            } else={
                :log warning ($logPrefix . "state save: file not visible after 200ms")
            }
        } on-error={
            :log warning ($logPrefix . "inline state save failed")
        }
    }
    :return ""
}

# -----------------------------
# Derived / formatted values
# -----------------------------
:set mbc3Probe "format"
:set mbc3ProbeDetail "normalize-and-label"

:local usedTech $rawDataClass
:local usedDuplex $rawDuplex
:local usedPrimary $rawPrimary

:local displayCA $rawCAJoined
:if ($displayCA = "") do={ :set displayCA "None" }

:local compareCA [$normalizeCA $rawCAInput]
:if ($compareCA = "") do={ :set compareCA $rawCAJoined }
:if ($compareCA = "") do={ :set compareCA "None" }

:local usedRsrq [$formatDeciDb $rawRsrq]
:local usedNrRsrq [$formatDeciDb $rawNrRsrq]

:local usedRssi $rawRssi
:local usedRsrp $rawRsrp
:local usedSinr $rawSinr
:local usedCqi $rawCqi
:local usedRi $rawRi
:local usedMcs $rawMcs

:local usedNrRsrp $rawNrRsrp
:local usedNrSinr $rawNrSinr

:local lRsrp [$rsrpLabel $usedRsrp]
:local lSinr [$sinrLabel $usedSinr]
:local lCqi [$cqiLabel $usedCqi]
:local lRi [$riLabel $usedRi]
:local lMcs [$mcsLabel $usedMcs]

:local lNrRsrp [$rsrpLabel $usedNrRsrp]
:local lNrSinr [$sinrLabel $usedNrSinr]

:local nrActive false
:if ($usedNrRsrp != "-") do={
    :if ($usedNrRsrp != "") do={ :set nrActive true }
}

# -----------------------------
# Log lines
# -----------------------------
:local techLine ("LTE tech data-class=\"" . $usedTech . "\" duplex=\"" . $usedDuplex . "\"")
:local primaryLine ("LTE primary=\"" . $usedPrimary . "\"")
:local caLine ("LTE ca-bands=\"" . $displayCA . "\"")

:local lteLine ("LTE metrics rssi=" . $usedRssi . "dBm rsrp=" . $usedRsrp . "dBm(" . $lRsrp . ") sinr=" . $usedSinr . "dB(" . $lSinr . ") rsrq=" . $usedRsrq . "dB cqi=" . $usedCqi . "(" . $lCqi . ") ri=" . $usedRi . "(" . $lRi . ") mcs=" . $usedMcs . "(" . $lMcs . ")")
:local nrLine ("NR metrics rsrp=" . $usedNrRsrp . "dBm(" . $lNrRsrp . ") sinr=" . $usedNrSinr . "dB(" . $lNrSinr . ") rsrq=" . $usedNrRsrq . "dB")

:local rawLteLine ("LTE raw metrics rssi=" . $rawRssi . " rsrp=" . $rawRsrp . " sinr=" . $rawSinr . " rsrq=" . $rawRsrq . " cqi=" . $rawCqi . " ri=" . $rawRi . " mcs=" . $rawMcs)
:local rawNrLine ("NR raw metrics rsrp=" . $rawNrRsrp . " sinr=" . $rawNrSinr . " rsrq=" . $rawNrRsrq)

# -----------------------------
# Debug
# -----------------------------
:if ($debug = true) do={
    :log debug ($logPrefix . "LTE raw-ca=" . $rawCAJoined . " compare-ca=" . $compareCA . " display-ca=" . $displayCA)
    :log debug ($logPrefix . "LTE raw-rsrq=" . $rawRsrq . " used-rsrq=" . $usedRsrq . " raw-nr-rsrq=" . $rawNrRsrq . " used-nr-rsrq=" . $usedNrRsrq)
}

# -----------------------------
# Safe global init
# -----------------------------
:set mbc3Probe "state-init"
:set mbc3ProbeDetail "globals-check"

:if ([:typeof $mbc3LastPrimary] = "nothing") do={ :set mbc3LastPrimary "" }
:if ([:typeof $mbc3LastCA] = "nothing") do={ :set mbc3LastCA "" }
:if ([:typeof $mbc3LastCARaw] = "nothing") do={ :set mbc3LastCARaw "" }
:if ([:typeof $mbc3LastLRsrp] = "nothing") do={ :set mbc3LastLRsrp "" }
:if ([:typeof $mbc3LastLSinr] = "nothing") do={ :set mbc3LastLSinr "" }
:if ([:typeof $mbc3LastNrActive] = "nothing") do={ :set mbc3LastNrActive false }
:if ([:typeof $mbc3PendingLRsrp] = "nothing") do={ :set mbc3PendingLRsrp "" }
:if ([:typeof $mbc3PendingLRsrpCount] = "nothing") do={ :set mbc3PendingLRsrpCount 0 }
:if ([:typeof $mbc3PendingLSinr] = "nothing") do={ :set mbc3PendingLSinr "" }
:if ([:typeof $mbc3PendingLSinrCount] = "nothing") do={ :set mbc3PendingLSinrCount 0 }
:if ([:typeof $mbc3LastRunProbe] = "nothing") do={ :set mbc3LastRunProbe "" }
:if ([:typeof $mbc3LastRunProbeDetail] = "nothing") do={ :set mbc3LastRunProbeDetail "" }
:if ([:typeof $mbc3LastRunFailProbe] = "nothing") do={ :set mbc3LastRunFailProbe "" }

:if ($mbc3LogInited = true) do={
    :if ($mbc3LastPrimary = "") do={
        :set mbc3LastPrimary $usedPrimary
        :set mbc3FailProbe "state-repair"
        :set mbc3ProbeDetail "repaired-lastPrimary"
        :log warning ($logPrefix . "LTE state-repair repaired=mbc3LastPrimary")
        :set stateChanged true
    }
}

:if ($mbc3LogInited = true) do={
    :if ($mbc3LastCA = "") do={
        :set mbc3LastCA $compareCA
        :set mbc3FailProbe "state-repair"
        :set mbc3ProbeDetail "repaired-lastCA"
        :log warning ($logPrefix . "LTE state-repair repaired=mbc3LastCA")
        :set stateChanged true
    }
}

:if ($mbc3LogInited = true) do={
    :if ($mbc3LastCARaw = "") do={
        :set mbc3LastCARaw $rawCAJoined
        :set mbc3FailProbe "state-repair"
        :set mbc3ProbeDetail "repaired-lastCARaw"
        :log warning ($logPrefix . "LTE state-repair repaired=mbc3LastCARaw")
        :set stateChanged true
    }
}

# -----------------------------
# Init
# -----------------------------
:if ($mbc3LogInited != true) do={
    :set mbc3Probe "log-init"
    :set mbc3ProbeDetail "init-event"

    :set mbc3LastPrimary $usedPrimary
    :set mbc3LastCA $compareCA
    :set mbc3LastCARaw $rawCAJoined
    :set mbc3LastLRsrp $lRsrp
    :set mbc3LastLSinr $lSinr
    :set mbc3LastNrActive $nrActive
    :set mbc3PendingLRsrp ""
    :set mbc3PendingLRsrpCount 0
    :set mbc3PendingLSinr ""
    :set mbc3PendingLSinrCount 0
    # Seed heartbeat count so first heartbeat fires on schedule.
    :set mbc3HeartbeatCount 1
    :set mbc3LogInited true
    :set stateChanged true

    :log warning ($logPrefix . "LTE init")
    :log warning ($logPrefix . $techLine)
    :log warning ($logPrefix . $primaryLine)
    :log warning ($logPrefix . $caLine)
    :log warning ($logPrefix . $lteLine)
    :log warning ($logPrefix . $nrLine)

    :if ($debugRaw = true) do={
        :log debug ($logPrefix . $rawLteLine)
        :log debug ($logPrefix . $rawNrLine)
    }

    # Save here before the early return — init is the only exit path that
    # cannot reach the save call at the bottom of the script.
    :do {
        :local sf "mbc3-state.txt"
        :local pl [$mbc3BuildState]
        :if ([:len [/file find name=$sf]] > 0) do={ /file remove [find name=$sf] }
        /file print file=$sf
        :delay 200ms
        :local ff [/file find name=$sf]
        :if ([:len $ff] > 0) do={
            /file set $ff contents=$pl
            :if ([:typeof [:find [/file get $ff contents] "# MBC3-STATE-END"]] = "num") do={
                :log info ($logPrefix . "state saved -> " . $sf)
            } else={
                :log warning ($logPrefix . "state save: end marker missing after write")
            }
        } else={
            :log warning ($logPrefix . "state save: file not visible after 200ms")
        }
    } on-error={
        :log warning ($logPrefix . "inline state save failed")
    }

    :set mbc3Probe "done"
    :set mbc3ProbeDetail "done"
    :set mbc3FailProbe "none"
    :return ""
}

# -----------------------------
# NR connect / disconnect
# -----------------------------
:set mbc3Probe "compare-nr"
:set mbc3ProbeDetail "nr-active-check"

:if ($nrActive != $mbc3LastNrActive) do={
    :set mbc3Probe "log-nr"
    :if ($nrActive = true) do={
        :set mbc3ProbeDetail "nr-connected"
        :log warning ($logPrefix . "NR connected")
    } else={
        :set mbc3ProbeDetail "nr-disconnected"
        :log warning ($logPrefix . "NR disconnected")
    }
    :log warning ($logPrefix . $techLine)
    :log warning ($logPrefix . $primaryLine)
    :log warning ($logPrefix . $caLine)
    :log warning ($logPrefix . $lteLine)
    :log warning ($logPrefix . $nrLine)
    :if ($debugRaw = true) do={
        :log debug ($logPrefix . $rawLteLine)
        :log debug ($logPrefix . $rawNrLine)
    }
    :set mbc3LastNrActive $nrActive
    :set stateChanged true
}

# -----------------------------
# Primary change
# -----------------------------
:set mbc3Probe "compare-primary"
:set mbc3ProbeDetail "primary-check"

:if ($usedPrimary != $mbc3LastPrimary) do={
    :set mbc3Probe "primary-parse"
    :set mbc3ProbeDetail "extract-band-earfcn-pci"

    :local oldBand ""
    :local newBand ""

    :local pOldBand [:find $mbc3LastPrimary "@"]
    :if ([:typeof $pOldBand] != "num") do={
        :set oldBand $mbc3LastPrimary
    } else={
        :set oldBand [:pick $mbc3LastPrimary 0 $pOldBand]
    }

    :local pNewBand [:find $usedPrimary "@"]
    :if ([:typeof $pNewBand] != "num") do={
        :set newBand $usedPrimary
    } else={
        :set newBand [:pick $usedPrimary 0 $pNewBand]
    }

    :local oldEarfcn [$extractBetweenTokens $mbc3LastPrimary "earfcn: " " phy-cellid:"]
    :local newEarfcn [$extractBetweenTokens $usedPrimary "earfcn: " " phy-cellid:"]

    :local oldPci [$extractLeadingDigits [$extractAfterToken $mbc3LastPrimary "phy-cellid: "]]
    :local newPci [$extractLeadingDigits [$extractAfterToken $usedPrimary "phy-cellid: "]]

    :local primaryChangeType "details-change"

    :if ($oldBand != $newBand) do={
        :set primaryChangeType "band-change"
    } else={
        :if ($oldEarfcn != $newEarfcn) do={
            :set primaryChangeType "earfcn-change"
        } else={
            :if ($oldPci != $newPci) do={
                :set primaryChangeType "phy-cellid-change"
            }
        }
    }

    :set mbc3Probe "log-primary"
    :set mbc3ProbeDetail $primaryChangeType

    :log warning ($logPrefix . "LTE primary-switch type=" . $primaryChangeType . " oldBand=" . $oldBand . " newBand=" . $newBand . " oldEarfcn=" . $oldEarfcn . " newEarfcn=" . $newEarfcn . " oldPci=" . $oldPci . " newPci=" . $newPci)
    :log warning ($logPrefix . "LTE primary-from=\"" . $mbc3LastPrimary . "\"")
    :log warning ($logPrefix . "LTE primary-to=\"" . $usedPrimary . "\"")
    :log warning ($logPrefix . $techLine)
    :log warning ($logPrefix . $primaryLine)
    :log warning ($logPrefix . $caLine)
    :log warning ($logPrefix . $lteLine)
    :log warning ($logPrefix . $nrLine)

    :if ($debugRaw = true) do={
        :log debug ($logPrefix . $rawLteLine)
        :log debug ($logPrefix . $rawNrLine)
    }

    :set mbc3LastPrimary $usedPrimary
    :set mbc3LastCA $compareCA
    :set mbc3LastCARaw $rawCAJoined
    :set stateChanged true
}

# -----------------------------
# CA change / CA raw-only change
# -----------------------------
:set mbc3Probe "compare-ca"
:set mbc3ProbeDetail "ca-check"

:if ($compareCA != $mbc3LastCA) do={
    :if ($debug = true) do={
        :log debug ($logPrefix . "LTE compareCA-old=\"" . $mbc3LastCA . "\"")
        :log debug ($logPrefix . "LTE compareCA-new=\"" . $compareCA . "\"")
    }

    :set mbc3Probe "log-ca"
    :set mbc3ProbeDetail "ca-composition-change"

    :if ($compareCA = "None") do={
        :if ($mbc3LastCA != "None") do={
            :log warning ($logPrefix . "LTE ca-drop-to-none degradation=yes")
        }
    }

    :log warning ($logPrefix . "LTE ca-composition-change")
    :log warning ($logPrefix . "LTE ca-from=\"" . $mbc3LastCA . "\"")
    :log warning ($logPrefix . "LTE ca-to=\"" . $compareCA . "\"")
    :log warning ($logPrefix . $techLine)
    :log warning ($logPrefix . $primaryLine)
    :log warning ($logPrefix . $caLine)
    :log warning ($logPrefix . $lteLine)
    :log warning ($logPrefix . $nrLine)

    :if ($debugRaw = true) do={
        :log debug ($logPrefix . "LTE ca-raw-from=\"" . $mbc3LastCARaw . "\"")
        :log debug ($logPrefix . "LTE ca-raw-to=\"" . $rawCAJoined . "\"")
        :log debug ($logPrefix . $rawLteLine)
        :log debug ($logPrefix . $rawNrLine)
    }

    :set mbc3LastCA $compareCA
    :set mbc3LastCARaw $rawCAJoined
    :set stateChanged true

} else={
    :if ($rawCAJoined != $mbc3LastCARaw) do={
        :if ($rawCAJoined != "") do={
            :if ($mbc3LastCARaw != "") do={
        :set mbc3Probe "log-ca"
        :set mbc3ProbeDetail "ca-raw-change"

        :log warning ($logPrefix . "LTE ca-raw-change only normalized-same=yes")
        :log warning ($logPrefix . "LTE ca-raw-from=\"" . $mbc3LastCARaw . "\"")
        :log warning ($logPrefix . "LTE ca-raw-to=\"" . $rawCAJoined . "\"")
        :log warning ($logPrefix . $techLine)
        :log warning ($logPrefix . $primaryLine)
        :log warning ($logPrefix . $caLine)
        :log warning ($logPrefix . $lteLine)
        :log warning ($logPrefix . $nrLine)

        :set mbc3LastCARaw $rawCAJoined
        :set stateChanged true
            }
        }
    }
}

# -----------------------------
# Signal quality label transitions
# 2-run debounce: quality event fires only when new class is seen twice in a row.
# Prevents noise from signals hovering near class thresholds.
# Disabled entirely when mbc3QualityMonitor = false — no events, no saves.
# -----------------------------
:set mbc3Probe "compare-quality"
:set mbc3ProbeDetail "label-check-debounced"

:if ($qualityMonitor = true) do={

    :local doLRsrpDebounce false
    :if ($mbc3LastLRsrp != "") do={
        :if ($lRsrp != "-") do={
            :if ($lRsrp != $mbc3LastLRsrp) do={ :set doLRsrpDebounce true }
        }
    }
    :if ($doLRsrpDebounce = true) do={
        :if ($mbc3PendingLRsrp = $lRsrp) do={
            :set mbc3PendingLRsrpCount ($mbc3PendingLRsrpCount + 1)
        } else={
            :set mbc3PendingLRsrp $lRsrp
            :set mbc3PendingLRsrpCount 1
        }
        :if ($mbc3PendingLRsrpCount >= 2) do={
            :log warning ($logPrefix . "LTE rsrp-quality-change from=" . $mbc3LastLRsrp . " to=" . $lRsrp . " rsrp=" . $usedRsrp . "dBm primary=\"" . $usedPrimary . "\" ca=\"" . $compareCA . "\"")
            :set mbc3LastLRsrp $lRsrp
            :set mbc3PendingLRsrp ""
            :set mbc3PendingLRsrpCount 0
            :set stateChanged true
        }
    } else={
        :local doResetLRsrp false
        :if ($mbc3PendingLRsrp != "") do={ :set doResetLRsrp true }
        :if ($mbc3PendingLRsrpCount != 0) do={ :set doResetLRsrp true }
        :if ($doResetLRsrp = true) do={
            :set mbc3PendingLRsrp ""
            :set mbc3PendingLRsrpCount 0
        }
        :if ($lRsrp != "-") do={
            :if ($mbc3LastLRsrp != $lRsrp) do={
                :set mbc3LastLRsrp $lRsrp
                :set stateChanged true
            }
        }
    }

    :local doLSinrDebounce false
    :if ($mbc3LastLSinr != "") do={
        :if ($lSinr != "-") do={
            :if ($lSinr != $mbc3LastLSinr) do={ :set doLSinrDebounce true }
        }
    }
    :if ($doLSinrDebounce = true) do={
        :if ($mbc3PendingLSinr = $lSinr) do={
            :set mbc3PendingLSinrCount ($mbc3PendingLSinrCount + 1)
        } else={
            :set mbc3PendingLSinr $lSinr
            :set mbc3PendingLSinrCount 1
        }
        :if ($mbc3PendingLSinrCount >= 2) do={
            :log warning ($logPrefix . "LTE sinr-quality-change from=" . $mbc3LastLSinr . " to=" . $lSinr . " sinr=" . $usedSinr . "dB primary=\"" . $usedPrimary . "\" ca=\"" . $compareCA . "\"")
            :set mbc3LastLSinr $lSinr
            :set mbc3PendingLSinr ""
            :set mbc3PendingLSinrCount 0
            :set stateChanged true
        }
    } else={
        :local doResetLSinr false
        :if ($mbc3PendingLSinr != "") do={ :set doResetLSinr true }
        :if ($mbc3PendingLSinrCount != 0) do={ :set doResetLSinr true }
        :if ($doResetLSinr = true) do={
            :set mbc3PendingLSinr ""
            :set mbc3PendingLSinrCount 0
        }
        :if ($lSinr != "-") do={
            :if ($mbc3LastLSinr != $lSinr) do={
                :set mbc3LastLSinr $lSinr
                :set stateChanged true
            }
        }
    }

} else={
    :set mbc3ProbeDetail "quality-monitoring-disabled"
}

# -----------------------------
# Heartbeat
# Periodic one-line liveness snapshot. Also forces a rare save to confirm state
# is fresh during long quiet periods even when nothing changes. Default 60 runs.
# (Band switches / CA changes / iface up-down are logged as warnings when they
# happen, so this is just the "still alive, nothing changed" beat.)
# -----------------------------
:set mbc3Probe "heartbeat"
:set mbc3ProbeDetail "heartbeat-check"

:set mbc3HeartbeatCount ($mbc3HeartbeatCount + 1)
:if ($mbc3HeartbeatCount >= $heartbeatEvery) do={
    :set mbc3HeartbeatCount 0
    :log info ($logPrefix . "heartbeat run-count=" . $mbc3RunCount . " primary=\"" . $usedPrimary . "\" rsrp=" . $usedRsrp . "dBm(" . $lRsrp . ") sinr=" . $usedSinr . "dB(" . $lSinr . ") nr-rsrp=" . $usedNrRsrp . "dBm(" . $lNrRsrp . ")")
    :if ($debugRaw = true) do={
        :log debug ($logPrefix . $rawLteLine)
        :log debug ($logPrefix . $rawNrLine)
    }
    :set stateChanged true
}

# -----------------------------
# Save on any state change
# -----------------------------
:if ($stateChanged = true) do={
    :do {
        :local sf "mbc3-state.txt"
        :local pl [$mbc3BuildState]
        :if ([:len [/file find name=$sf]] > 0) do={ /file remove [find name=$sf] }
        /file print file=$sf
        :delay 200ms
        :local ff [/file find name=$sf]
        :if ([:len $ff] > 0) do={
            /file set $ff contents=$pl
            :if ([:typeof [:find [/file get $ff contents] "# MBC3-STATE-END"]] = "num") do={
                :log info ($logPrefix . "state saved -> " . $sf)
            } else={
                :log warning ($logPrefix . "state save: end marker missing after write")
            }
        } else={
            :log warning ($logPrefix . "state save: file not visible after 200ms")
        }
    } on-error={
        :log warning ($logPrefix . "inline state save failed")
    }
}

:set mbc3Probe "done"
:set mbc3ProbeDetail "done"
:set mbc3FailProbe "none"

:return ""
